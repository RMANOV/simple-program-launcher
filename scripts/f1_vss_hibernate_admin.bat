@echo off
title Admin: VSS limit 1GB + Hibernate OFF (frees C:)
color 0D
echo.
echo   ADMIN: VSS shadow storage limit + Hibernate OFF
echo   ================================================
echo   Root cause of the "disappearing 6-8 GB" on C: (see N:\STORAGE_E14_20260910\CHECKPOINT_1_20260910.md)
echo   Requires administrator credentials once (UAC prompt).
echo   Does: vssadmin resize shadowstorage /for=C: /on=C: /maxsize=1GB  +  powercfg /hibernate off
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0f1_vss_hibernate_admin.ps1"
echo.
pause
