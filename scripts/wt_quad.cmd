@echo off
REM ═══════════════════════════════════════════════════════════
REM  Quad Layout — 4 vertical panes (12.5% | 25% | 25% | 37.5%)
REM  Leftmost: smallest utility pane (12.5%) | Middle pair: equal secondary panes (25% each)
REM  Right: MAIN (37.5%)
REM  Strategy: carve the smallest pane, carve the main pane, then split the middle block in half
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.875 -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.428571 -p "Claude Code" -d "C:\Users\rmanov" ; move-focus left ; split-pane -V -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 2
