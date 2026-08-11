@echo off
REM ============================================================
REM  Codex Resume - idempotent request to the fixed quad pane.
REM  Exact UUID is stored by /restart; a repeated click only focuses.
REM ============================================================
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0session_pane.ps1" -Mode Request -Agent codex
exit /b %ERRORLEVEL%
