unit CmdX.Executor;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX.Types, CmdX.Builtins, CmdX.Expansion, CmdX.Parser
  {$IFDEF MSWINDOWS}
  , Windows
  {$ELSE}
  , Process
  {$ENDIF}
  ;

function ResolveExecutable(const CmdName: string; Session: TSession): string;
function ExecuteCommandNode(Node: PCommandNode; Session: TSession; IsBatch: Boolean = False): Integer;

implementation

function ResolveExecutable(const CmdName: string; Session: TSession): string;
var
  Paths, Exts: TArray<string>;
  PathDir, Ext, Candidate: string;
  EffectivePath, PathextVal: string;
begin
  if (Pos('/', CmdName) > 0) or (Pos('\', CmdName) > 0) then
  begin
    Candidate := ExpandFileName(CmdName);
    if FileExists(Candidate) then Exit(Candidate);
  end;

  { Check current directory }
  Candidate := IncludeTrailingPathDelimiter(Session.CurrentDir) + CmdName;
  if FileExists(Candidate) then Exit(Candidate);

  PathextVal := Session.GetVarDef('PATHEXT', '.COM;.EXE;.BAT;.CMD');
  Exts := PathextVal.Split([';']);

  for Ext in Exts do
  begin
    if FileExists(Candidate + Ext) then Exit(Candidate + Ext);
  end;

  { Check PATH }
  EffectivePath := Session.GetVarDef('PATH', '');
  Paths := EffectivePath.Split([PathSeparator]);

  for PathDir in Paths do
  begin
    if PathDir = '' then Continue;
    Candidate := IncludeTrailingPathDelimiter(PathDir) + CmdName;
    if FileExists(Candidate) then Exit(Candidate);
    for Ext in Exts do
    begin
      if FileExists(Candidate + Ext) then Exit(Candidate + Ext);
    end;
  end;

  Result := '';
end;

function ExecuteExternalProcess(const Executable: string; Args: TStringList; Redirs: TRedirectionArray; Session: TSession): Integer;
{$IFDEF MSWINDOWS}
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine: string;
  I: Integer;
  EnvBlock: Pointer;
  BlockSize: Integer;
  Success: Boolean;
  ExitCode: DWORD;
  SecAttr: TSecurityAttributes;
  HIn, HOut, HErr: THandle;
  R: TRedirection;
begin
  CmdLine := '"' + Executable + '"';
  for I := 0 to Args.Count - 1 do
    CmdLine := CmdLine + ' "' + Args[I] + '"';

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES;
  SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  SI.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  SI.hStdError := GetStdHandle(STD_ERROR_HANDLE);

  SecAttr.nLength := SizeOf(SecAttr);
  SecAttr.lpSecurityDescriptor := nil;
  SecAttr.bInheritHandle := True;

  for R in Redirs do
  begin
    case R.RedirType of
      rtIn:
        begin
          HIn := CreateFile(PChar(R.Target), GENERIC_READ, FILE_SHARE_READ, @SecAttr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
          if HIn <> INVALID_HANDLE_VALUE then SI.hStdInput := HIn;
        end;
      rtOut:
        begin
          HOut := CreateFile(PChar(R.Target), GENERIC_WRITE, FILE_SHARE_READ, @SecAttr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
          if HOut <> INVALID_HANDLE_VALUE then SI.hStdOutput := HOut;
        end;
      rtAppend:
        begin
          HOut := CreateFile(PChar(R.Target), FILE_APPEND_DATA, FILE_SHARE_READ, @SecAttr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
          if HOut <> INVALID_HANDLE_VALUE then SI.hStdOutput := HOut;
        end;
      rtErr:
        begin
          HErr := CreateFile(PChar(R.Target), GENERIC_WRITE, FILE_SHARE_READ, @SecAttr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
          if HErr <> INVALID_HANDLE_VALUE then SI.hStdError := HErr;
        end;
      rtErrAppend:
        begin
          HErr := CreateFile(PChar(R.Target), FILE_APPEND_DATA, FILE_SHARE_READ, @SecAttr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
          if HErr <> INVALID_HANDLE_VALUE then SI.hStdError := HErr;
        end;
      rtMergeStderr:
        begin
          SI.hStdError := SI.hStdOutput;
        end;
      rtBoth:
        begin
          HOut := CreateFile(PChar(R.Target), GENERIC_WRITE, FILE_SHARE_READ, @SecAttr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
          if HOut <> INVALID_HANDLE_VALUE then
          begin
            SI.hStdOutput := HOut;
            SI.hStdError := HOut;
          end;
        end;
    end;
  end;

  EnvBlock := Session.BuildShortEnvironmentBlock(BlockSize);
  try
    Success := CreateProcess(
      nil,
      PChar(CmdLine),
      nil, nil,
      True,
      CREATE_UNICODE_ENVIRONMENT,
      EnvBlock,
      PChar(Session.CurrentDir),
      SI,
      PI
    );

    if Success then
    begin
      WaitForSingleObject(PI.hProcess, INFINITE);
      GetExitCodeProcess(PI.hProcess, ExitCode);
      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread);
      Result := ExitCode;
    end
    else
    begin
      Writeln('''', ExtractFileName(Executable), ''' is not recognized as an internal or external command, operable program or batch file.');
      Result := 9009;
    end;
  finally
    FreeMem(EnvBlock);
  end;
end;
{$ELSE}
var
  AProcess: TProcess;
  I: Integer;
  Pair: TPair<string, string>;
begin
  AProcess := TProcess.Create(nil);
  try
    AProcess.Executable := Executable;
    for I := 0 to Args.Count - 1 do
      AProcess.Parameters.Add(Args[I]);

    AProcess.CurrentDirectory := Session.CurrentDir;
    AProcess.Options := [poWaitOnExit];

    { Explicit short environment construction for non-Windows targets }
    AProcess.Environment.Clear;
    for Pair in Session.Vars do
      AProcess.Environment.Add(Pair.Key + '=' + Pair.Value);

    AProcess.Execute;
    Result := AProcess.ExitCode;
  except
    on E: Exception do
    begin
      Writeln('''', ExtractFileName(Executable), ''' is not recognized as an internal or external command, operable program or batch file.');
      Result := 9009;
    end;
  end;
  AProcess.Free;
end;
{$ENDIF}

function ExecuteCommandNode(Node: PCommandNode; Session: TSession; IsBatch: Boolean): Integer;
var
  CurNode: PCommandNode;
  ExecPath: string;
  Res: Integer;
  RunNext: Boolean;
begin
  Result := 0;
  CurNode := Node;

  while CurNode <> nil do
  begin
    if CurNode^.Command.Executable <> '' then
    begin
      if IsBuiltinCommand(CurNode^.Command.Executable) then
      begin
        Res := ExecuteBuiltin(CurNode^.Command.Executable, CurNode^.Command.Args, Session);
      end
      else
      begin
        ExecPath := ResolveExecutable(CurNode^.Command.Executable, Session);
        if ExecPath <> '' then
        begin
          Res := ExecuteExternalProcess(ExecPath, CurNode^.Command.Args, CurNode^.Command.Redirections, Session);
        end
        else
        begin
          Writeln('''', CurNode^.Command.Executable, ''' is not recognized as an internal or external command, operable program or batch file.');
          Res := 9009;
        end;
      end;

      Session.ErrorLevel := Res;
      Result := Res;
    end;

    { Operator Decision }
    RunNext := True;
    case CurNode^.NextOperator of
      opSequential: RunNext := True;
      opCondAnd: RunNext := (Res = 0);
      opCondOr: RunNext := (Res <> 0);
      opPipe: RunNext := True;
    end;

    if not RunNext then
      Break;

    CurNode := CurNode^.NextNode;
  end;
end;

end.
