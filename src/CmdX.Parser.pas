unit CmdX.Parser;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX.Types;

function Tokenize(const ALine: string): TTokenArray;
function ParseCommandChain(const Tokens: TTokenArray): PCommandNode;
procedure FreeCommandNode(Node: PCommandNode);

implementation

function Tokenize(const ALine: string): TTokenArray;
var
  I, N, TokenCount: Integer;
  InQuotes: Boolean;
  C, NextC: Char;
  CurToken: string;
  IsQuoted: Boolean;

  procedure AddToken(AType: TTokenType; const AVal: string = ''; AQuoted: Boolean = False);
  begin
    SetLength(Result, TokenCount + 1);
    Result[TokenCount].TokenType := AType;
    Result[TokenCount].Value := AVal;
    Result[TokenCount].Quoted := AQuoted;
    Inc(TokenCount);
  end;

  procedure FlushWord;
  begin
    if (CurToken <> '') or IsQuoted then
    begin
      AddToken(ttWord, CurToken, IsQuoted);
      CurToken := '';
      IsQuoted := False;
    end;
  end;

begin
  TokenCount := 0;
  SetLength(Result, 0);
  InQuotes := False;
  IsQuoted := False;
  CurToken := '';
  I := 1;
  N := Length(ALine);

  while I <= N do
  begin
    C := ALine[I];
    if I < N then NextC := ALine[I + 1] else NextC := #0;

    { Caret Escape }
    if (C = '^') and (not InQuotes) and (I < N) then
    begin
      CurToken := CurToken + ALine[I + 1];
      Inc(I, 2);
      Continue;
    end;

    { Double Quote Toggle }
    if C = '"' then
    begin
      InQuotes := not InQuotes;
      IsQuoted := True;
      CurToken := CurToken + C;
      Inc(I);
      Continue;
    end;

    if InQuotes then
    begin
      CurToken := CurToken + C;
      Inc(I);
      Continue;
    end;

    { Whitespace Outside Quotes }
    if C in [' ', #9, #10, #13] then
    begin
      FlushWord;
      Inc(I);
      Continue;
    end;

    { Special Operator Tokens Outside Quotes }
    if C = '|' then
    begin
      FlushWord;
      if NextC = '|' then
      begin
        AddToken(ttCondOr, '||');
        Inc(I, 2);
      end
      else
      begin
        AddToken(ttPipe, '|');
        Inc(I);
      end;
      Continue;
    end;

    if C = '&' then
    begin
      FlushWord;
      if NextC = '&' then
      begin
        AddToken(ttCondAnd, '&&');
        Inc(I, 2);
      end
      else if NextC = '>' then
      begin
        AddToken(ttRedirectBoth, '&>');
        Inc(I, 2);
      end
      else
      begin
        AddToken(ttSeparator, '&');
        Inc(I);
      end;
      Continue;
    end;

    if C = '<' then
    begin
      FlushWord;
      AddToken(ttRedirectIn, '<');
      Inc(I);
      Continue;
    end;

    if C = '>' then
    begin
      FlushWord;
      if NextC = '>' then
      begin
        AddToken(ttRedirectAppend, '>>');
        Inc(I, 2);
      end
      else
      begin
        AddToken(ttRedirectOut, '>');
        Inc(I);
      end;
      Continue;
    end;

    if (C = '2') and (NextC = '>') then
    begin
      FlushWord;
      if (I + 2 <= N) and (ALine[I + 2] = '>') then
      begin
        AddToken(ttRedirectErrAppend, '2>>');
        Inc(I, 3);
      end;
      if (I + 3 <= N) and (ALine[I + 2] = '&') and (ALine[I + 3] = '1') then
      begin
        AddToken(ttMergeStderr, '2>&1');
        Inc(I, 4);
      end
      else
      begin
        AddToken(ttRedirectErr, '2>');
        Inc(I, 2);
      end;
      Continue;
    end;

    if C = '(' then
    begin
      FlushWord;
      AddToken(ttLParen, '(');
      Inc(I);
      Continue;
    end;

    if C = ')' then
    begin
      FlushWord;
      AddToken(ttRParen, ')');
      Inc(I);
      Continue;
    end;

    CurToken := CurToken + C;
    Inc(I);
  end;

  FlushWord;
end;

function ParseCommandChain(const Tokens: TTokenArray): PCommandNode;
var
  I, N: Integer;
  Head, CurrentNode, PrevNode: PCommandNode;

  procedure AddRedirection(Node: PCommandNode; RType: TRedirectionType; const Target: string);
  var
    Len: Integer;
  begin
    Len := Length(Node^.Command.Redirections);
    SetLength(Node^.Command.Redirections, Len + 1);
    Node^.Command.Redirections[Len].RedirType := RType;
    Node^.Command.Redirections[Len].Target := Target;
  end;

begin
  Head := nil;
  CurrentNode := nil;
  PrevNode := nil;
  N := Length(Tokens);
  I := 0;

  while I < N do
  begin
    if CurrentNode = nil then
    begin
      New(CurrentNode);
      CurrentNode^.Command.Executable := '';
      CurrentNode^.Command.Args := TStringList.Create;
      SetLength(CurrentNode^.Command.Redirections, 0);
      CurrentNode^.NextOperator := opNone;
      CurrentNode^.NextNode := nil;

      if PrevNode <> nil then
        PrevNode^.NextNode := CurrentNode;

      if Head = nil then
        Head := CurrentNode;
    end;

    case Tokens[I].TokenType of
      ttWord:
        begin
          if CurrentNode^.Command.Executable = '' then
            CurrentNode^.Command.Executable := Tokens[I].Value
          else
            CurrentNode^.Command.Args.Add(Tokens[I].Value);
        end;

      ttRedirectIn:
        begin
          if (I + 1 < N) and (Tokens[I + 1].TokenType = ttWord) then
          begin
            AddRedirection(CurrentNode, rtIn, Tokens[I + 1].Value);
            Inc(I);
          end;
        end;

      ttRedirectOut:
        begin
          if (I + 1 < N) and (Tokens[I + 1].TokenType = ttWord) then
          begin
            AddRedirection(CurrentNode, rtOut, Tokens[I + 1].Value);
            Inc(I);
          end;
        end;

      ttRedirectAppend:
        begin
          if (I + 1 < N) and (Tokens[I + 1].TokenType = ttWord) then
          begin
            AddRedirection(CurrentNode, rtAppend, Tokens[I + 1].Value);
            Inc(I);
          end;
        end;

      ttRedirectErr:
        begin
          if (I + 1 < N) and (Tokens[I + 1].TokenType = ttWord) then
          begin
            AddRedirection(CurrentNode, rtErr, Tokens[I + 1].Value);
            Inc(I);
          end;
        end;

      ttRedirectErrAppend:
        begin
          if (I + 1 < N) and (Tokens[I + 1].TokenType = ttWord) then
          begin
            AddRedirection(CurrentNode, rtErrAppend, Tokens[I + 1].Value);
            Inc(I);
          end;
        end;

      ttMergeStderr:
        begin
          AddRedirection(CurrentNode, rtMergeStderr, '1');
        end;

      ttRedirectBoth:
        begin
          if (I + 1 < N) and (Tokens[I + 1].TokenType = ttWord) then
          begin
            AddRedirection(CurrentNode, rtBoth, Tokens[I + 1].Value);
            Inc(I);
          end;
        end;

      ttSeparator:
        begin
          CurrentNode^.NextOperator := opSequential;
          PrevNode := CurrentNode;
          CurrentNode := nil;
        end;

      ttCondAnd:
        begin
          CurrentNode^.NextOperator := opCondAnd;
          PrevNode := CurrentNode;
          CurrentNode := nil;
        end;

      ttCondOr:
        begin
          CurrentNode^.NextOperator := opCondOr;
          PrevNode := CurrentNode;
          CurrentNode := nil;
        end;

      ttPipe:
        begin
          CurrentNode^.NextOperator := opPipe;
          PrevNode := CurrentNode;
          CurrentNode := nil;
        end;

      ttLParen, ttRParen:
        begin
          { Grouping token }
        end;
    end;

    Inc(I);
  end;

  Result := Head;
end;

procedure FreeCommandNode(Node: PCommandNode);
var
  Next: PCommandNode;
begin
  while Node <> nil do
  begin
    Next := Node^.NextNode;
    if Node^.Command.Args <> nil then
      Node^.Command.Args.Free;
    Dispose(Node);
    Node := Next;
  end;
end;

end.
