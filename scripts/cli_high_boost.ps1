# CLI High Boost - CachyOS-Style Aggressive Optimization
# Focus: Terminal, Shell, CLI tools - TOP PRIORITY
# Autor: rmanov | 2026-02-04
# OODA: Observe - Orient - Decide - Act

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "         CLI HIGH BOOST - Terminal/Shell Priority              " -ForegroundColor Magenta
Write-Host "              CachyOS-Style Aggressive Mode                    " -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$StartTime = Get-Date
$Changes = @()

# ============================================
# 1. CLI and TERMINAL PROCESS PRIORITY (TOP)
# ============================================
Write-Host "[1/7] CLI and Terminal Priority Boost..." -ForegroundColor Yellow

# TIER 1: Terminals and Shells - HIGHEST user-level priority
$TerminalProcesses = @(
    "WindowsTerminal", "wt",
    "pwsh", "powershell",
    "bash", "sh",
    "conhost",
    "cmd"
)

# TIER 2: Dev Tools and Claude
$DevProcesses = @(
    "claude",
    "Code - Insiders", "Code",
    "python", "pythonw",
    "node", "npm", "npx",
    "git", "gh",
    "uv", "pip",
    "rg", "fd", "fzf"
)

# TIER 3: Background - demote aggressively
$BackgroundProcesses = @(
    "OneDrive", "OneDriveSetup",
    "Teams", "ms-teams",
    "msedge", "chrome",
    "SearchHost", "SearchIndexer", "SearchProtocolHost",
    "Widgets", "WidgetService",
    "YourPhone", "PhoneExperienceHost",
    "GameBar", "GameBarPresenceWriter",
    "StartMenuExperienceHost",
    "ShellExperienceHost",
    "RuntimeBroker",
    "backgroundTaskHost",
    "SettingsSyncHost"
)

$boosted = 0
$demoted = 0

# Boost terminals to High (max without admin)
foreach ($proc in $TerminalProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.PriorityClass = "High"
            Write-Host "  [!] $($_.Name) -> High (Terminal)" -ForegroundColor Green
            $boosted++
        } catch {}
    }
}

# Boost dev tools to AboveNormal
foreach ($proc in $DevProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.PriorityClass = "AboveNormal"
            Write-Host "  [+] $($_.Name) -> AboveNormal (Dev)" -ForegroundColor Green
            $boosted++
        } catch {}
    }
}

# Demote background to BelowNormal
foreach ($proc in $BackgroundProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.PriorityClass = "BelowNormal"
            Write-Host "  [-] $($_.Name) -> BelowNormal" -ForegroundColor DarkGray
            $demoted++
        } catch {}
    }
}

$Changes += "Priority: $boosted boosted, $demoted demoted"

# ============================================
# 2. CPU AFFINITY - Isolate Background
# ============================================
Write-Host ""
Write-Host "[2/7] CPU Affinity (Background Isolation)..." -ForegroundColor Yellow

$CPUCount = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
Write-Host "  Detected $CPUCount logical processors" -ForegroundColor Gray

# Background gets only 2 cores (mask = 3 = binary 00000011)
$BackgroundMask = 3

$affinitySet = 0
foreach ($proc in @("OneDrive", "Teams", "SearchIndexer", "msedge")) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.ProcessorAffinity = $BackgroundMask
            Write-Host "  $($_.Name) -> Cores 0-1 only" -ForegroundColor Cyan
            $affinitySet++
        } catch {}
    }
}
$Changes += "Affinity: $affinitySet processes limited to 2 cores"

# ============================================
# 3. I/O PRIORITY (Registry-based, persists)
# ============================================
Write-Host ""
Write-Host "[3/7] I/O Priority (Persistent)..." -ForegroundColor Yellow

$IOPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"

