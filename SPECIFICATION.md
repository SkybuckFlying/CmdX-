# CmdX Specification - Version 1.0

## 1. Overview
CmdX is a high-performance, `cmd.exe`-compatible command interpreter written in Object Pascal (supporting Delphi 13 and Free Pascal Compiler in `{$MODE DELPHI}` / `-Mdelphi` mode).

CmdX is designed to solve the Windows `PATH` variable truncation / bloat problem (the 4095-character registry limit and 8191-character cmd.exe environment variable limit) while maintaining syntax and behavioral compatibility with standard Windows `cmd.exe` batch files and interactive commands.

## 2. Key Objectives & Features

1. **Full `cmd.exe` Syntax & Built-in Command Compatibility**:
   - Interactive REPL loop.
   - Batch file execution (`.bat`, `.cmd`).
   - Standard redirection (`>`, `>>`, `<`, `2>`, `2>&1`, `&>`) and chaining operators (`&`, `&&`, `||`, `|`).
   - Immediate `%VAR%` expansion and Delayed `!VAR!` expansion.
   - Full built-ins set: `cd`/`chdir`, `dir`, `md`/`mkdir`, `rd`/`rmdir`, `del`/`erase`, `copy`, `move`, `ren`/`rename`, `type`, `cls`, `echo`, `set`, `setlocal`/`endlocal`, `path`, `prompt`, `title`, `color`, `ver`, `vol`, `pause`, `exit`, `call`, `goto`, `shift`, `if`, `for`, `rem`.

2. **Per-Child Short Environment Block Management (PATH Solution)**:
   - Does NOT inherit bloated global `PATH` blocks directly into child processes.
   - Maintains an in-memory session environment.
   - Automatically loads per-directory / project `.cmdenv` files (like `direnv`).
   - Builds custom, minimal, serialized environment blocks (`NAME=VALUE\0... \0\0`) for every invoked process.

3. **Cross-Compiler & Cross-Platform Architecture**:
   - Written in Delphi Object Pascal compatible syntax.
   - Compiles cleanly on Free Pascal Compiler using `fpc -Mdelphi` / `{$MODE DELPHI}`.
   - Cross-platform abstraction for OS-specific execution (Windows Win32 APIs where available, POSIX/Process fallbacks for Unix/Linux testing).

## 3. Architecture Subsystems

### A. Environment Manager (`CmdX.Environment.pas`)
- Case-insensitive environment key-value map.
- Effective PATH management (Base system dirs + session/project overrides).
- Support for `.cmdenv` project configuration.
- Environment stack for `setlocal` / `endlocal` scoping.
- Serialization logic to raw binary environment block (`NAME=VALUE\0... \0\0`).

### B. Lexer & Parser (`CmdX.Parser.pas`)
- Tokenizer handling double quotes (`"`), escape carets (`^`), parameter references, and special syntax.
- Operator parser recognizing `|`, `&`, `&&`, `||`, `(`, `)`.
- Redirection parser handling stdin/stdout/stderr handles.

### C. Expansion Engine (`CmdX.Expansion.pas`)
- Percent Expansion (`%VAR%`, `%VAR:~start,len%`, `%VAR:old=new%`).
- Delayed Expansion (`!VAR!`, `!VAR:~start,len%`, `!VAR:old=new%`).
- Batch parameter expansion (`%0`..`%9`, `%*`, `%~1`).
- Caret escaping rules outside and inside quotes.

### D. Built-In Commands (`CmdX.Builtins.pas`)
- Dispatcher and handlers for all standard `cmd.exe` internal commands.
- Support for `if` conditions (`errorlevel`, `exist`, `defined`, string equality `==`, numeric comparisons `equ`, `neq`, `lss`, `leq`, `gtr`, `geq`).
- Support for `for` loops (`for %v in (...)`, `for /d`, `for /r`, `for /l`, `for /f`).

### E. Execution Engine (`CmdX.Executor.pas`)
- Command lookup (built-in vs script vs external executable via PATH resolution).
- Redirection setup and handle duplication.
- Pipeline concurrent execution.
- Child process spawning with explicitly constructed environment block.

### F. Console & REPL (`CmdX.Console.pas` & `CmdX.pas`)
- Interactive command prompt and history navigation.
- Main entry point and batch file processor loop.
