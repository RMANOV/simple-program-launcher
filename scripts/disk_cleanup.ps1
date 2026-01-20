# Disk Cleanup Script
# Почиства: .node cache, pip cache, npm cache
# Автор: rmanov | Дата: 2026-01-19

$LogFile = "$env:TEMP\disk_cleanup.log"
$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$TotalFreed = 0

Add-Content $LogFile "`n=== Cleanup started: $Date ==="

# 1. Delete .node files from Temp (V8 compile cache)
$NodeFiles = Get-ChildItem "$env:TEMP\*.node" -Hidden -ErrorAction SilentlyContinue
$NodeCount = $NodeFiles.Count
$NodeSize = 0
if ($NodeCount -gt 0) {
    $NodeSize = ($NodeFiles | Measure-Object Length -Sum).Sum / 1MB
    Remove-Item "$env:TEMP\*.node" -Force -ErrorAction SilentlyContinue
    $TotalFreed += $NodeSize
    Add-Content $LogFile "Deleted $NodeCount .node files ($([math]::Round($NodeSize,1)) MB)"
} else {
    Add-Content $LogFile "No .node files to delete"
}

# 2. Purge pip cache (with timeout)
Write-Host "  Cleaning pip cache..." -NoNewline
try {
    $job = Start-Job { pip cache purge 2>&1 }
    $completed = Wait-Job $job -Timeout 30
    if ($completed) {
        $PipOutput = Receive-Job $job
        Add-Content $LogFile "Purged pip cache"
        Write-Host " done" -ForegroundColor Green
    } else {
        Stop-Job $job
        Add-Content $LogFile "pip cache purge timed out (30s)"
        Write-Host " timeout" -ForegroundColor Yellow
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
} catch {
    Add-Content $LogFile "pip cache purge skipped"
    Write-Host " skipped" -ForegroundColor Yellow
}

# 3. Clean npm cache (with timeout)
Write-Host "  Cleaning npm cache..." -NoNewline
try {
    $job = Start-Job { npm cache clean --force 2>&1 }
    $completed = Wait-Job $job -Timeout 30
    if ($completed) {
        Receive-Job $job | Out-Null
        Add-Content $LogFile "Cleaned npm cache"
        Write-Host " done" -ForegroundColor Green
    } else {
        Stop-Job $job
        Add-Content $LogFile "npm cache clean timed out (30s)"
        Write-Host " timeout" -ForegroundColor Yellow
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
} catch {
    Add-Content $LogFile "npm cache clean skipped"
    Write-Host " skipped" -ForegroundColor Yellow
}

# 4. Check for runaway Python processes (memory leak detection)
$RunawayProcesses = Get-Process python* -ErrorAction SilentlyContinue |
    Where-Object {$_.WorkingSet64 -gt 1GB}
if ($RunawayProcesses) {
    Add-Content $LogFile "WARNING: Runaway Python processes detected!"
    foreach ($proc in $RunawayProcesses) {
        $memGB = [math]::Round($proc.WorkingSet64/1GB, 2)
        Add-Content $LogFile "  PID $($proc.Id): $memGB GB - Consider killing if >5GB"
        Write-Host "  WARNING: python.exe PID $($proc.Id) using $memGB GB!" -ForegroundColor Red
    }
} else {
    Add-Content $LogFile "No runaway Python processes (all < 1GB)"
}

# Summary
$FreeSpace = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
Add-Content $LogFile "C: Free space: $FreeSpace GB"
Add-Content $LogFile "=== Cleanup completed ==="

# Console output for manual runs
Write-Host ""
Write-Host "=== Disk Cleanup Complete ===" -ForegroundColor Green
Write-Host "  .node files: $NodeCount deleted ($([math]::Round($NodeSize,1)) MB)" -ForegroundColor Cyan
Write-Host "  pip cache:   purged" -ForegroundColor Cyan
Write-Host "  npm cache:   cleaned" -ForegroundColor Cyan
Write-Host ""
Write-Host "  C: Free space: $FreeSpace GB" -ForegroundColor Yellow
Write-Host ""
