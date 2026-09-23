@echo off
REM ═══════════════════════════════════════════════════════════
REM  Quad Layout — 4 vertical panes (20% | 20% | 20% | 40%)
REM  3 equal secondary panes (DeepFocus) | Right: MAIN 40% (DeepFocusContrast)
REM  Strategy: binary tree split — all secondary panes at equal depth (2 levels)
REM  Step 1: 40/60  Step 2: split right 1:2  Step 3: split left 1:1
REM ═══════════════════════════════════════════════════════════
start "" wt.exe -p "Claude Code Soft" -d "C:\Users\rmanov" ; split-pane -V -s 0.60 --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" ; split-pane -V -s 0.6667 -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 0 ; split-pane -V -s 0.50 --colorScheme "DeepFocus" -p "Claude Code" -d "C:\Users\rmanov" ; focus-pane -t 2
