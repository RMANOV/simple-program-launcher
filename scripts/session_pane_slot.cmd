@echo off
setlocal

rem Resident slot supervisor.  It keeps the Claude/Codex broker connection in
rem this exact WT pane and restarts only the broker process after an error.
set "AGENT=%~1"
if /i not "%AGENT%"=="claude" if /i not "%AGENT%"=="codex" exit /b 2

:again
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0session_pane.ps1" -Mode Host -Agent "%AGENT%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="88" exit /b 0
timeout /t 1 /nobreak >nul
goto again
