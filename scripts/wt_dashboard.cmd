@echo off
REM ═══════════════════════════════════════════════════════════
REM  Dashboard Layout — L-shape (2 equal stacked left + main right)
REM  Left stack: equal secondary panes (22.5% + 22.5%) | Right: MAIN (55%)
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.55 -p "Claude Code" -d "C:\Users\rmanov" ; move-focus left ; split-pane -H -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 1
