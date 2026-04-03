@echo off
REM Install Claude Code Explain Pane (Windows)

set CLAUDE_DIR=%USERPROFILE%\.claude
set COMMANDS_DIR=%CLAUDE_DIR%\commands
set HOOKS_DIR=%CLAUDE_DIR%\hooks
set TMP_DIR=%CLAUDE_DIR%\tmp

echo Installing Claude Code Explain Pane...

if not exist "%COMMANDS_DIR%" mkdir "%COMMANDS_DIR%"
if not exist "%HOOKS_DIR%" mkdir "%HOOKS_DIR%"
if not exist "%TMP_DIR%" mkdir "%TMP_DIR%"

copy /Y "%~dp0commands\explain-e.md" "%COMMANDS_DIR%\explain-e.md"
copy /Y "%~dp0scripts\watcher.sh"      "%HOOKS_DIR%\explain-watcher.sh"
copy /Y "%~dp0scripts\open-pane.sh"    "%HOOKS_DIR%\explain-open-pane.sh"
copy /Y "%~dp0scripts\explain-send.sh" "%HOOKS_DIR%\explain-send.sh"

echo.
echo Installed!
echo.
echo Usage:  /explain-e [your question]  in Claude Code
echo.
pause
