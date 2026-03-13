@echo off
REM ═══════════════════════════════════════════════════════════
REM  Trio Layout — 3 vertical panes (25% | 25% | 50%)
REM  Left=Center: secondary (exact 50/50) | Right: MAIN
REM  Strategy: split main first, go back, split remainder in half
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; move-focus left ; split-pane -V -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 1
