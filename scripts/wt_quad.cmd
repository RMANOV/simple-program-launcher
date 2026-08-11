@echo off
REM Quad Layout - 4 vertical panes (20%% | 20%% | 20%% | 40%%)
REM  Left: persistent Claude slot | next: persistent Codex slot
REM  Remaining panes: CMD + Clink audit prompt | Right: MAIN 40%%
REM  Re-running this file focuses the existing layout; it does not duplicate it.
set "PANE_HOST=%~dp0session_pane.ps1"
set "PANE_SLOT=%~dp0session_pane_slot.cmd"
if not defined SPL_WT_WORKDIR set "SPL_WT_WORKDIR=%USERPROFILE%"
if not defined SPL_WT_PROFILE set "SPL_WT_PROFILE=PowerShell"
if not defined SPL_WT_PROFILE_SOFT set "SPL_WT_PROFILE_SOFT=%SPL_WT_PROFILE%"

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PANE_HOST%" -Mode PrepareLayout
set "LAYOUT_RC=%ERRORLEVEL%"
if "%LAYOUT_RC%"=="0" exit /b 0
if not "%LAYOUT_RC%"=="10" exit /b %LAYOUT_RC%

REM One bootstrap owner: only this command creates the named canonical window.
REM Each managed slot has a supervisor, so a broker crash is repaired in the
REM same pane instead of appending a second tab.
start "" wt.exe -w SimpleProgramLauncherQuad new-tab --title "Claude slot" --suppressApplicationTitle -p "%SPL_WT_PROFILE_SOFT%" -d "%SPL_WT_WORKDIR%" cmd.exe /d /c call "%PANE_SLOT%" claude ; split-pane -V -s 0.80 --title "Codex slot" --suppressApplicationTitle --colorScheme "DeepFocus" -p "%SPL_WT_PROFILE%" -d "%SPL_WT_WORKDIR%" cmd.exe /d /c call "%PANE_SLOT%" codex ; split-pane -V -s 0.75 --title "Shell" --suppressApplicationTitle --colorScheme "DeepFocus" -p "%SPL_WT_PROFILE%" -d "%SPL_WT_WORKDIR%" ; split-pane -V -s 0.6667 --title "MAIN" --suppressApplicationTitle -p "%SPL_WT_PROFILE%" -d "%SPL_WT_WORKDIR%" ; move-focus first
exit /b 0
