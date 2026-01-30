# Setup CachyOS Optimizer as Scheduled Task (replaces VBS launcher)
# No admin required - creates user-level task
# Run once to setup, then delete BoostPC.vbs from Startup

$TaskName = "CachyOS-Optimizer"
$ScriptPath = "$env:OneDrive\utilities\launcher\scripts\cachyos_optimizer.ps1"

# Check if script exists
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: Script not found: $ScriptPath" -ForegroundColor Red
    exit 1
}

# Remove existing task if any
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create action - PowerShell hidden
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File "$ScriptPath"
"@

# Trigger at logon
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Principal - current user, no admin
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# Register task
try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "CachyOS-style Windows optimizer - runs at logon"
    Write-Host "`n✅ Task '$TaskName' created successfully!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Test: schtasks /run /tn `"$TaskName`""
    Write-Host "  2. Delete: %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\BoostPC.vbs"
    Write-Host "  3. Verify: Task Scheduler > Task Scheduler Library > $TaskName"
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nAlternative: Create task manually in Task Scheduler GUI" -ForegroundColor Yellow
}
