@echo off
REM ═══════════════════════════════════════════════════════════
REM  Duo Layout — 2 vertical panes (30% | 70%)
REM  Left: secondary/reference (30%) | Right: MAIN (70%)
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.70 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 1
