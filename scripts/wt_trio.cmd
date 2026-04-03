@echo off
REM ═══════════════════════════════════════════════════════════
REM  Trio Layout — 3 vertical panes (25% | 25% | 50%)
REM  Left + Center: equal secondary panes (25% each) | Right: MAIN (50%)
REM  Strategy: split the main pane first, then split the remaining block in half
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code Soft" -d "C:\Users\rmanov" ; split-pane -V -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; move-focus left ; split-pane -V -s 0.50 --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 1
