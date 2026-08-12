@echo off
REM Quad Layout - 4 vertical panes (20%% | 20%% | 20%% | 40%%)
REM  Left: persistent Claude slot | next: persistent Codex slot
REM  Remaining panes: CMD + Clink audit prompt | Right: MAIN 40%%
REM  Re-running this file focuses the existing layout; it does not duplicate it.
set "PANE_HOST=%~dp0session_pane.ps1"
set "PANE_SLOT=%~dp0session_pane_slot.cmd"

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PANE_HOST%" -Mode PrepareLayout
set "LAYOUT_RC=%ERRORLEVEL%"
if "%LAYOUT_RC%"=="0" exit /b 0
if not "%LAYOUT_RC%"=="10" exit /b %LAYOUT_RC%

REM One bootstrap owner: only this command creates the named canonical window.
REM Each managed slot has a supervisor, so a broker crash is repaired in the
REM same pane instead of appending a second tab.
REM In a CMD script the WT command delimiters must be written as \;.
REM Without the backslash WT can consume the remainder as arguments to the
REM first profile, leaving ordinary profile shells instead of the two hosts.
start "" wt.exe -w RManovQuad new-tab --title "Claude slot" --suppressApplicationTitle -p "Claude Code Soft" -d "C:\Users\rmanov" cmd.exe /d /c call "%PANE_SLOT%" claude \; split-pane -V -s 0.80 --title "Codex slot" --suppressApplicationTitle --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" cmd.exe /d /c call "%PANE_SLOT%" codex \; split-pane -V -s 0.75 --title "Shell" --suppressApplicationTitle --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" \; split-pane -V -s 0.6667 --title "MAIN" --suppressApplicationTitle -p "Claude Code" -d "C:\Users\rmanov" \; move-focus first
exit /b 0
