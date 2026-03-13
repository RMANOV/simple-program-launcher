@echo off
title Admin Setup: Claude Cowork + Feature Cleanup
color 0D
echo.
echo   ADMIN SETUP: Claude Cowork + Feature Cleanup
echo   =============================================
echo   This script requires administrator privileges.
echo   You will be prompted for admin password once.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0admin_setup_cowork.ps1"
echo.
pause
