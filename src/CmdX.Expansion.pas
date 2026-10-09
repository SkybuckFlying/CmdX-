unit CmdX.Expansion;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX.Types;

function ExpandLine(const AInput: string; Session: TSession; IsBatch: Boolean; Args: TStringList = nil): string;
function ExpandSubstringsAndReplacements(const VarName, VarVal: string): string;

implementation

function ExpandSubstringsAndReplacements(const VarName, VarVal: string): string;
var
  ColonPos, TildePos, EqPos, ErrCode: Integer;
  ActualName, Modifier, SubStr, OldStr, NewStr: string;
  StartIdx, LenIdx: Integer;
  CommaPos: Integer;
begin
  ColonPos := Pos(':', VarName);
  if ColonPos = 0 then
    Exit(VarVal);

  ActualName := Copy(VarName, 1, ColonPos - 1);
  Modifier := Copy(VarName, ColonPos + 1, Length(VarName));

  if Modifier = '' then
    Exit(VarVal);

  { Substring operation: ~n or ~n,m }
  if Modifier[1] = '~' then
  begin
    Modifier := Copy(Modifier, 2, Length(Modifier));
    CommaPos := Pos(',', Modifier);
    if CommaPos > 0 then
    begin
      Val(Copy(Modifier, 1, CommaPos - 1), StartIdx, ErrCode);
      Val(Copy(Modifier, CommaPos + 1, Length(Modifier)), LenIdx, ErrCode);
    end
    else
    begin
      Val(Modifier, StartIdx, ErrCode);
      LenIdx := Length(VarVal);
    end;

    if StartIdx < 0 then
      StartIdx := Length(VarVal) + StartIdx;
    if StartIdx < 0 then StartIdx := 0;

    { Note: 0-based indexing in cmd.exe }
    if StartIdx >= Length(VarVal) then
      Exit('')
    else
    begin
      if LenIdx < 0 then
        LenIdx := (Length(VarVal) + LenIdx) - StartIdx;
      if LenIdx <= 0 then Exit('');

      Result := Copy(VarVal, StartIdx + 1, LenIdx);
      Exit;
    end;
  end;

  { Substitution operation: old=new }
  EqPos := Pos('=', Modifier);
  if EqPos > 0 then
  begin
    OldStr := Copy(Modifier, 1, EqPos - 1);
    NewStr := Copy(Modifier, EqPos + 1, Length(Modifier));
    if OldStr <> '' then
      Exit(StringReplace(VarVal, OldStr, NewStr, [rfReplaceAll, rfIgnoreCase]))
    else
      Exit(VarVal);
  end;

  Result := VarVal;
end;

function ExpandLine(const AInput: string; Session: TSession; IsBatch: Boolean; Args: TStringList): string;
var
  I, N, PercentEnd, ExclEnd: Integer;
  InQuotes: Boolean;
  C, NextC: Char;
  VarName, VarVal, ExpansionResult: string;
  ArgIdx, ErrCode: Integer;
  ModStr: string;
  StripQuotes: Boolean;
