# Install script for Simple Program Launcher on Windows
# Sets up auto-start via Registry

$ErrorActionPreference = "Stop"

$projectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$binaryName = "launcher.exe"
$installDir = "$env:LOCALAPPDATA\Programs\Launcher"
$configDir = "$env:APPDATA\launcher"

Write-Host "Simple Program Launcher - Windows Installer" -ForegroundColor Green
Write-Host "============================================"

# Build release binary (if Rust is available)
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Write-Host "`nBuilding release binary..." -ForegroundColor Yellow
    Set-Location $projectDir
    cargo build --release

    # Copy binary
    Write-Host "`nInstalling binary to $installDir..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Copy-Item "$projectDir\target\release\$binaryName" "$installDir\" -Force
} elseif (Test-Path "$projectDir\launcher.pyw") {
    # Use Python version
    Write-Host "`nUsing Python version..." -ForegroundColor Yellow
    $installDir = $projectDir
    $binaryName = "launcher.pyw"
}

# Create config directory
Write-Host "`nSetting up configuration..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
if (-not (Test-Path "$configDir\config.json")) {
    Copy-Item "$projectDir\config\default_config.json" "$configDir\config.json"
    Write-Host "Created default config at $configDir\config.json"
}

# Add to startup (Registry)
Write-Host "`nAdding to Windows startup..." -ForegroundColor Yellow
$startupPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$launcherPath = "$installDir\$binaryName"

if ($binaryName -eq "launcher.pyw") {
    # Use pythonw for .pyw files
    $launcherPath = "pythonw `"$installDir\$binaryName`""
}

Set-ItemProperty -Path $startupPath -Name "SimpleProgramLauncher" -Value $launcherPath

Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host "============================================"
Write-Host "Binary:  $installDir\$binaryName" -ForegroundColor Yellow
Write-Host "Config:  $configDir\config.json" -ForegroundColor Yellow
Write-Host ""
Write-Host "The launcher will start automatically on login."
Write-Host "Trigger: Press L+R mouse buttons simultaneously!" -ForegroundColor Green

# Ask to start now
$response = Read-Host "`nStart the launcher now? (y/n)"
if ($response -eq 'y' -or $response -eq 'Y') {
    if ($binaryName -eq "launcher.pyw") {
        Start-Process pythonw -ArgumentList "$installDir\$binaryName" -WindowStyle Hidden
    } else {
        Start-Process "$installDir\$binaryName" -WindowStyle Hidden
    }
    Write-Host "Launcher started!" -ForegroundColor Green
}
