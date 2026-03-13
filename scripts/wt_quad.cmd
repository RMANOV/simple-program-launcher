@echo off
REM ═══════════════════════════════════════════════════════════
REM  Quad Layout — 4 vertical panes (12% | 26% | 26% | 36%)
REM  Leftmost: tertiary | Center-left=Center-right: secondary (exact 50/50) | Right: MAIN
REM  Strategy: split tertiary, split main, go back, split middle in half
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.88 -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.41 -p "Claude Code" -d "C:\Users\rmanov" ; move-focus left ; split-pane -V -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 2
