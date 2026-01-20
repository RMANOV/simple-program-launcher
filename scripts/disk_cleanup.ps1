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

# 2. Purge pip cache
try {
    $PipOutput = pip cache purge 2>&1
    if ($PipOutput -match "Files removed: (\d+) \(([^)]+)\)") {
        Add-Content $LogFile "Purged pip cache: $($Matches[1]) files ($($Matches[2]))"
    } else {
        Add-Content $LogFile "Purged pip cache"
    }
} catch {
    Add-Content $LogFile "pip cache purge skipped (pip not available)"
}

# 3. Clean npm cache
try {
    npm cache clean --force 2>$null
    Add-Content $LogFile "Cleaned npm cache"
} catch {
    Add-Content $LogFile "npm cache clean skipped (npm not available)"
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
