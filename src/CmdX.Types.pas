unit CmdX.Types;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  { Core Token Types }
  TTokenType = (
    ttWord,            // Command or argument string
    ttPipe,            // |
    ttSeparator,       // &
    ttCondAnd,         // &&
    ttCondOr,          // ||
    ttRedirectIn,      // <
    ttRedirectOut,     // >
    ttRedirectAppend,  // >>
    ttRedirectErr,     // 2>
    ttRedirectErrAppend,// 2>>
    ttMergeStderr,     // 2>&1
    ttRedirectBoth,    // &>
    ttLParen,          // (
    ttRParen           // )
  );

  TToken = record
    TokenType: TTokenType;
    Value: string;
    Quoted: Boolean;
  end;

  TTokenArray = array of TToken;

  { Redirection Record }
  TRedirectionType = (
    rtIn,         // <
    rtOut,        // >
    rtAppend,     // >>
    rtErr,        // 2>
    rtErrAppend,  // 2>>
    rtMergeStderr,// 2>&1
    rtBoth        // &>
  );

  TRedirection = record
    RedirType: TRedirectionType;
    Target: string; // File name or target stream ID
  end;

  TRedirectionArray = array of TRedirection;

  { Single Command Record }
  TSimpleCommand = record
    Executable: string;
    Args: TStringList;
    Redirections: TRedirectionArray;
  end;

  { Chain / Operator Types }
  TOperatorType = (
    opNone,
    opSequential, // &
    opCondAnd,    // &&
    opCondOr,     // ||
    opPipe        // |
  );

  { Node in a Command Chain }
  PCommandNode = ^TCommandNode;
  TCommandNode = record
    Command: TSimpleCommand;
    NextOperator: TOperatorType;
    NextNode: PCommandNode;
  end;

  { Environment Scope Stack for setlocal / endlocal }
  TEnvScope = record
    DelayedExpansion: Boolean;
    CommandExtensions: Boolean;
    Vars: TDictionary<string, string>;
    Cwd: string;
  end;

  { Session Context }
  TSession = class
  private
    FVars: TDictionary<string, string>;
    FCurrentDir: string;
    FErrorLevel: Integer;
    FEchoOn: Boolean;
    FDelayedExpansion: Boolean;
    FCommandExtensions: Boolean;
    FScopeStack: TList<TEnvScope>;
    FBatchContextStack: TList<string>;
    FExitRequested: Boolean;
    FExitCode: Integer;
    FBaseDirectory: string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure SetVar(const AName, AValue: string);
    function GetVar(const AName: string; out AValue: string): Boolean;
    function GetVarDef(const AName, ADefault: string): string;
    procedure DeleteVar(const AName: string);
    function HasVar(const AName: string): Boolean;

    procedure SetLocal;
    procedure EndLocal;

    procedure CheckAndLoadProjectConfig(const ADir: string);
    function BuildShortEnvironmentBlock(out ABlockSize: Integer): Pointer;

    property Vars: TDictionary<string, string> read FVars;
    property CurrentDir: string read FCurrentDir write FCurrentDir;
    property ErrorLevel: Integer read FErrorLevel write FErrorLevel;
    property EchoOn: Boolean read FEchoOn write FEchoOn;
    property DelayedExpansion: Boolean read FDelayedExpansion write FDelayedExpansion;
    property CommandExtensions: Boolean read FCommandExtensions write FCommandExtensions;
    property ExitRequested: Boolean read FExitRequested write FExitRequested;
    property ExitCode: Integer read FExitCode write FExitCode;
  end;

implementation

{ TSession }

constructor TSession.Create;
var
  I: Integer;
  EnvStr: string;
  EqPos: Integer;
  K, V: string;
begin
  inherited Create;
  FVars := TDictionary<string, string>.Create;
  FScopeStack := TList<TEnvScope>.Create;
  FBatchContextStack := TList<string>.Create;
  FCurrentDir := GetCurrentDir;
  FBaseDirectory := FCurrentDir;
  FErrorLevel := 0;
  FEchoOn := True;
  FDelayedExpansion := False;
  FCommandExtensions := True;
  FExitRequested := False;
  FExitCode := 0;

  { Populate initial environment from OS }
  for I := 1 to GetEnvironmentVariableCount do
  begin
    EnvStr := GetEnvironmentString(I);
    EqPos := Pos('=', EnvStr);
    if EqPos > 1 then
    begin
      K := Copy(EnvStr, 1, EqPos - 1);
      V := Copy(EnvStr, EqPos + 1, Length(EnvStr));
      FVars.AddOrSetValue(K, V);
    end;
  end;

  { Load initial project config if present }
  CheckAndLoadProjectConfig(FCurrentDir);
end;

destructor TSession.Destroy;
var
  Scope: TEnvScope;
begin
  for Scope in FScopeStack do
    Scope.Vars.Free;
  FScopeStack.Free;
  FBatchContextStack.Free;
  FVars.Free;
  inherited Destroy;