# HIGH I/O for CLI tools (IoPriority = 3)
$HighIOTools = @(
    "pwsh.exe", "powershell.exe",
    "WindowsTerminal.exe", "wt.exe",
    "git.exe", "gh.exe",
    "python.exe", "python3.exe",
    "node.exe", "npm.exe",
    "uv.exe", "pip.exe",
    "rg.exe", "fd.exe", "fzf.exe",
    "Code - Insiders.exe", "Code.exe",
    "claude.exe"
)

foreach ($exe in $HighIOTools) {
    $keyPath = "$IOPath\$exe\PerfOptions"
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $keyPath -Name "IoPriority" -Value 3 -Type DWord -ErrorAction SilentlyContinue
}
Write-Host "  High I/O: pwsh, git, python, node, rg, fd, uv, VSCode" -ForegroundColor Green

# LOW I/O for background (IoPriority = 0)
$LowIOTools = @(
    "OneDrive.exe", "SearchIndexer.exe", "SearchProtocolHost.exe",
    "msedge.exe", "chrome.exe", "Teams.exe"
)

foreach ($exe in $LowIOTools) {
    $keyPath = "$IOPath\$exe\PerfOptions"
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $keyPath -Name "IoPriority" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Host "  Low I/O: OneDrive, SearchIndexer, Edge, Teams" -ForegroundColor Cyan

$Changes += "I/O Priority: $($HighIOTools.Count) high, $($LowIOTools.Count) low"

# ============================================
# 4. ENVIRONMENT VARIABLES (CLI-focused)
# ============================================
Write-Host ""
Write-Host "[4/7] Environment Variables (CLI Performance)..." -ForegroundColor Yellow

# Git optimizations
[Environment]::SetEnvironmentVariable("GIT_FLUSH", "1", "User")
[Environment]::SetEnvironmentVariable("GIT_OPTIONAL_LOCKS", "0", "User")
[Environment]::SetEnvironmentVariable("GIT_PARALLEL", "6", "User")

# Python optimizations
[Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "1", "User")
[Environment]::SetEnvironmentVariable("PYTHONOPTIMIZE", "1", "User")
[Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
[Environment]::SetEnvironmentVariable("PYTHONMALLOC", "pymalloc", "User")
[Environment]::SetEnvironmentVariable("PYTHONHASHSEED", "0", "User")

# Node.js optimizations
[Environment]::SetEnvironmentVariable("NODE_OPTIONS", "--max-old-space-size=4096 --no-warnings", "User")
[Environment]::SetEnvironmentVariable("UV_THREADPOOL_SIZE", "6", "User")

# UV (Python) optimizations
[Environment]::SetEnvironmentVariable("UV_NO_PROGRESS", "1", "User")
[Environment]::SetEnvironmentVariable("UV_CONCURRENT_DOWNLOADS", "6", "User")

# Polars/Pandas optimizations
[Environment]::SetEnvironmentVariable("POLARS_MAX_THREADS", "6", "User")
[Environment]::SetEnvironmentVariable("OPENBLAS_NUM_THREADS", "6", "User")

# Telemetry OFF
[Environment]::SetEnvironmentVariable("POWERSHELL_TELEMETRY_OPTOUT", "1", "User")
[Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "User")

Write-Host "  Git: flush=1, no optional locks, parallel=6" -ForegroundColor Green
Write-Host "  Python: no bytecode, optimized, pymalloc" -ForegroundColor Green
Write-Host "  Node: max-old-space=4GB, no-warnings" -ForegroundColor Green
Write-Host "  Telemetry: PowerShell/dotnet OFF" -ForegroundColor Green

$Changes += "Environment: 15 variables optimized"

# ============================================
# 5. MEMORY OPTIMIZATION (Aggressive Trim)
# ============================================
Write-Host ""
Write-Host "[5/7] Memory Optimization (Aggressive)..." -ForegroundColor Yellow

$trimmed = 0
$freedMB = 0

# Trim ALL background processes with >50MB and <1% CPU
Get-Process | Where-Object {
    $_.WorkingSet64 -gt 50MB -and
    $_.Name -notin ($TerminalProcesses + $DevProcesses + @("explorer", "dwm", "csrss", "System"))
} | ForEach-Object {
    try {
        $cpuPercent = 0
        $runtime = (Get-Date) - $_.StartTime
        if ($runtime.TotalSeconds -gt 10) {
            $cpuPercent = ($_.CPU / $runtime.TotalSeconds) * 100
        }

        if ($cpuPercent -lt 1) {
            $beforeMB = [math]::Round($_.WorkingSet64/1MB)
            $_.MinWorkingSet = 1MB
            $afterMB = [math]::Round($_.WorkingSet64/1MB)
            $freed = $beforeMB - $afterMB
            if ($freed -gt 0) {
                $freedMB += $freed
                $trimmed++
            }
        }
    } catch {}
}

Write-Host "  Trimmed $trimmed idle processes (~$freedMB MB)" -ForegroundColor Cyan
$Changes += "Memory: ~${freedMB} MB trimmed from $trimmed processes"

# ============================================
# 6. GIT FSMONITOR (10x faster git status)
# ============================================
Write-Host ""
Write-Host "[6/7] Git FSMonitor (Optional)..." -ForegroundColor Yellow

$gitConfig = "$env:USERPROFILE\.gitconfig"
$fsmonitorEnabled = $false

if (Test-Path $gitConfig) {
    $content = Get-Content $gitConfig -Raw -ErrorAction SilentlyContinue
    if ($content -notmatch "fsmonitor") {
        Write-Host "  FSMonitor not configured. To enable globally:" -ForegroundColor Gray
        Write-Host "    git config --global core.fsmonitor true" -ForegroundColor DarkGray
        Write-Host "    git config --global core.untrackedcache true" -ForegroundColor DarkGray
    } else {
        Write-Host "  FSMonitor: Already configured" -ForegroundColor Green
        $fsmonitorEnabled = $true
    }
} else {
    Write-Host "  Skipped (no .gitconfig found)" -ForegroundColor DarkGray
}

# ============================================
# 7. CONSOLE OPTIMIZATIONS
# ============================================
Write-Host ""
Write-Host "[7/7] Console Optimizations..." -ForegroundColor Yellow

# Enable VirtualTerminalLevel for faster rendering
$consolePath = "HKCU:\Console"
try {
    Set-ItemProperty -Path $consolePath -Name "VirtualTerminalLevel" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Write-Host "  Virtual Terminal: Enabled (faster ANSI)" -ForegroundColor Green
} catch {
    Write-Host "  Virtual Terminal: Skipped" -ForegroundColor DarkGray
}

# QuickEdit OFF (prevents accidental pause)
try {
    Set-ItemProperty -Path $consolePath -Name "QuickEdit" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Write-Host "  QuickEdit: Disabled (no accidental pause)" -ForegroundColor Green
} catch {}

# Larger screen buffer for scrollback
try {
    Set-ItemProperty -Path $consolePath -Name "ScreenBufferSize" -Value 0x270F0078 -Type DWord -ErrorAction SilentlyContinue
    Write-Host "  Screen Buffer: Extended (9999 lines)" -ForegroundColor Green
} catch {}

$Changes += "Console: VT enabled, QuickEdit off, buffer extended"

# ============================================
# SUMMARY
# ============================================
$Duration = ((Get-Date) - $StartTime).TotalSeconds

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "                    CLI HIGH BOOST COMPLETE                    " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "  Applied optimizations:" -ForegroundColor White
foreach ($change in $Changes) {
    Write-Host "    * $change" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  Duration: $([math]::Round($Duration, 2))s" -ForegroundColor Gray
Write-Host ""
Write-Host "  NOTE: Some changes require process restart to take effect." -ForegroundColor DarkGray
Write-Host "        I/O priorities persist across reboots." -ForegroundColor DarkGray
Write-Host ""
