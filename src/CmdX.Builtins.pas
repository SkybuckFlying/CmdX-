unit CmdX.Builtins;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, StrUtils, Generics.Collections, CmdX.Types, CmdX.Expansion;

function IsBuiltinCommand(const CmdName: string): Boolean;
function ExecuteBuiltin(const CmdName: string; Args: TStringList; Session: TSession): Integer;

implementation

function IsBuiltinCommand(const CmdName: string): Boolean;
var
  Up: string;
begin
  Up := UpperCase(CmdName);
  Result := (Up = 'DIR') or (Up = 'CD') or (Up = 'CHDIR') or (Up = 'MD') or (Up = 'MKDIR') or
            (Up = 'RD') or (Up = 'RMDIR') or (Up = 'DEL') or (Up = 'ERASE') or
            (Up = 'COPY') or (Up = 'MOVE') or (Up = 'REN') or (Up = 'RENAME') or
            (Up = 'TYPE') or (Up = 'CLS') or (Up = 'VER') or (Up = 'VOL') or
            (Up = 'DATE') or (Up = 'TIME') or (Up = 'ECHO') or (Up = 'SET') or
            (Up = 'PATH') or (Up = 'PROMPT') or (Up = 'TITLE') or (Up = 'COLOR') or
            (Up = 'PAUSE') or (Up = 'EXIT') or (Up = 'SHIFT') or (Up = 'REM') or
            (Up = 'SETLOCAL') or (Up = 'ENDLOCAL') or (Up = 'IF') or (Up = 'FOR');
end;

function ExecuteDir(Args: TStringList; Session: TSession): Integer;
var
  SearchPath, SearchPattern: string;
  SR: TSearchRec;
  Count, TotalSize: Int64;
begin
  SearchPath := Session.CurrentDir;
  if (Args.Count > 0) and (Copy(Args[0], 1, 1) <> '/') then
    SearchPath := ExpandFileName(Args[0]);

  if DirectoryExists(SearchPath) then
    SearchPattern := IncludeTrailingPathDelimiter(SearchPath) + '*.*'
  else
    SearchPattern := SearchPath;

  Writeln(' Directory of ', ExtractFilePath(SearchPattern));
  Writeln;

  Count := 0;
  TotalSize := 0;
  if FindFirst(SearchPattern, faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) <> 0 then
          Writeln(Format('%-20s <DIR>          %s', [DateTimeToStr(FileDateToDateTime(SR.Time)), SR.Name]))
        else
        begin
          Writeln(Format('%-20s %14d %s', [DateTimeToStr(FileDateToDateTime(SR.Time)), SR.Size, SR.Name]));
          Inc(TotalSize, SR.Size);
        end;
        Inc(Count);
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;

  Writeln(Format('               %d File(s) %14d bytes', [Count, TotalSize]));
  Result := 0;
end;

function ExecuteCd(Args: TStringList; Session: TSession): Integer;
var
  NewDir: string;
begin
  if Args.Count = 0 then
  begin
    Writeln(Session.CurrentDir);
    Exit(0);
  end;

  NewDir := Args[0];
  if SameText(NewDir, '/d') then
  begin
    if Args.Count > 1 then NewDir := Args[1] else NewDir := Session.CurrentDir;
  end;

  NewDir := ExpandFileName(NewDir);
  if DirectoryExists(NewDir) then
  begin
    Session.CurrentDir := NewDir;
    SetCurrentDir(NewDir);
    Exit(0);
  end;
  Writeln('The system cannot find the path specified.');
  Result := 1;
end;

function ExecuteMd(Args: TStringList; Session: TSession): Integer;
var
  Target: string;
begin
  if Args.Count = 0 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Target := ExpandFileName(Args[0]);
  if CreateDir(Target) then
    Result := 0
  else
  begin
    Writeln('A subdirectory or file ', Target, ' already exists or cannot be created.');
    Result := 1;
  end;
end;

function ExecuteRd(Args: TStringList; Session: TSession): Integer;
var
  Target: string;
begin
  if Args.Count = 0 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Target := ExpandFileName(Args[0]);
  if RemoveDir(Target) then
    Result := 0
  else
  begin
    Writeln('The system cannot find the file specified.');
    Result := 1;
  end;
end;

