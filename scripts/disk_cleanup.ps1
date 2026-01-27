# Disk Cleanup Script
# Почиства: uv cache, temp files, Claude sessions, .node cache, pip/npm cache
# Автор: rmanov | Дата: 2026-01-19 | Обновен: 2026-01-27 (uv cache, temp, Claude sessions)

$LogFile = "$env:TEMP\disk_cleanup.log"
$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$TotalFreedMB = 0

Add-Content $LogFile "`n=== Cleanup started: $Date ==="
$FreeSpaceBefore = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
Add-Content $LogFile "C: Free before: $FreeSpaceBefore GB"

# --- Helper: run command with timeout ---
function Invoke-WithTimeout {
    param([scriptblock]$Script, [int]$TimeoutSec = 120, [string]$Name)
    Write-Host "  Cleaning $Name..." -NoNewline
    try {
        $job = Start-Job -ScriptBlock $Script
        $completed = Wait-Job $job -Timeout $TimeoutSec
        if ($completed) {
            $output = Receive-Job $job
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Write-Host " done" -ForegroundColor Green
            return $output
        } else {
            Stop-Job $job
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Add-Content $LogFile "$Name timed out (${TimeoutSec}s)"
            Write-Host " timeout" -ForegroundColor Yellow
            return $null
        }
    } catch {
        Add-Content $LogFile "$Name skipped: $($_.Exception.Message)"
        Write-Host " skipped" -ForegroundColor Yellow
        return $null
    }
}

# 1. Clean uv cache (Python package manager — can grow to 40+ GB!)
$UvFreed = 0
$UvCachePath = "$env:LOCALAPPDATA\uv\cache"
if (Test-Path $UvCachePath) {
    $UvBefore = (Get-ChildItem $UvCachePath -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $UvBeforeMB = [math]::Round($UvBefore / 1MB, 0)
    Write-Host "  Cleaning uv cache ($UvBeforeMB MB)..." -NoNewline
    $uvResult = Invoke-WithTimeout -Script { uv cache clean 2>&1 } -TimeoutSec 300 -Name "uv cache"
    # uv cache clean deletes everything, so freed = before size
    if ($uvResult) {
        $UvFreed = $UvBeforeMB
        $TotalFreedMB += $UvFreed
        Add-Content $LogFile "Cleaned uv cache: $UvFreed MB freed"
    }
} else {
    Write-Host "  uv cache: not found" -ForegroundColor DarkGray
    Add-Content $LogFile "uv cache not found"
}

# 2. Clean old temp files (>1 day old, skip locked)
# Exclude dirs needed by apps between restarts (VSCode Insiders updater, etc.)
$TempExclude = @('vscode-insider*')
$TempBefore = (Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
    Where-Object { $name = $_.FullName; -not ($TempExclude | Where-Object { $name -like "*\$_*" }) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $env:TEMP -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $name = $_.Name; -not ($TempExclude | Where-Object { $name -like $_ }) } |
    Where-Object { (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue).Count -eq 0 } |
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
$TempAfter = (Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
$TempFreedMB = [math]::Round(($TempBefore - $TempAfter) / 1MB, 0)
$TotalFreedMB += $TempFreedMB
Add-Content $LogFile "Cleaned temp files: $TempFreedMB MB freed"
Write-Host "  Temp cleanup: $TempFreedMB MB freed" -ForegroundColor Cyan

# 3. Clean old Claude Code sessions (JSONL >5MB, >7 days old)
$ClaudeProjects = "$env:USERPROFILE\.claude\projects"
$ClaudeFreed = 0
if (Test-Path $ClaudeProjects) {
    $OldSessions = Get-ChildItem $ClaudeProjects -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.jsonl' -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) -and $_.Length -gt 5MB }
    if ($OldSessions) {
        $ClaudeFreed = [math]::Round(($OldSessions | Measure-Object Length -Sum).Sum / 1MB, 0)
        $OldSessions | Remove-Item -Force -ErrorAction SilentlyContinue
        $TotalFreedMB += $ClaudeFreed
        Add-Content $LogFile "Cleaned $($OldSessions.Count) Claude sessions: $ClaudeFreed MB freed"
        Write-Host "  Claude sessions: $($OldSessions.Count) old files, $ClaudeFreed MB freed" -ForegroundColor Cyan
    } else {
        Add-Content $LogFile "No old Claude sessions to clean"
        Write-Host "  Claude sessions: clean" -ForegroundColor DarkGray
    }
} else {
    Add-Content $LogFile "Claude projects folder not found"
}

# 4. Delete .node files from Temp (V8 compile cache)
$NodeFiles = Get-ChildItem "$env:TEMP\*.node" -Hidden -ErrorAction SilentlyContinue
$NodeCount = $NodeFiles.Count
$NodeSizeMB = 0
if ($NodeCount -gt 0) {
    $NodeSizeMB = [math]::Round(($NodeFiles | Measure-Object Length -Sum).Sum / 1MB, 0)
    Remove-Item "$env:TEMP\*.node" -Force -ErrorAction SilentlyContinue
    $TotalFreedMB += $NodeSizeMB
    Add-Content $LogFile "Deleted $NodeCount .node files ($NodeSizeMB MB)"
} else {
    Add-Content $LogFile "No .node files to delete"
}

# 5. Purge pip cache (with timeout)
Invoke-WithTimeout -Script { pip cache purge 2>&1 } -TimeoutSec 30 -Name "pip cache" | Out-Null
Add-Content $LogFile "Purged pip cache"

# 6. Clean npm cache (with timeout)
Invoke-WithTimeout -Script { npm cache clean --force 2>&1 } -TimeoutSec 30 -Name "npm cache" | Out-Null
Add-Content $LogFile "Cleaned npm cache"

# 7. Check for runaway Python processes (memory leak detection)
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
$FreeSpaceAfter = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
$NetFreedGB = [math]::Round($FreeSpaceAfter - $FreeSpaceBefore, 2)
Add-Content $LogFile "Total freed: $TotalFreedMB MB ($([math]::Round($TotalFreedMB/1024,2)) GB)"
Add-Content $LogFile "C: Free after: $FreeSpaceAfter GB (net +$NetFreedGB GB)"
Add-Content $LogFile "=== Cleanup completed ==="

# Console output
Write-Host ""
Write-Host "=== Disk Cleanup Complete ===" -ForegroundColor Green
Write-Host "  uv cache:    $UvFreed MB freed" -ForegroundColor Cyan
Write-Host "  Temp files:  $TempFreedMB MB freed" -ForegroundColor Cyan
Write-Host "  Claude:      $ClaudeFreed MB freed" -ForegroundColor Cyan
Write-Host "  .node files: $NodeCount deleted ($NodeSizeMB MB)" -ForegroundColor Cyan
Write-Host "  pip cache:   purged" -ForegroundColor Cyan
Write-Host "  npm cache:   cleaned" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total freed:  $([math]::Round($TotalFreedMB/1024,2)) GB" -ForegroundColor Yellow
Write-Host "  C: Free now:  $FreeSpaceAfter GB" -ForegroundColor Yellow
Write-Host ""
