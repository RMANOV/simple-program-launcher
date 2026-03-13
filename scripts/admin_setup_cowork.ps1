# Admin Setup: Claude Cowork + Feature Cleanup
# Enables Hyper-V for Claude Cowork VM, disables unused Windows features
# Requires: Admin elevation (UAC prompt, one-time password entry)
# Author: rmanov | Date: 2026-03-05

# ============================================
# STEP 0: UAC SELF-ELEVATION
# ============================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting admin elevation..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "   ADMIN SETUP: Claude Cowork + Feature Cleanup                " -ForegroundColor Magenta
Write-Host "   Running as Administrator                                     " -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$NeedsReboot = $false
$Changes = @()
$Errors = @()

# ============================================
# STEP 1: SYSTEM INFO
# ============================================
Write-Host "[0/3] System Check..." -ForegroundColor Yellow

$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor
$hypervisor = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent

Write-Host "  OS:         $($os.Caption) ($($os.Version))" -ForegroundColor Gray
Write-Host "  CPU:        $($cpu.Name)" -ForegroundColor Gray
Write-Host "  VT-x:       $($cpu.VirtualizationFirmwareEnabled)" -ForegroundColor Gray
Write-Host "  Hypervisor: $hypervisor" -ForegroundColor $(if ($hypervisor) { "Green" } else { "Red" })
Write-Host ""

if (-not $cpu.VirtualizationFirmwareEnabled) {
    Write-Host "  [!] VT-x is NOT enabled in BIOS. Hyper-V will NOT work!" -ForegroundColor Red
    Write-Host "  [!] Enable Intel VT-x / AMD-V in BIOS first, then re-run." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ============================================
# STEP 2: ENABLE VIRTUALIZATION FEATURES
# ============================================
Write-Host "[1/3] Enabling Virtualization Features (for Claude Cowork)..." -ForegroundColor Yellow
Write-Host ""

$FeaturesToEnable = @(
    @{ Name = "Microsoft-Hyper-V-All";  Desc = "Hyper-V (Management Tools + Platform)" },
    @{ Name = "HypervisorPlatform";     Desc = "Windows Hypervisor Platform" },
    @{ Name = "VirtualMachinePlatform"; Desc = "Virtual Machine Platform" }
)

foreach ($feature in $FeaturesToEnable) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue)
    if ($null -eq $state) {
        Write-Host "  [?] $($feature.Desc): Feature not found (skipped)" -ForegroundColor DarkGray
        continue
    }

    if ($state.State -eq "Enabled") {
        Write-Host "  [=] $($feature.Desc): Already enabled" -ForegroundColor Green
    } else {
        Write-Host "  [+] $($feature.Desc): Enabling..." -ForegroundColor Cyan -NoNewline
        try {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop
            Write-Host " OK" -ForegroundColor Green
            $Changes += "ENABLED: $($feature.Desc)"
            if ($result.RestartNeeded) { $NeedsReboot = $true }
        } catch {
            Write-Host " FAILED" -ForegroundColor Red
            $Errors += "ENABLE $($feature.Name): $($_.Exception.Message)"
        }
    }
}

Write-Host ""

# ============================================
# STEP 3: DISABLE UNUSED FEATURES
# ============================================
Write-Host "[2/3] Disabling Unused Features (freeing resources)..." -ForegroundColor Yellow
Write-Host ""

$FeaturesToDisable = @(
    @{ Name = "Printing-XPSServices-Features";            Desc = "XPS Document Writer" },
    @{ Name = "WorkFolders-Client";                       Desc = "Work Folders Client" },
    @{ Name = "MicrosoftWindowsPowerShellV2Root";          Desc = "PowerShell v2 (security risk)" },
    @{ Name = "MediaPlayback";                             Desc = "Windows Media Player" },
    @{ Name = "Printing-Foundation-InternetPrinting-Client"; Desc = "Internet Printing Client" }
)

foreach ($feature in $FeaturesToDisable) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue)
    if ($null -eq $state) {
        Write-Host "  [?] $($feature.Desc): Feature not found (skipped)" -ForegroundColor DarkGray
        continue
    }

    if ($state.State -eq "Disabled") {
        Write-Host "  [=] $($feature.Desc): Already disabled" -ForegroundColor Green
    } else {
        Write-Host "  [-] $($feature.Desc): Disabling..." -ForegroundColor Cyan -NoNewline
        try {
            $result = Disable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop
            Write-Host " OK" -ForegroundColor Green
            $Changes += "DISABLED: $($feature.Desc)"
            if ($result.RestartNeeded) { $NeedsReboot = $true }
        } catch {
            Write-Host " FAILED" -ForegroundColor Red
            $Errors += "DISABLE $($feature.Name): $($_.Exception.Message)"
        }
    }
}

Write-Host ""

# ============================================
# STEP 4: SUMMARY + REBOOT PROMPT
# ============================================
Write-Host "[3/3] Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "   SETUP COMPLETE                                               " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

if ($Changes.Count -gt 0) {
    Write-Host "  Changes applied:" -ForegroundColor White
    foreach ($c in $Changes) {
        Write-Host "    * $c" -ForegroundColor Cyan
    }
} else {
    Write-Host "  No changes needed (everything already configured)" -ForegroundColor Green
}

if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Errors:" -ForegroundColor Red
    foreach ($e in $Errors) {
        Write-Host "    ! $e" -ForegroundColor Red
    }
}

Write-Host ""

if ($NeedsReboot) {
    Write-Host "  [!] REBOOT REQUIRED for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
    $answer = Read-Host "  Reboot now? (y/N)"
    if ($answer -eq 'y' -or $answer -eq 'Y') {
        Write-Host "  Rebooting in 10 seconds..." -ForegroundColor Yellow
        & shutdown.exe /r /t 10 /c "Admin Setup: Claude Cowork - Reboot for Hyper-V activation"
    } else {
        Write-Host "  OK, reboot manually when ready." -ForegroundColor Gray
    }
} else {
    Write-Host "  No reboot needed." -ForegroundColor Green
}

Write-Host ""
Read-Host "Press Enter to close"