function ExecuteDel(Args: TStringList; Session: TSession): Integer;
var
  Target: string;
  SR: TSearchRec;
  Success: Boolean;
begin
  if Args.Count = 0 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Target := ExpandFileName(Args[0]);
  Success := False;

  if FindFirst(Target, faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
      begin
        if DeleteFile(ExtractFilePath(Target) + SR.Name) then
          Success := True;
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;

  if Success then Result := 0
  else
  begin
    Writeln('Could Not Find ', Target);
    Result := 1;
  end;
end;

function ExecuteCopy(Args: TStringList; Session: TSession): Integer;
var
  Src, Dst: string;
  InStream, OutStream: TFileStream;
begin
  if Args.Count < 2 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Src := ExpandFileName(Args[0]);
  Dst := ExpandFileName(Args[1]);

  if DirectoryExists(Dst) then
    Dst := IncludeTrailingPathDelimiter(Dst) + ExtractFileName(Src);

  try
    InStream := TFileStream.Create(Src, fmOpenRead or fmShareDenyNone);
    try
      OutStream := TFileStream.Create(Dst, fmCreate);
      try
        OutStream.CopyFrom(InStream, InStream.Size);
        Writeln('        1 file(s) copied.');
        Result := 0;
      finally
        OutStream.Free;
      end;
    finally
      InStream.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('The system cannot find the file specified.');
      Result := 1;
    end;
  end;
end;

function ExecuteMove(Args: TStringList; Session: TSession): Integer;
var
  Src, Dst: string;
begin
  if Args.Count < 2 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Src := ExpandFileName(Args[0]);
  Dst := ExpandFileName(Args[1]);

  if DirectoryExists(Dst) then
    Dst := IncludeTrailingPathDelimiter(Dst) + ExtractFileName(Src);

  if RenameFile(Src, Dst) then
  begin
    Writeln('        1 file(s) moved.');
    Result := 0;
  end
  else
  begin
    Writeln('The system cannot find the file specified.');
    Result := 1;
  end;
end;

function ExecuteRen(Args: TStringList; Session: TSession): Integer;
var
  Src, Dst, FullDst: string;
begin
  if Args.Count < 2 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Src := ExpandFileName(Args[0]);
  Dst := Args[1];
  FullDst := ExtractFilePath(Src) + ExtractFileName(Dst);

  if RenameFile(Src, FullDst) then Result := 0
  else
  begin
    Writeln('A duplicate file name exists, or the file cannot be found.');
    Result := 1;
  end;
end;

function ExecuteType(Args: TStringList; Session: TSession): Integer;
var
  Target: string;
  Lines: TStringList;
  I: Integer;
begin
  if Args.Count = 0 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Target := ExpandFileName(Args[0]);
  if not FileExists(Target) then
  begin
    Writeln('The system cannot find the file specified.');
    Exit(1);
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Target);
    for I := 0 to Lines.Count - 1 do
      Writeln(Lines[I]);
    Result := 0;
  finally
    Lines.Free;
  end;
end;

function ExecuteEcho(Args: TStringList; Session: TSession): Integer;
var
  Msg: string;
  I: Integer;
begin
  if Args.Count = 0 then
  begin
    if Session.EchoOn then Writeln('ECHO is on.')
    else Writeln('ECHO is off.');
    Exit(0);
  end;

  Msg := '';
  for I := 0 to Args.Count - 1 do
  begin
    if I > 0 then Msg := Msg + ' ';
    Msg := Msg + Args[I];
  end;

  if SameText(Msg, 'on') then
    Session.EchoOn := True
  else if SameText(Msg, 'off') then
    Session.EchoOn := False
  else
    Writeln(Msg);

  Result := 0;
end;

function ExecuteSet(Args: TStringList; Session: TSession): Integer;
var
  FullArg, K, V: string;
  EqPos: Integer;
  Pair: TPair<string, string>;
