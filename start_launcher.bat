@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "EXE_NAME=MouseLauncher.exe"
set "EXE_PATH=%SCRIPT_DIR%%EXE_NAME%"

:: Copy pythonw.exe to unique name if not exists
if not exist "%EXE_PATH%" (
    for /f "delims=" %%i in ('where pythonw.exe 2^>nul') do (
        copy "%%i" "%EXE_PATH%" >nul
        goto :run
    )
    echo ERROR: pythonw.exe not found
    pause
    exit /b 1
)

:run
:: Kill existing instance
taskkill /F /IM "%EXE_NAME%" >nul 2>&1

:: Start with unique process name
start "" "%EXE_PATH%" "%SCRIPT_DIR%launcher.pyw"
