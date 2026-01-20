@echo off
title Disk Cleanup
powershell -ExecutionPolicy Bypass -File "%~dp0disk_cleanup.ps1"
pause
