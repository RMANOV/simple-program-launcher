# Disk Cleanup Script
# Почиства: uv cache, temp files, Claude sessions, .node cache, pip/npm cache, Snipping Tool temp, OneDrive Screenshots, Recycle Bin
#           Browser caches (Chrome/Edge), VS Code caches, OneDrive logs, Teams cache, OfficeHub EBWebView cache, Cargo cache
# Автор: rmanov | Дата: 2026-01-19 | Обновен: 2026-03-31 (OfficeHub cache, Cargo cache, Claude VM advisory)

$LogFile = "$env:TEMP\disk_cleanup.log"
$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$TotalFreedMB = 0

# --- Opt-in flags for heavy cleanup ---
$CleanCoworkVM = $false    # Set $true to delete Cowork VM (12G, needs re-download on next use)
$CleanMLModels = $false    # Set $true to delete Whisper/HuggingFace models (3.5G, re-downloadable)

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

$PendingUpdate = Test-PendingWindowsUpdate
if ($PendingUpdate) {
    Write-Host "  [!] Pending Windows Update detected -> update-safe cleanup mode" -ForegroundColor Yellow
    Add-Content $LogFile "Pending Windows Update: YES (update-safe cleanup mode)"
} else {
    Add-Content $LogFile "Pending Windows Update: NO"
}

