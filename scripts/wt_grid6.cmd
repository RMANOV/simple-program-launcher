@echo off
REM ═══════════════════════════════════════════════════════════
REM  Grid Layout — 6 panes: 2x2 equal left + 2 equal tall right
REM  4 equal columns (25%%), left 2 split horizontally at 50%%
REM  Strategy: sequential column splits, then 50/50 row splits on the first two columns
REM  ┌────┬────┬─────────┬─────────┐
REM  │ 1  │ 2  │         │         │
REM  ├────┼────┤    3    │    4    │
REM  │ 5  │ 6  │         │         │
REM  └────┴────┴─────────┴─────────┘
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code Soft" -d "C:\Users\rmanov" ; split-pane -V -s 0.75 --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.666667 -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.50 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 0 ; split-pane -H -s 0.50 --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" ; move-focus right ; split-pane -H -s 0.50 --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" ; move-focus right
