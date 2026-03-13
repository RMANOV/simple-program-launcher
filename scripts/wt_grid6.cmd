@echo off
REM ═══════════════════════════════════════════════════════════
REM  Grid Layout — 6 panes: 2x2 left + 2 tall right
REM  4 equal columns (25%%), left 2 split horizontally at 50%%
REM  Strategy: flat sequential splits (no nesting) to avoid border pixel imbalance
REM  ┌────┬────┬─────────┬─────────┐
REM  │ 1  │ 2  │         │         │
REM  ├────┼────┤    3    │    4    │
REM  │ 5  │ 6  │         │         │
REM  └────┴────┴─────────┴─────────┘
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.75 -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.667 -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 0 ; split-pane -H -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; move-focus right ; split-pane -H -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; move-focus right