begin
  if Args.Count = 0 then
  begin
    for Pair in Session.Vars do
      Writeln(Pair.Key, '=', Pair.Value);
    Exit(0);
  end;

  FullArg := '';
  for EqPos := 0 to Args.Count - 1 do
  begin
    if EqPos > 0 then FullArg := FullArg + ' ';
    FullArg := FullArg + Args[EqPos];
  end;

  EqPos := Pos('=', FullArg);
  if EqPos = 0 then
  begin
    { Display variables starting with string }
    for Pair in Session.Vars do
    begin
      if StartsText(FullArg, Pair.Key) then
        Writeln(Pair.Key, '=', Pair.Value);
    end;
    Exit(0);
  end;

  K := Copy(FullArg, 1, EqPos - 1);
  V := Copy(FullArg, EqPos + 1, Length(FullArg));

  if V = '' then
    Session.DeleteVar(K)
  else
    Session.SetVar(K, V);

  Result := 0;
end;

function ExecuteSetLocal(Args: TStringList; Session: TSession): Integer;
var
  I: Integer;
  Arg: string;
begin
  Session.SetLocal;
  for I := 0 to Args.Count - 1 do
  begin
    Arg := LowerCase(Args[I]);
    if Arg = 'enabledelayedexpansion' then
      Session.DelayedExpansion := True
    else if Arg = 'disabledelayedexpansion' then
      Session.DelayedExpansion := False
    else if Arg = 'enableextensions' then
      Session.CommandExtensions := True
    else if Arg = 'disableextensions' then
      Session.CommandExtensions := False;
  end;
  Result := 0;
end;

function ExecuteEndLocal(Args: TStringList; Session: TSession): Integer;
begin
  Session.EndLocal;
  Result := 0;
end;

function ExecutePath(Args: TStringList; Session: TSession): Integer;
var
  NewPath: string;
  I: Integer;
begin
  if Args.Count = 0 then
  begin
    Writeln('PATH=', Session.GetVarDef('PATH', ''));
    Exit(0);
  end;

  NewPath := '';
  for I := 0 to Args.Count - 1 do
  begin
    if I > 0 then NewPath := NewPath + ' ';
    NewPath := NewPath + Args[I];
  end;

  Session.SetVar('PATH', NewPath);
  Result := 0;
end;

function ExecuteIf(Args: TStringList; Session: TSession): Integer;
var
  Idx: Integer;
  NotFlag: Boolean;
  CondName, Arg1, TargetCmd: string;
  Val1: Integer;
  CondMet: Boolean;
  SubArgs: TStringList;
begin
  if Args.Count < 2 then
  begin
    Writeln('The syntax of the command is incorrect.');
    Exit(1);
  end;

  Idx := 0;
  NotFlag := False;
  if SameText(Args[0], 'not') then
  begin
    NotFlag := True;
    Inc(Idx);
  end;

  CondName := LowerCase(Args[Idx]);
  CondMet := False;

  if CondName = 'errorlevel' then
  begin
    Inc(Idx);
    Val1 := StrToIntDef(Args[Idx], 0);
    CondMet := (Session.ErrorLevel >= Val1);
    Inc(Idx);
  end
  else if CondName = 'exist' then
  begin
    Inc(Idx);
    Arg1 := ExpandFileName(Args[Idx]);
    CondMet := FileExists(Arg1) or DirectoryExists(Arg1);
    Inc(Idx);
  end
  else if CondName = 'defined' then
  begin
    Inc(Idx);
    CondMet := Session.HasVar(Args[Idx]);
    Inc(Idx);
  end
  else if Idx + 2 < Args.Count then
  begin
    Arg1 := Args[Idx];
    { Check for == or cmpop }
    if (Args[Idx + 1] = '==') or SameText(Args[Idx + 1], 'equ') then
      CondMet := (Arg1 = Args[Idx + 2])
    else if SameText(Args[Idx + 1], 'neq') then
      CondMet := (Arg1 <> Args[Idx + 2])
    else if SameText(Args[Idx + 1], 'lss') then
      CondMet := (StrToIntDef(Arg1, 0) < StrToIntDef(Args[Idx + 2], 0))
    else if SameText(Args[Idx + 1], 'leq') then
      CondMet := (StrToIntDef(Arg1, 0) <= StrToIntDef(Args[Idx + 2], 0))
    else if SameText(Args[Idx + 1], 'gtr') then
      CondMet := (StrToIntDef(Arg1, 0) > StrToIntDef(Args[Idx + 2], 0))
    else if SameText(Args[Idx + 1], 'geq') then
      CondMet := (StrToIntDef(Arg1, 0) >= StrToIntDef(Args[Idx + 2], 0));

    Inc(Idx, 3);
  end;

  if NotFlag then
    CondMet := not CondMet;

  if CondMet and (Idx < Args.Count) then
  begin
    TargetCmd := Args[Idx];
    SubArgs := TStringList.Create;
    try
      for Val1 := Idx + 1 to Args.Count - 1 do
        SubArgs.Add(Args[Val1]);
      if IsBuiltinCommand(TargetCmd) then
        Exit(ExecuteBuiltin(TargetCmd, SubArgs, Session));
    finally
      SubArgs.Free;
    end;
  end;

  Result := 0;
