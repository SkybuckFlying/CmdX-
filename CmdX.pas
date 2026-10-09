program CmdX;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes,
  CmdX.Types in 'src/CmdX.Types.pas',
  CmdX.Expansion in 'src/CmdX.Expansion.pas',
  CmdX.Parser in 'src/CmdX.Parser.pas',
  CmdX.Builtins in 'src/CmdX.Builtins.pas',
  CmdX.Executor in 'src/CmdX.Executor.pas';

procedure ProcessCommandLine(const InputLine: string; Session: TSession; IsBatch: Boolean = False; BatchArgs: TStringList = nil);
var
  ExpandedLine: string;
  Tokens: TTokenArray;
  CmdNode: PCommandNode;
begin
  if Trim(InputLine) = '' then Exit;

  ExpandedLine := ExpandLine(InputLine, Session, IsBatch, BatchArgs);
  Tokens := Tokenize(ExpandedLine);
  if Length(Tokens) = 0 then Exit;

  CmdNode := ParseCommandChain(Tokens);
  try
    ExecuteCommandNode(CmdNode, Session, IsBatch);
  finally
    FreeCommandNode(CmdNode);
  end;
end;

procedure RunBatchFile(const BatchPath: string; Session: TSession; ScriptArgs: TStringList);
var
  Lines: TStringList;
  I: Integer;
  Line: string;
begin
  if not FileExists(BatchPath) then
  begin
    Writeln('The system cannot find the batch file specified.');
    Session.ErrorLevel := 1;
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(BatchPath);
    I := 0;
    while (I < Lines.Count) and (not Session.ExitRequested) do
    begin
      Line := Trim(Lines[I]);
      if (Line <> '') and (Copy(Line, 1, 2) <> '::') and (not SameText(Copy(Line, 1, 4), 'REM ')) then
      begin
        if Session.EchoOn then
          Writeln(Session.CurrentDir, '>', Line);
        ProcessCommandLine(Line, Session, True, ScriptArgs);
      end;
      Inc(I);
    end;
  finally
    Lines.Free;
  end;
end;

procedure InteractiveREPL(Session: TSession);
var
  InputLine: string;
begin
  Writeln('CmdX Shell [Version 1.0.100]');
  Writeln('Microsoft Windows cmd.exe compatible interpreter with short per-child PATH management.');
  Writeln;

  while not Session.ExitRequested do
  begin
    Write(Session.CurrentDir, '>');
    Readln(InputLine);
    ProcessCommandLine(InputLine, Session, False, nil);
  end;
end;

var
  Session: TSession;
  ScriptArgs: TStringList;
  I: Integer;
  Arg0: string;
begin
  Session := TSession.Create;
  try
    if ParamCount > 0 then
    begin
      Arg0 := ParamStr(1);
      if SameText(Arg0, '/c') and (ParamCount >= 2) then
      begin
        { Execute command line and exit }
        Arg0 := '';
        for I := 2 to ParamCount do
        begin
          if I > 2 then Arg0 := Arg0 + ' ';
          Arg0 := Arg0 + ParamStr(I);
        end;
        ProcessCommandLine(Arg0, Session, False, nil);
      end;
      if (ParamCount >= 2) and SameText(Arg0, '/k') then
      begin
        Arg0 := '';
        for I := 2 to ParamCount do
        begin
          if I > 2 then Arg0 := Arg0 + ' ';
          Arg0 := Arg0 + ParamStr(I);
        end;
        ProcessCommandLine(Arg0, Session, False, nil);
        InteractiveREPL(Session);
      end;
      if FileExists(ParamStr(1)) then
      begin
        ScriptArgs := TStringList.Create;
        try
          for I := 1 to ParamCount do
            ScriptArgs.Add(ParamStr(I));
          RunBatchFile(ParamStr(1), Session, ScriptArgs);
        finally
          ScriptArgs.Free;
        end;
      end;
    end
    else
    begin
      InteractiveREPL(Session);
    end;
  finally
    Session.Free;
  end;
end.
