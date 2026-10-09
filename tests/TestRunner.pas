program TestRunner;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

uses
  SysUtils, Classes, Generics.Collections,
  CmdX.Types in 'src/CmdX.Types.pas',
  CmdX.Expansion in 'src/CmdX.Expansion.pas',
  CmdX.Parser in 'src/CmdX.Parser.pas',
  CmdX.Builtins in 'src/CmdX.Builtins.pas',
  CmdX.Executor in 'src/CmdX.Executor.pas';

var
  PassedCount: Integer = 0;
  FailedCount: Integer = 0;

procedure AssertTrue(const Cond: Boolean; const TestName: string);
begin
  if Cond then
  begin
    Writeln('  [PASS] ', TestName);
    Inc(PassedCount);
  end
  else
  begin
    Writeln('  [FAIL] ', TestName);
    Inc(FailedCount);
  end;
end;

procedure AssertEquals(const Expected, Actual: string; const TestName: string);
begin
  if Expected = Actual then
  begin
    Writeln('  [PASS] ', TestName);
    Inc(PassedCount);
  end
  else
  begin
    Writeln('  [FAIL] ', TestName, ' - Expected "', Expected, '" but got "', Actual, '"');
    Inc(FailedCount);
  end;
end;

procedure TestExpansion;
var
  Session: TSession;
  OutStr: string;
begin
  Writeln('=== Testing Variable Expansion ===');
  Session := TSession.Create;
  try
    Session.SetVar('TESTVAR', 'HelloWorld');
    OutStr := ExpandLine('%TESTVAR%', Session, False);
    AssertEquals('HelloWorld', OutStr, 'Basic %VAR% expansion');

    OutStr := ExpandLine('%TESTVAR:~0,5%', Session, False);
    AssertEquals('Hello', OutStr, 'Substring %VAR:~0,5%');

    OutStr := ExpandLine('%TESTVAR:World=Pascal%', Session, False);
    AssertEquals('HelloPascal', OutStr, 'Replacement %VAR:old=new%');

    Session.DelayedExpansion := True;
    Session.SetVar('DELAYVAR', 'DelayedValue');
    OutStr := ExpandLine('!DELAYVAR!', Session, False);
    AssertEquals('DelayedValue', OutStr, 'Delayed !VAR! expansion');
  finally
    Session.Free;
  end;
end;

procedure TestParser;
var
  Tokens: TTokenArray;
  Node: PCommandNode;
begin
  Writeln('=== Testing Lexer & Parser ===');
  Tokens := Tokenize('echo hello && dir || cd ..');
  AssertTrue(Length(Tokens) = 7, 'Tokenize operator chain length');

  Node := ParseCommandChain(Tokens);
  try
    AssertTrue(Node <> nil, 'ParseCommandChain head exists');
    if Node <> nil then
    begin
      AssertEquals('echo', Node^.Command.Executable, 'First command executable');
      AssertTrue(Node^.NextOperator = opCondAnd, 'First operator is &&');
    end;
  finally
    FreeCommandNode(Node);
  end;
end;

procedure TestEnvironmentBlockAndProjectConfig;
var
  Session: TSession;
  Block: PAnsiChar;
  BlockSize: Integer;
  ProjectDir, ConfigPath: string;
  Lines: TStringList;
begin
  Writeln('=== Testing Short Environment Block & .cmdenv ===');
  Session := TSession.Create;
  try
    Session.SetVar('PROJECT_VAR', 'CmdXValue');
    Block := Session.BuildShortEnvironmentBlock(BlockSize);
    try
      AssertTrue(BlockSize > 0, 'BuildShortEnvironmentBlock size > 0');
      AssertTrue(Block <> nil, 'BuildShortEnvironmentBlock pointer not nil');
    finally
      FreeMem(Block);
    end;

    { Test .cmdenv loading }
    ProjectDir := GetCurrentDir + '/test_proj';
    CreateDir(ProjectDir);
    ConfigPath := ProjectDir + '/.cmdenv';
    Lines := TStringList.Create;
    try
      Lines.Add('CUSTOM_SETTING=Active');
      Lines.Add('PATH_ADD=/custom/bin');
      Lines.SaveToFile(ConfigPath);
    finally
      Lines.Free;
    end;

    Session.CheckAndLoadProjectConfig(ProjectDir);
    AssertEquals('Active', Session.GetVarDef('CUSTOM_SETTING', ''), '.cmdenv setting loaded');

    DeleteFile(ConfigPath);
    RemoveDir(ProjectDir);
  finally
    Session.Free;
  end;
end;

begin
  Writeln('Running CmdX Test Suite...');
  Writeln;

  TestExpansion;
  TestParser;
  TestEnvironmentBlockAndProjectConfig;

  Writeln;
  Writeln('Test Summary: ', PassedCount, ' Passed, ', FailedCount, ' Failed.');
  if FailedCount > 0 then ExitCode := 1 else ExitCode := 0;
end.