# 1. Clean uv cache (Python package manager - can grow to 40+ GB!)
$UvFreed = 0
$UvCachePath = "$env:LOCALAPPDATA\uv\cache"
if (Test-Path $UvCachePath) {
    $UvBefore = (Get-ChildItem $UvCachePath -Recurse -Force -File -ErrorAction SilentlyContinue |
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
$TempBefore = (Get-ChildItem $env:TEMP -Recurse -Force -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
    Where-Object { $name = $_.FullName; -not ($TempExclude | Where-Object { $name -like "*\$_*" }) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $env:TEMP -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $name = $_.Name; -not ($TempExclude | Where-Object { $name -like $_ }) } |
    Where-Object { (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue).Count -eq 0 } |
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
$TempAfter = (Get-ChildItem $env:TEMP -Recurse -Force -File -ErrorAction SilentlyContinue |
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

# 3b. Clean Claude Code debug logs (>7 days old, can grow to ~1GB)
$ClaudeDebugDir = "$env:USERPROFILE\.claude\debug"
$ClaudeDebugFreed = 0
if (Test-Path $ClaudeDebugDir) {
    $OldDebugFiles = Get-ChildItem $ClaudeDebugDir -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    if ($OldDebugFiles) {
        $ClaudeDebugFreed = [math]::Round(($OldDebugFiles | Measure-Object Length -Sum).Sum / 1MB, 0)
        $OldDebugFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        $TotalFreedMB += $ClaudeDebugFreed
        Add-Content $LogFile "Cleaned Claude debug logs: $ClaudeDebugFreed MB freed ($($OldDebugFiles.Count) files)"
        Write-Host "  Claude debug:  $($OldDebugFiles.Count) old files, $ClaudeDebugFreed MB freed" -ForegroundColor Cyan
    } else {
        Add-Content $LogFile "No old Claude debug logs to clean"
        Write-Host "  Claude debug:  clean" -ForegroundColor DarkGray
    }
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

# 7. Browser Caches (Chrome & Edge, incl. Service Worker caches)
$BrowserFreed = 0
$BrowserRoots = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
)
foreach ($root in $BrowserRoots) {
    if (Test-Path $root) {
        $profiles = Get-ChildItem $root -Directory -EA SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
        foreach ($profile in $profiles) {
            $BrowserPaths = @(
                "$($profile.FullName)\Cache",
                "$($profile.FullName)\Code Cache",
                "$($profile.FullName)\GPUCache",
                "$($profile.FullName)\Service Worker\CacheStorage",
                "$($profile.FullName)\GrShaderCache",
                "$($profile.FullName)\DawnGraphiteCache",
                "$($profile.FullName)\DawnWebGPUCache"
            )
            foreach ($bpath in $BrowserPaths) {
                if (Test-Path $bpath) {
                    $before = (Get-ChildItem $bpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
                    Remove-Item "$bpath\*" -Recurse -Force -EA SilentlyContinue
                    $after = (Get-ChildItem $bpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
                    $BrowserFreed += [math]::Round(($before - $after) / 1MB, 0)
                }
            }
        }
    }
}
$TotalFreedMB += $BrowserFreed
Add-Content $LogFile "Cleaned browser caches: $BrowserFreed MB freed"
Write-Host "  Browser caches: $BrowserFreed MB freed" -ForegroundColor Cyan

# 7b. Chrome OptGuide on-device ML model (2-3GB, auto-redownloads on demand)
$OptGuideFreed = 0
$OptGuidePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\OptGuideOnDeviceModel"
if (Test-Path $OptGuidePath) {
    $sz = (Get-ChildItem $OptGuidePath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($sz -gt 500MB) {
        $OptGuideFreed = [math]::Round($sz / 1MB, 0)
        Remove-Item $OptGuidePath -Recurse -Force -EA SilentlyContinue
        $TotalFreedMB += $OptGuideFreed
        Add-Content $LogFile "Cleaned Chrome OptGuide ML model: $OptGuideFreed MB freed"
        Write-Host "  Chrome OptGuide: $OptGuideFreed MB freed" -ForegroundColor Cyan
    } else {
        Write-Host "  Chrome OptGuide: small ($([math]::Round($sz/1MB))MB), skipped" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Chrome OptGuide: clean" -ForegroundColor DarkGray
}

# 8. VS Code Caches
$VSCodeFreed = 0
$VSCodePaths = @(
    "$env:APPDATA\Code - Insiders\Cache",
    "$env:APPDATA\Code - Insiders\CachedData",
    "$env:APPDATA\Code - Insiders\GPUCache",
    "$env:APPDATA\Code - Insiders\CachedExtensionVSIXs",
    "$env:APPDATA\Code - Insiders\Crashpad",
    "$env:APPDATA\Code\Cache",
    "$env:APPDATA\Code\CachedData",
    "$env:APPDATA\Code\GPUCache",
    "$env:APPDATA\Code\CachedExtensionVSIXs",
    "$env:APPDATA\Code\Crashpad"
)
foreach ($vpath in $VSCodePaths) {
    if (Test-Path $vpath) {
        $before = (Get-ChildItem $vpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item "$vpath\*" -Recurse -Force -EA SilentlyContinue
        $after = (Get-ChildItem $vpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        $VSCodeFreed += [math]::Round(($before - $after) / 1MB, 0)
    }
}
$TotalFreedMB += $VSCodeFreed
Add-Content $LogFile "Cleaned VS Code caches: $VSCodeFreed MB freed"
Write-Host "  VS Code caches: $VSCodeFreed MB freed" -ForegroundColor Cyan

# 9. OneDrive logs (aggressive log cleanup, keeps settings/list sync)
$ODLogsPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\logs"
$ODFreed = 0
$OneDriveExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
$OneDriveWasRunning = $false
$ODLogExtensions = @('.odl', '.odlgz', '.aodl', '.etlgz', '.log', '.loggz')
if (Get-Process OneDrive -EA SilentlyContinue) {
    $OneDriveWasRunning = $true
    Stop-Process -Name OneDrive -Force -EA SilentlyContinue
    Start-Sleep -Milliseconds 800
}
if (Test-Path $ODLogsPath) {
    $before = (Get-ChildItem $ODLogsPath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    Get-ChildItem $ODLogsPath -Recurse -Force -File -EA SilentlyContinue |
        Where-Object { $ODLogExtensions -contains $_.Extension.ToLowerInvariant() } |
        Remove-Item -Force -EA SilentlyContinue
    Get-ChildItem $ODLogsPath -Recurse -Force -Directory -EA SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { (Get-ChildItem $_.FullName -Force -EA SilentlyContinue).Count -eq 0 } |
        Remove-Item -Force -EA SilentlyContinue
    $after = (Get-ChildItem $ODLogsPath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    $ODFreed = [int][math]::Round(($before - $after) / 1MB, 0)
    if ($ODFreed -lt 0) { $ODFreed = 0 }
    $TotalFreedMB += $ODFreed
}
if ($OneDriveWasRunning -and (Test-Path $OneDriveExe)) {
    Start-Process $OneDriveExe -EA SilentlyContinue | Out-Null
}
Add-Content $LogFile "Cleaned OneDrive logs: $ODFreed MB freed"
Write-Host "  OneDrive logs: $ODFreed MB freed" -ForegroundColor Cyan

# 10. Teams Cache (EBWebView/WV2Profile caches + logs)
$TeamsFreed = 0
$TeamsPaths = @(
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\Cache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\Code Cache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\GPUCache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\Service Worker\CacheStorage",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\GrShaderCache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\DawnGraphiteCache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\DawnWebGPUCache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Logs"
)
foreach ($tpath in $TeamsPaths) {
    if (Test-Path $tpath) {
        $before = (Get-ChildItem $tpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item "$tpath\*" -Recurse -Force -EA SilentlyContinue
        $after = (Get-ChildItem $tpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        $TeamsFreed += [math]::Round(($before - $after) / 1MB, 0)
    }
}
$TotalFreedMB += $TeamsFreed
Add-Content $LogFile "Cleaned Teams cache: $TeamsFreed MB freed"
Write-Host "  Teams cache: $TeamsFreed MB freed" -ForegroundColor Cyan

# 10b. OfficeHub EBWebView cache (Microsoft 365 app shell cache)
$OfficeHubFreed = 0
$OfficeHubBase = "$env:LOCALAPPDATA\Packages\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe\LocalState\EBWebView"
$OfficeHubPaths = @(
    "$OfficeHubBase\Default\Cache",
    "$OfficeHubBase\Default\Code Cache",
    "$OfficeHubBase\Default\GPUCache",
    "$OfficeHubBase\Default\Service Worker\CacheStorage",
    "$OfficeHubBase\GrShaderCache",
    "$OfficeHubBase\DawnGraphiteCache",
    "$OfficeHubBase\DawnWebGPUCache",
    "$OfficeHubBase\component_crx_cache"
)
foreach ($opath in $OfficeHubPaths) {
    if (Test-Path $opath) {
        $before = (Get-ChildItem $opath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item "$opath\*" -Recurse -Force -EA SilentlyContinue
        $after = (Get-ChildItem $opath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        $OfficeHubFreed += [math]::Round(($before - $after) / 1MB, 0)
    }
}
Get-ChildItem "$OfficeHubBase\Default\WebStorage" -Directory -EA SilentlyContinue |
    ForEach-Object {
        $cacheStorage = Join-Path $_.FullName "CacheStorage"
        if (Test-Path $cacheStorage) {
            $before = (Get-ChildItem $cacheStorage -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
            Remove-Item "$cacheStorage\*" -Recurse -Force -EA SilentlyContinue
            $after = (Get-ChildItem $cacheStorage -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
            $OfficeHubFreed += [math]::Round(($before - $after) / 1MB, 0)
        }
    }
$TotalFreedMB += $OfficeHubFreed
Add-Content $LogFile "Cleaned OfficeHub EBWebView cache: $OfficeHubFreed MB freed"
Write-Host "  OfficeHub:     $OfficeHubFreed MB freed" -ForegroundColor Cyan

# 11. Snipping Tool TempState (screenshots/recordings not cleaned on close)
$SnipFreed = 0
$SnipTempPath = "$env:LOCALAPPDATA\Packages\Microsoft.ScreenSketch_8wekyb3d8bbwe\TempState"
if (Test-Path $SnipTempPath) {
    $before = (Get-ChildItem $SnipTempPath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    Get-ChildItem $SnipTempPath -Recurse -Force -File -EA SilentlyContinue |
        Remove-Item -Force -EA SilentlyContinue
    $after = (Get-ChildItem $SnipTempPath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    $SnipFreed = [math]::Round(($before - $after) / 1MB, 0)
    $TotalFreedMB += $SnipFreed
}
Add-Content $LogFile "Cleaned Snipping Tool temp: $SnipFreed MB freed"
Write-Host "  Snipping Tool:  $SnipFreed MB freed" -ForegroundColor Cyan

# 12. OneDrive Screenshots (>30 days old only)
$ScreensFreed = 0
$ScreensPath = Join-Path $env:OneDrive "Pictures\Screenshots"
if (Test-Path $ScreensPath) {
    $oldScreens = Get-ChildItem $ScreensPath -Force -File -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
    if ($oldScreens) {
        $ScreensFreed = [int][math]::Round(($oldScreens | Measure-Object Length -Sum).Sum / 1MB, 0)
        $oldScreens | Remove-Item -Force -EA SilentlyContinue
        if ($ScreensFreed -lt 0) { $ScreensFreed = 0 }
        $TotalFreedMB += $ScreensFreed
    }
}
Add-Content $LogFile "Cleaned OneDrive Screenshots: $ScreensFreed MB freed"
Write-Host "  Screenshots:   $ScreensFreed MB freed" -ForegroundColor Cyan

# 13. Recycle Bin (hidden space consumer - not visible in folder sizes)
$RecycleBefore = [math]::Round((Get-PSDrive C).Free / 1MB, 0)
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
$RecycleAfter = [math]::Round((Get-PSDrive C).Free / 1MB, 0)
$RecycleFreed = $RecycleAfter - $RecycleBefore
if ($RecycleFreed -lt 0) { $RecycleFreed = 0 }
$TotalFreedMB += $RecycleFreed
Add-Content $LogFile "Emptied Recycle Bin: $RecycleFreed MB freed"
Write-Host "  Recycle Bin:    $RecycleFreed MB freed" -ForegroundColor Cyan

# 14. Check for runaway Python processes (memory leak detection)
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

# 15. VS Code chat/session payload cleanup (targets large stale JSON history)
$VSCodeChatFreed = 0
$VSCodeChatFiles = @()
$VSWorkspaceRoots = @(
    "$env:APPDATA\Code - Insiders\User\workspaceStorage",
    "$env:APPDATA\Code\User\workspaceStorage"
)
foreach ($root in $VSWorkspaceRoots) {
    if (Test-Path $root) {
        $VSCodeChatFiles += Get-ChildItem $root -Recurse -Force -File -EA SilentlyContinue |
            Where-Object {
                ($_.FullName -like "*\chatSessions\*.json" -or $_.FullName -like "*\chatEditingSessions\*\state.json") -and
                $_.LastWriteTime -lt (Get-Date).AddDays(-7)
            }
    }
}
$VSEmptyWindowRoots = @(
    "$env:APPDATA\Code - Insiders\User\globalStorage\emptyWindowChatSessions",
    "$env:APPDATA\Code\User\globalStorage\emptyWindowChatSessions"
)
foreach ($root in $VSEmptyWindowRoots) {
    if (Test-Path $root) {
        $VSCodeChatFiles += Get-ChildItem $root -Recurse -Force -File -EA SilentlyContinue |
            Where-Object { $_.Extension -eq ".json" -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    }
}
$VSCodeChatFiles = $VSCodeChatFiles | Sort-Object FullName -Unique
if ($VSCodeChatFiles -and $VSCodeChatFiles.Count -gt 0) {
    $chatBytes = ($VSCodeChatFiles | Measure-Object Length -Sum).Sum
    $VSCodeChatFiles | Remove-Item -Force -EA SilentlyContinue
    $VSCodeChatFreed = [int][math]::Round($chatBytes / 1MB, 0)
    if ($VSCodeChatFreed -lt 0) { $VSCodeChatFreed = 0 }
    $TotalFreedMB += $VSCodeChatFreed
}
Add-Content $LogFile "Cleaned VS Code chat/session payloads: $VSCodeChatFreed MB freed"
Write-Host "  VS Code chat:  $VSCodeChatFreed MB freed" -ForegroundColor Cyan

# 16. Claude Desktop full cleanup (cache, old versions, logs, sessions, VM)
$ClaudeCacheFreed = 0
$ClaudeOldVerFreed = 0
$ClaudeLogsFreed = 0
$ClaudeSessionsFreed = 0
$ClaudeVMFreed = 0
$ClaudeIsRunning = $false
$ClaudeRoot = "$env:APPDATA\Claude"
$ClaudeVmBundleSizeMB = 0
if (Test-Path "$ClaudeRoot\vm_bundles") {
    $vmSize = (Get-ChildItem "$ClaudeRoot\vm_bundles" -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    $ClaudeVmBundleSizeMB = [int][math]::Round($vmSize / 1MB, 0)
}

if (Get-Process claude -EA SilentlyContinue) {
    $ClaudeIsRunning = $true
}

# 16a. Old claude-code versions (keep only latest)
$ccDir = "$ClaudeRoot\claude-code"
if (Test-Path $ccDir) {
    $versions = Get-ChildItem $ccDir -Directory -EA SilentlyContinue | Sort-Object Name -Descending
    if ($versions.Count -gt 1) {
        $oldVersions = $versions | Select-Object -Skip 1
        foreach ($old in $oldVersions) {
            $sz = (Get-ChildItem $old.FullName -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
            Remove-Item $old.FullName -Recurse -Force -EA SilentlyContinue
            $ClaudeOldVerFreed += [int][math]::Round($sz / 1MB, 0)
        }
    }
}
if ($ClaudeOldVerFreed -lt 0) { $ClaudeOldVerFreed = 0 }
$TotalFreedMB += $ClaudeOldVerFreed
Add-Content $LogFile "Cleaned old claude-code versions: $ClaudeOldVerFreed MB freed"
Write-Host "  Claude old ver: $ClaudeOldVerFreed MB freed" -ForegroundColor Cyan

# 16b. Claude Desktop logs (>7 days)
$claudeLogsDir = "$ClaudeRoot\logs"
if (Test-Path $claudeLogsDir) {
    $oldLogs = Get-ChildItem $claudeLogsDir -Recurse -Force -File -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    if ($oldLogs) {
        $sz = ($oldLogs | Measure-Object Length -Sum).Sum
        $oldLogs | Remove-Item -Force -EA SilentlyContinue
        $ClaudeLogsFreed = [int][math]::Round($sz / 1MB, 0)
    }
}
if ($ClaudeLogsFreed -lt 0) { $ClaudeLogsFreed = 0 }
$TotalFreedMB += $ClaudeLogsFreed
Add-Content $LogFile "Cleaned Claude logs: $ClaudeLogsFreed MB freed"
Write-Host "  Claude logs:   $ClaudeLogsFreed MB freed" -ForegroundColor Cyan

# 16c. Local agent mode sessions (>7 days)
$agentSessions = "$ClaudeRoot\local-agent-mode-sessions"
if (Test-Path $agentSessions) {
    $oldSess = Get-ChildItem $agentSessions -Recurse -Force -File -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    if ($oldSess) {
        $sz = ($oldSess | Measure-Object Length -Sum).Sum
        $oldSess | Remove-Item -Force -EA SilentlyContinue
        $ClaudeSessionsFreed = [int][math]::Round($sz / 1MB, 0)
    }
}
if ($ClaudeSessionsFreed -lt 0) { $ClaudeSessionsFreed = 0 }
$TotalFreedMB += $ClaudeSessionsFreed
Add-Content $LogFile "Cleaned Claude agent sessions: $ClaudeSessionsFreed MB freed"
Write-Host "  Claude sessions: $ClaudeSessionsFreed MB freed" -ForegroundColor Cyan

# 16d. Cache/Code Cache (existing behavior, requires Claude not running)
if (-not $ClaudeIsRunning) {
    $ClaudeCacheRoots = @(
        "$ClaudeRoot\Cache\Cache_Data",
        "$ClaudeRoot\Code Cache\js"
    )
    foreach ($root in $ClaudeCacheRoots) {
        if (Test-Path $root) {
            $oldFiles = Get-ChildItem $root -Recurse -Force -File -EA SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
            if ($oldFiles) {
                $before = ($oldFiles | Measure-Object Length -Sum).Sum
                $oldFiles | Remove-Item -Force -EA SilentlyContinue
                $ClaudeCacheFreed += [int][math]::Round($before / 1MB, 0)
            }
        }
    }
    # 16e. sessiondata.vhdx — Cowork session state (recreated automatically)
    $sessionVhdx = "$ClaudeRoot\vm_bundles\claudevm.bundle\sessiondata.vhdx"
    if (Test-Path $sessionVhdx) {
        $sz = (Get-Item $sessionVhdx -EA SilentlyContinue).Length
        Remove-Item $sessionVhdx -Force -EA SilentlyContinue
        $ClaudeCacheFreed += [int][math]::Round($sz / 1MB, 0)
    }
} else {
    Add-Content $LogFile "Claude cache/VM cleanup skipped (claude.exe is running)"
}
if ($ClaudeCacheFreed -lt 0) { $ClaudeCacheFreed = 0 }
$TotalFreedMB += $ClaudeCacheFreed
Add-Content $LogFile "Cleaned Claude cache + sessiondata: $ClaudeCacheFreed MB freed"
if ($ClaudeIsRunning) {
    Write-Host "  Claude cache:  skipped (running)" -ForegroundColor DarkGray
} else {
    Write-Host "  Claude cache:  $ClaudeCacheFreed MB freed" -ForegroundColor Cyan
}

# 16f. Cowork VM full purge (opt-in, 12G+ — needs re-download on next use)
if ($CleanCoworkVM -and -not $ClaudeIsRunning) {
    $vmBundles = "$ClaudeRoot\vm_bundles"
    if (Test-Path $vmBundles) {
        $sz = (Get-ChildItem $vmBundles -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item "$vmBundles\*" -Recurse -Force -EA SilentlyContinue
        $ClaudeVMFreed = [int][math]::Round($sz / 1MB, 0)
    }
    if ($ClaudeVMFreed -lt 0) { $ClaudeVMFreed = 0 }
    $TotalFreedMB += $ClaudeVMFreed
    Add-Content $LogFile "Purged Cowork VM bundles: $ClaudeVMFreed MB freed"
    Write-Host "  Cowork VM:    $ClaudeVMFreed MB freed" -ForegroundColor Yellow
} elseif ($CleanCoworkVM -and $ClaudeIsRunning) {
    Write-Host "  Cowork VM:    skipped (running)" -ForegroundColor DarkGray
}

# 17. WinGet package payload cleanup (old installer remnants)
# NOTE: Portable apps (fd, fzf, etc.) may install to WinGet Packages — verify before cleanup
$WinGetFreed = 0
$WinGetRoot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
if (Test-Path $WinGetRoot) {
    $oldWinGetFiles = Get-ChildItem $WinGetRoot -Recurse -Force -File -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-21) }
    if ($oldWinGetFiles) {
        $before = ($oldWinGetFiles | Measure-Object Length -Sum).Sum
        $oldWinGetFiles | Remove-Item -Force -EA SilentlyContinue
        $WinGetFreed = [int][math]::Round($before / 1MB, 0)
        if ($WinGetFreed -lt 0) { $WinGetFreed = 0 }
        $TotalFreedMB += $WinGetFreed
    }
    Get-ChildItem $WinGetRoot -Recurse -Force -Directory -EA SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { (Get-ChildItem $_.FullName -Force -EA SilentlyContinue).Count -eq 0 } |
        Remove-Item -Force -EA SilentlyContinue
}
Add-Content $LogFile "Cleaned WinGet package payloads: $WinGetFreed MB freed"
Write-Host "  WinGet cache:  $WinGetFreed MB freed" -ForegroundColor Cyan

# 18. Cargo registry cache (safe redownloadable Rust dependency cache)
$CargoFreed = 0
$CargoPaths = @(
    "$env:USERPROFILE\.cargo\registry\cache",
    "$env:USERPROFILE\.cargo\registry\src",
    "$env:USERPROFILE\.cargo\git\db"
)
foreach ($cpath in $CargoPaths) {
    if (Test-Path $cpath) {
        $before = (Get-ChildItem $cpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item "$cpath\*" -Recurse -Force -EA SilentlyContinue
        $after = (Get-ChildItem $cpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
        $CargoFreed += [int][math]::Round(($before - $after) / 1MB, 0)
    }
}
if ($CargoFreed -lt 0) { $CargoFreed = 0 }
$TotalFreedMB += $CargoFreed
Add-Content $LogFile "Cleaned Cargo cache: $CargoFreed MB freed"
Write-Host "  Cargo cache:   $CargoFreed MB freed" -ForegroundColor Cyan

# 19. ML Model Caches (opt-in — large re-downloads)
$MLFreed = 0
if ($CleanMLModels) {
    $MLCachePaths = @(
        "$env:USERPROFILE\.cache\whisper",
        "$env:USERPROFILE\.cache\huggingface"
    )
    foreach ($mlpath in $MLCachePaths) {
        if (Test-Path $mlpath) {
            $sz = (Get-ChildItem $mlpath -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
            Remove-Item "$mlpath\*" -Recurse -Force -EA SilentlyContinue
            $MLFreed += [int][math]::Round($sz / 1MB, 0)
        }
    }
    if ($MLFreed -lt 0) { $MLFreed = 0 }
    $TotalFreedMB += $MLFreed
    Add-Content $LogFile "Cleaned ML model caches (whisper+huggingface): $MLFreed MB freed"
    Write-Host "  ML models:    $MLFreed MB freed" -ForegroundColor Yellow
}

# 20. New Outlook (Olk) logs (>7 days)
$OlkFreed = 0
$OlkLogsPath = "$env:LOCALAPPDATA\Microsoft\Olk\logs"
if (Test-Path $OlkLogsPath) {
    $oldOlkLogs = Get-ChildItem $OlkLogsPath -Recurse -Force -File -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    if ($oldOlkLogs) {
        $sz = ($oldOlkLogs | Measure-Object Length -Sum).Sum
        $oldOlkLogs | Remove-Item -Force -EA SilentlyContinue
        $OlkFreed = [int][math]::Round($sz / 1MB, 0)
    }
}
if ($OlkFreed -lt 0) { $OlkFreed = 0 }
$TotalFreedMB += $OlkFreed
Add-Content $LogFile "Cleaned Olk (new Outlook) logs: $OlkFreed MB freed"
Write-Host "  Outlook logs:  $OlkFreed MB freed" -ForegroundColor Cyan

# Summary
$FreeSpaceAfter = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
$NetFreedGB = [math]::Round($FreeSpaceAfter - $FreeSpaceBefore, 2)
Add-Content $LogFile "Total freed: $TotalFreedMB MB ($([math]::Round($TotalFreedMB/1024,2)) GB)"
Add-Content $LogFile "C: Free after: $FreeSpaceAfter GB (net +$NetFreedGB GB)"
Add-Content $LogFile "=== Cleanup completed ==="

# Console output
Write-Host ""
Write-Host "=== Disk Cleanup Complete ===" -ForegroundColor Green
Write-Host "  uv cache:       $UvFreed MB" -ForegroundColor Cyan
Write-Host "  Temp files:     $TempFreedMB MB" -ForegroundColor Cyan
Write-Host "  Claude JSONL:   $ClaudeFreed MB" -ForegroundColor Cyan
Write-Host "  Claude debug:   $ClaudeDebugFreed MB" -ForegroundColor Cyan
Write-Host "  .node files:    $NodeSizeMB MB ($NodeCount files)" -ForegroundColor Cyan
Write-Host "  Browser caches: $BrowserFreed MB" -ForegroundColor Cyan
Write-Host "  Chrome OptGuide: $OptGuideFreed MB" -ForegroundColor Cyan
Write-Host "  VS Code caches: $VSCodeFreed MB" -ForegroundColor Cyan
Write-Host "  OneDrive logs:  $ODFreed MB" -ForegroundColor Cyan
Write-Host "  Teams cache:    $TeamsFreed MB" -ForegroundColor Cyan
Write-Host "  Snipping Tool:  $SnipFreed MB" -ForegroundColor Cyan
Write-Host "  Screenshots:    $ScreensFreed MB" -ForegroundColor Cyan
Write-Host "  Recycle Bin:    $RecycleFreed MB" -ForegroundColor Cyan
Write-Host "  VS Code chat:   $VSCodeChatFreed MB" -ForegroundColor Cyan
Write-Host "  Claude old ver: $ClaudeOldVerFreed MB" -ForegroundColor Cyan
Write-Host "  Claude logs:    $ClaudeLogsFreed MB" -ForegroundColor Cyan
Write-Host "  Claude sessions:$ClaudeSessionsFreed MB" -ForegroundColor Cyan
Write-Host "  Claude cache:   $ClaudeCacheFreed MB" -ForegroundColor Cyan
Write-Host "  OfficeHub:      $OfficeHubFreed MB" -ForegroundColor Cyan
if ($CleanCoworkVM) {
    Write-Host "  Cowork VM:     $ClaudeVMFreed MB" -ForegroundColor Yellow
} elseif ($ClaudeVmBundleSizeMB -ge 1024) {
    $ClaudeVmBundleSizeGB = [math]::Round($ClaudeVmBundleSizeMB / 1024, 2)
    if ($ClaudeIsRunning) {
        Write-Host "  Advisory: Claude vm_bundles = $ClaudeVmBundleSizeGB GB (close Claude, then opt in with `$CleanCoworkVM = `$true)" -ForegroundColor Yellow
    } else {
        Write-Host "  Advisory: Claude vm_bundles = $ClaudeVmBundleSizeGB GB (opt in with `$CleanCoworkVM = `$true to purge)" -ForegroundColor Yellow
    }
}
Write-Host "  WinGet cache:   $WinGetFreed MB" -ForegroundColor Cyan
Write-Host "  Cargo cache:    $CargoFreed MB" -ForegroundColor Cyan
if ($CleanMLModels) {
    Write-Host "  ML models:     $MLFreed MB" -ForegroundColor Yellow
}
Write-Host "  Outlook logs:   $OlkFreed MB" -ForegroundColor Cyan
Write-Host "  pip/npm cache:  purged" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  TOTAL FREED:  $([math]::Round($TotalFreedMB/1024,2)) GB" -ForegroundColor Yellow
Write-Host "  C: Free now:  $FreeSpaceAfter GB" -ForegroundColor Yellow
Write-Host ""
exit 0
