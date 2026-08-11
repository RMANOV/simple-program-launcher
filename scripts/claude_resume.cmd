@echo off
REM ============================================================
REM  Claude Resume - prodalzhava POSLEDNATA Claude sesiya v ~
REM  Minava prez bashrc wrapper-a: pre-launch patch + /restart loop
REM ============================================================
start "" wt.exe -d "C:\Users\rmanov" "C:\Users\rmanov\AppData\Local\Programs\Git\usr\bin\bash.exe" -ilc "claude --continue"