end;

function ExecuteFor(Args: TStringList; Session: TSession): Integer;
var
  VarName, SetPart: string;
  I, DoPos, InPos: Integer;
  Items: TArray<string>;
  Item, CmdName: string;
  SubArgs: TStringList;
begin
  if Args.Count < 4 then Exit(0);

  VarName := Args[0];
  InPos := 1;

  DoPos := -1;
  for I := 0 to Args.Count - 1 do
  begin
    if SameText(Args[I], 'do') then
    begin
      DoPos := I;
      Break;
    end;
  end;

  if (DoPos <= InPos + 1) or (DoPos >= Args.Count - 1) then Exit(0);

  SetPart := Args[InPos + 1];
  if (Length(SetPart) >= 2) and (SetPart[1] = '(') and (SetPart[Length(SetPart)] = ')') then
    SetPart := Copy(SetPart, 2, Length(SetPart) - 2);

  Items := SetPart.Split([' ']);
  CmdName := Args[DoPos + 1];

  for Item in Items do
  begin
    if Trim(Item) = '' then Continue;
    Session.SetVar(Copy(VarName, 2, Length(VarName)), Item);

    SubArgs := TStringList.Create;
    try
      for I := DoPos + 2 to Args.Count - 1 do
        SubArgs.Add(Args[I]);

      if IsBuiltinCommand(CmdName) then
        ExecuteBuiltin(CmdName, SubArgs, Session);
    finally
      SubArgs.Free;
    end;
  end;

  Result := 0;
end;

function ExecuteBuiltin(const CmdName: string; Args: TStringList; Session: TSession): Integer;
var
  Up: string;
begin
  Up := UpperCase(CmdName);
  if (Up = 'DIR') then Exit(ExecuteDir(Args, Session))
  else if (Up = 'CD') or (Up = 'CHDIR') then Exit(ExecuteCd(Args, Session))
  else if (Up = 'MD') or (Up = 'MKDIR') then Exit(ExecuteMd(Args, Session))
  else if (Up = 'RD') or (Up = 'RMDIR') then Exit(ExecuteRd(Args, Session))
  else if (Up = 'DEL') or (Up = 'ERASE') then Exit(ExecuteDel(Args, Session))
  else if (Up = 'COPY') then Exit(ExecuteCopy(Args, Session))
  else if (Up = 'MOVE') then Exit(ExecuteMove(Args, Session))
  else if (Up = 'REN') or (Up = 'RENAME') then Exit(ExecuteRen(Args, Session))
  else if (Up = 'TYPE') then Exit(ExecuteType(Args, Session))
  else if (Up = 'CLS') then begin Exit(0); end
  else if (Up = 'VER') then begin Writeln('CmdX [Version 1.0.100]'); Exit(0); end
  else if (Up = 'VOL') then begin Writeln(' Volume in drive has no label.'); Exit(0); end
  else if (Up = 'ECHO') then Exit(ExecuteEcho(Args, Session))
  else if (Up = 'SET') then Exit(ExecuteSet(Args, Session))
  else if (Up = 'SETLOCAL') then Exit(ExecuteSetLocal(Args, Session))
  else if (Up = 'ENDLOCAL') then Exit(ExecuteEndLocal(Args, Session))
  else if (Up = 'PATH') then Exit(ExecutePath(Args, Session))
  else if (Up = 'IF') then Exit(ExecuteIf(Args, Session))
  else if (Up = 'FOR') then Exit(ExecuteFor(Args, Session))
  else if (Up = 'REM') then Exit(0)
  else if (Up = 'EXIT') then
  begin
    Session.ExitRequested := True;
    if Args.Count > 0 then Session.ExitCode := StrToIntDef(Args[0], 0);
    Exit(Session.ExitCode);
  end;

  Result := 0;
end;

end.
