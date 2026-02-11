# CachyOS-Style Optimizations for Windows (No Admin)
# Focuses on: Process Priority, I/O Priority, CPU Affinity, Memory Priority
# Автор: rmanov | 2026-01-20

function Test-PendingWindowsUpdate {
    $pendingKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\RebootRequired"
    )

    foreach ($key in $pendingKeys) {
        if (Test-Path $key) { return $true }
    }

    $volatile = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Updates" -Name UpdateExeVolatile -ErrorAction SilentlyContinue).UpdateExeVolatile
    if ($null -ne $volatile -and [int]$volatile -ne 0) { return $true }

    return $false
}

$pendingUpdate = Test-PendingWindowsUpdate

Write-Host "`n=== CachyOS-Style Windows Optimizer ===" -ForegroundColor Magenta
Write-Host "Scheduler & Priority Optimizations (User-Level)`n" -ForegroundColor Gray
if ($pendingUpdate) {
    Write-Host "  [!] Pending Windows Update detected -> update-safe mode enabled (SearchIndexer untouched)." -ForegroundColor Yellow
}

# ============================================
# 1. PROCESS PRIORITY OPTIMIZATION
# ============================================
Write-Host "[1/5] Process Priority Rules..." -ForegroundColor Yellow

# High priority for development tools
$HighPriority = @("Code - Insiders", "python", "node", "claude")
# Below Normal for background tasks
$LowPriority = @("OneDrive", "Teams", "msedge", "SearchHost", "Widgets")
if ($pendingUpdate) {
    $LowPriority = $LowPriority | Where-Object { $_ -ne "SearchHost" }
}

foreach ($proc in $HighPriority) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.PriorityClass = "AboveNormal"
            Write-Host "  $($_.Name) -> AboveNormal" -ForegroundColor Green
        } catch {}
    }
}

foreach ($proc in $LowPriority) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.PriorityClass = "BelowNormal"
            Write-Host "  $($_.Name) -> BelowNormal" -ForegroundColor Cyan
        } catch {}
    }
}

# ============================================
# 2. CPU AFFINITY - Performance Cores
# ============================================
Write-Host "`n[2/5] CPU Affinity (Performance Cores)..." -ForegroundColor Yellow

# Get number of logical processors
$CPUCount = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
Write-Host "  Detected $CPUCount logical processors" -ForegroundColor Gray

# For i5-8500 (6 cores): Use all cores for dev tools, limit background to 2 cores
$AllCoresMask = [Math]::Pow(2, $CPUCount) - 1  # 0x3F for 6 cores
$LimitedCoresMask = 3  # Only cores 0,1 (0b00000011)

# Set affinity for background processes to limited cores
foreach ($proc in @("OneDrive", "Teams")) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.ProcessorAffinity = $LimitedCoresMask
            Write-Host "  $($_.Name) -> Cores 0-1 only" -ForegroundColor Cyan
        } catch {}
    }
}

# ============================================
# 3. MEMORY WORKING SET TRIM
# ============================================
Write-Host "`n[3/5] Memory Optimization..." -ForegroundColor Yellow

# Trim working set of idle processes
$IdleThreshold = 60  # seconds
$now = Get-Date

Get-Process | Where-Object {
    $_.WorkingSet64 -gt 100MB -and
    $_.Name -notin @("Code - Insiders", "python", "claude", "explorer")
} | ForEach-Object {
    try {
        # Get CPU time - if low, process is idle
        $cpuPercent = ($_.CPU / ((Get-Date) - $_.StartTime).TotalSeconds) * 100
        if ($cpuPercent -lt 1) {
            # Trim working set
            $_.MinWorkingSet = 1MB
            Write-Host "  Trimmed idle: $($_.Name) (was $([math]::Round($_.WorkingSet64/1MB))MB)" -ForegroundColor Gray
        }
    } catch {}
}

# ============================================
# 4. I/O PRIORITY HINTS (via Registry)
# ============================================
Write-Host "`n[4/5] I/O Priority Hints..." -ForegroundColor Yellow

# Set I/O priority hints in registry for known processes
$IOPriorityPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"

# High I/O priority for dev tools
@("python.exe", "node.exe", "Code - Insiders.exe") | ForEach-Object {
    $keyPath = "$IOPriorityPath\$_\PerfOptions"
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $keyPath -Name "IoPriority" -Value 3 -Type DWord -ErrorAction SilentlyContinue
}
Write-Host "  High I/O priority for: python, node, VS Code" -ForegroundColor Green

# Low I/O priority for background
$LowIOTargets = @("OneDrive.exe", "SearchIndexer.exe")
if ($pendingUpdate) {
    $LowIOTargets = @("OneDrive.exe")
    @("SearchIndexer.exe", "SearchProtocolHost.exe") | ForEach-Object {
        $existingPath = "$IOPriorityPath\$_\PerfOptions"
        Remove-ItemProperty -Path $existingPath -Name "IoPriority" -ErrorAction SilentlyContinue
    }
}
$LowIOTargets | ForEach-Object {
    $keyPath = "$IOPriorityPath\$_\PerfOptions"
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $keyPath -Name "IoPriority" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Host "  Low I/O priority for: $($LowIOTargets -join ', ')" -ForegroundColor Cyan

# ============================================
# 5. ENVIRONMENT OPTIMIZATIONS
# ============================================
Write-Host "`n[5/5] Environment Tuning..." -ForegroundColor Yellow

# Python: Use faster allocator
[Environment]::SetEnvironmentVariable("PYTHONMALLOC", "pymalloc", "User")
# Python: Disable hash randomization for reproducibility
[Environment]::SetEnvironmentVariable("PYTHONHASHSEED", "0", "User")
# Git: Parallel operations
[Environment]::SetEnvironmentVariable("GIT_PARALLEL", "6", "User")
# Polars: Use all cores
[Environment]::SetEnvironmentVariable("POLARS_MAX_THREADS", "6", "User")
# UV: Parallel installs
[Environment]::SetEnvironmentVariable("UV_CONCURRENT_DOWNLOADS", "6", "User")

Write-Host "  Python malloc, Git parallel, Polars threads set" -ForegroundColor Green

# ============================================
# SUMMARY
# ============================================
Write-Host "`n=== CachyOS-Style Optimization Complete ===" -ForegroundColor Magenta
Write-Host @"

Applied (CachyOS-inspired):
  [Scheduler]
    - Dev tools: AboveNormal priority
    - Background: BelowNormal priority

  [CPU Affinity]
    - Background apps: Limited to cores 0-1
    - Dev tools: All 6 cores available

  [Memory]
    - Trimmed idle process working sets

  [I/O Priority]
    - python/node/VSCode: High I/O
    - OneDrive/Search: Low I/O

  [Environment]
    - Python pymalloc allocator
    - Parallel Git/Polars/UV operations

Run this script periodically or add to Task Scheduler.
Some changes require process restart to take effect.

"@ -ForegroundColor Cyan