begin
  Result := '';
  InQuotes := False;
  I := 1;
  N := Length(AInput);

  while I <= N do
  begin
    C := AInput[I];

    { Handle Caret Escaping outside quotes }
    if (C = '^') and (not InQuotes) and (I < N) then
    begin
      NextC := AInput[I + 1];
      Result := Result + NextC;
      Inc(I, 2);
      Continue;
    end;

    if C = '"' then
    begin
      InQuotes := not InQuotes;
      Result := Result + C;
      Inc(I);
      Continue;
    end;

    { Immediate Percent Expansion (%VAR% or %1..%9) }
    if C = '%' then
    begin
      { Double percent inside batch => single percent }
      if (I < N) and (AInput[I + 1] = '%') then
      begin
        if IsBatch then
          Result := Result + '%'
        else
          Result := Result + '%%';
        Inc(I, 2);
        Continue;
      end;

      { Batch Arguments: %0..%9 or %* or %~1..%~9 }
      if IsBatch and (Args <> nil) and (I < N) then
      begin
        StripQuotes := False;
        ModStr := '';
        if (AInput[I + 1] = '~') and (I + 2 <= N) then
        begin
          StripQuotes := True;
          ModStr := AInput[I + 2];
          Val(ModStr, ArgIdx, ErrCode);
          if ErrCode = 0 then
          begin
            if ArgIdx < Args.Count then
            begin
              VarVal := Args[ArgIdx];
              if StripQuotes and (Length(VarVal) >= 2) and (VarVal[1] = '"') and (VarVal[Length(VarVal)] = '"') then
                VarVal := Copy(VarVal, 2, Length(VarVal) - 2);
              Result := Result + VarVal;
            end;
            Inc(I, 3);
            Continue;
          end;
        end
        else if AInput[I + 1] = '*' then
        begin
          { %* expands to all arguments }
          VarVal := '';
          for ArgIdx := 1 to Args.Count - 1 do
          begin
            if ArgIdx > 1 then VarVal := VarVal + ' ';
            VarVal := VarVal + Args[ArgIdx];
          end;
          Result := Result + VarVal;
          Inc(I, 2);
          Continue;
        end;

        ModStr := AInput[I + 1];
        Val(ModStr, ArgIdx, ErrCode);
        if ErrCode = 0 then
        begin
          if ArgIdx < Args.Count then
            Result := Result + Args[ArgIdx];
          Inc(I, 2);
          Continue;
        end;
      end;

      { Look for closing % }
      PercentEnd := 0;
      for ExclEnd := I + 1 to N do
      begin
        if AInput[ExclEnd] = '%' then
        begin
          PercentEnd := ExclEnd;
          Break;
        end;
      end;

      if PercentEnd > I + 1 then
      begin
        VarName := Copy(AInput, I + 1, PercentEnd - (I + 1));
        if SameText(VarName, 'errorlevel') then
          VarVal := IntToStr(Session.ErrorLevel)
        else if SameText(VarName, 'cd') then
          VarVal := Session.CurrentDir
        else
        begin
          if Pos(':', VarName) > 0 then
          begin
            ModStr := Copy(VarName, 1, Pos(':', VarName) - 1);
            if Session.GetVar(ModStr, VarVal) then
              VarVal := ExpandSubstringsAndReplacements(VarName, VarVal)
            else
              VarVal := '';
          end
          else if not Session.GetVar(VarName, VarVal) then
            VarVal := '';
        end;

        Result := Result + VarVal;
        I := PercentEnd + 1;
        Continue;
      end;
    end;

    { Delayed Expansion (!VAR!) }
    if (C = '!') and Session.DelayedExpansion then
    begin
      ExclEnd := 0;
      for PercentEnd := I + 1 to N do
      begin
        if AInput[PercentEnd] = '!' then
        begin
          ExclEnd := PercentEnd;
          Break;
        end;
      end;

      if ExclEnd > I + 1 then
      begin
        VarName := Copy(AInput, I + 1, ExclEnd - (I + 1));
        if SameText(VarName, 'errorlevel') then
          VarVal := IntToStr(Session.ErrorLevel)
        else if SameText(VarName, 'cd') then
          VarVal := Session.CurrentDir
        else
        begin
          if Pos(':', VarName) > 0 then
          begin
            ModStr := Copy(VarName, 1, Pos(':', VarName) - 1);
            if Session.GetVar(ModStr, VarVal) then
              VarVal := ExpandSubstringsAndReplacements(VarName, VarVal)
            else
              VarVal := '';
          end
          else if not Session.GetVar(VarName, VarVal) then
            VarVal := '';
        end;

        Result := Result + VarVal;
        I := ExclEnd + 1;
        Continue;
      end;
    end;

    Result := Result + C;
    Inc(I);
  end;
end;

end.
