@echo off
REM ============================================================
REM  Status - zaetost na 18-te poluchatelya (hora + zali)
REM  Chete free/busy prez Outlook. NISHTO ne se izprashta.
REM
REM  Skriptat zhivee V REPOTO, za da ne zavisi ot neversioniran
REM  fail v Documents.
REM
REM  VNIMANIE: %~dp0 zavarshva s "\". Ako se podade kato "%~dp0",
REM  finalniyat backslash escape-va kavichkata i patyat se reje
REM  na parviya interval (D:\OneDrive | - Kreston ...). Zatova
REM  trailing backslash se maha PREDI upotreba.
REM
REM  -NoExit ostavya prompt-a v scripts\, taka che vednaga mozhe:
REM     .\razuznavach.ps1 -At 13:30      (srez v konkreten chas)
REM     .\razuznavach.ps1 -Days 3        (tri dni napred)
REM     .\razuznavach.ps1 -Watch         (zhivo, na 60 sek)
REM ============================================================
set "SDIR=%~dp0"
if "%SDIR:~-1%"=="\" set "SDIR=%SDIR:~0,-1%"
start "" wt.exe -d "%SDIR%" pwsh.exe -NoExit -File "%SDIR%\razuznavach.ps1"