end;

procedure TSession.SetVar(const AName, AValue: string);
var
  Pair: TPair<string, string>;
  KeyToUse: string;
begin
  if AName = '' then Exit;
  KeyToUse := AName;

  { Case-insensitive lookup }
  for Pair in FVars do
  begin
    if SameText(Pair.Key, AName) then
    begin
      KeyToUse := Pair.Key;
      Break;
    end;
  end;

  FVars.AddOrSetValue(KeyToUse, AValue);
end;

function TSession.GetVar(const AName: string; out AValue: string): Boolean;
var
  Pair: TPair<string, string>;
begin
  for Pair in FVars do
  begin
    if SameText(Pair.Key, AName) then
    begin
      AValue := Pair.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSession.GetVarDef(const AName, ADefault: string): string;
begin
  if not GetVar(AName, Result) then
    Result := ADefault;
end;

procedure TSession.DeleteVar(const AName: string);
var
  Pair: TPair<string, string>;
begin
  for Pair in FVars do
  begin
    if SameText(Pair.Key, AName) then
    begin
      FVars.Remove(Pair.Key);
      Break;
    end;
  end;
end;

function TSession.HasVar(const AName: string): Boolean;
var
  Dummy: string;
begin
  Result := GetVar(AName, Dummy);
end;

procedure TSession.SetLocal;
var
  Scope: TEnvScope;
  Pair: TPair<string, string>;
begin
  if FScopeStack.Count >= 32 then
    Exit; { Stack limit reached }

  Scope.DelayedExpansion := FDelayedExpansion;
  Scope.CommandExtensions := FCommandExtensions;
  Scope.Cwd := FCurrentDir;
  Scope.Vars := TDictionary<string, string>.Create;

  for Pair in FVars do
    Scope.Vars.Add(Pair.Key, Pair.Value);

  FScopeStack.Add(Scope);
end;

procedure TSession.EndLocal;
var
  Scope: TEnvScope;
  Pair: TPair<string, string>;
begin
  if FScopeStack.Count = 0 then Exit;

  Scope := FScopeStack[FScopeStack.Count - 1];
  FScopeStack.Delete(FScopeStack.Count - 1);

  FDelayedExpansion := Scope.DelayedExpansion;
  FCommandExtensions := Scope.CommandExtensions;
  FCurrentDir := Scope.Cwd;

  FVars.Clear;
  for Pair in Scope.Vars do
    FVars.Add(Pair.Key, Pair.Value);

  Scope.Vars.Free;
end;

procedure TSession.CheckAndLoadProjectConfig(const ADir: string);
var
  CfgPath: string;
  Lines: TStringList;
  I: Integer;
  Line, K, V: string;
  EqPos: Integer;
  CurrentPath: string;
begin
  CfgPath := IncludeTrailingPathDelimiter(ADir) + '.cmdenv';
  if not FileExists(CfgPath) then Exit;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(CfgPath);
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Copy(Line, 1, 1) = '#') or (Copy(Line, 1, 2) = 'REM') then
        Continue;

      EqPos := Pos('=', Line);
      if EqPos > 1 then
      begin
        K := Trim(Copy(Line, 1, EqPos - 1));
        V := Trim(Copy(Line, EqPos + 1, Length(Line)));
        if SameText(K, 'PATH') or SameText(K, 'PATH_ADD') then
        begin
          if GetVar('PATH', CurrentPath) then
            SetVar('PATH', V + PathSeparator + CurrentPath)
          else
            SetVar('PATH', V);
        end;
        SetVar(K, V);
      end;
    end;
  finally
    Lines.Free;
  end;
end;

function TSession.BuildShortEnvironmentBlock(out ABlockSize: Integer): Pointer;
var
  Pair: TPair<string, string>;
  StrList: TStringList;
  I, TotalChars, Offset: Integer;
  S: UnicodeString;
  P: PWideChar;
begin
  StrList := TStringList.Create;
  try
    for Pair in FVars do
    begin
      StrList.Add(Pair.Key + '=' + Pair.Value);
    end;

    TotalChars := 0;
    for I := 0 to StrList.Count - 1 do
    begin
      S := UnicodeString(StrList[I]);
      Inc(TotalChars, Length(S) + 1); // wide char string + wide char null terminator
    end;
    Inc(TotalChars, 1); // trailing wide null

    GetMem(P, TotalChars * SizeOf(WideChar));
    Offset := 0;
    for I := 0 to StrList.Count - 1 do
    begin
      S := UnicodeString(StrList[I]);
      if Length(S) > 0 then
        Move(S[1], P[Offset], Length(S) * SizeOf(WideChar));
      P[Offset + Length(S)] := #0;
      Inc(Offset, Length(S) + 1);
    end;
    P[Offset] := #0;

    ABlockSize := TotalChars * SizeOf(WideChar);
    Result := P;
  finally
    StrList.Free;
  end;
end;

end.
