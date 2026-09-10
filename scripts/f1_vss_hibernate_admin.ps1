# F1 — VSS shadow storage limit + Hibernate OFF (root cause of the "disappearing 6-8 GB" on C:)
# Operator decision 10.09.2026 15:27 (agreed with Hari): vssadmin maxsize low/conservative + powercfg /hibernate off.
# Prepared by EXECUTOR_14 (Claude session 00916a57); ADVOCATE audit 10.09 15:33 PASS + 2 AMEND (local path, Bypass -File) applied.
#
# USAGE (Hari / anyone with an admin account):
#   double-click scripts\f1_vss_hibernate_admin.bat   -> UAC prompt -> enter admin credentials -> done in ~1 minute
#   or from an elevated PowerShell:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\OneDrive - Крестън БулМар ООД\utilities\launcher\scripts\f1_vss_hibernate_admin.ps1"
#   -ReadOnly  : only readbacks (no elevation needed, changes nothing)   -MaxSize 320MB : lower limit (Windows minimum)
#
# Does exactly: (1) readback  (2) vssadmin resize shadowstorage /for=C: /on=C: /maxsize=<MaxSize>  (3) powercfg /hibernate off  (4) readback + receipt.
# Does NOT touch: pagefile, Windows Update, services, policies, OneDrive; no restart.
# All paths are LOCAL (an elevated token under another account does not see the N: mapping); receipt copy to the share is best-effort.
[CmdletBinding()]
param(
    [string]$MaxSize = '1GB',
    [switch]$ReadOnly
)
$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---- STEP 0: UAC self-elevation (same pattern as admin_setup_cowork.ps1) ----
if (-not $isAdmin -and -not $ReadOnly) {
    Write-Host 'Requesting admin elevation (UAC)...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-MaxSize', $MaxSize)
        Write-Host 'Elevated window started. This window can be closed.' -ForegroundColor Gray
    } catch {
        Write-Host ('Elevation cancelled or failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Nothing was changed. Re-run from an account with admin rights.' -ForegroundColor Red
    }
    exit
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$L = New-Object 'System.Collections.Generic.List[string]'
function Lg($m) { $s = '{0:HH:mm:ss.fff} {1}' -f (Get-Date), $m; $L.Add($s); Write-Host $s }
function CFree { (New-Object System.IO.DriveInfo('C:\')).AvailableFreeSpace }
function HibBytes { $h = New-Object System.IO.FileInfo('C:\hiberfil.sys'); if ($h.Exists) { $h.Length } else { 0 } }   # .NET FileInfo: size from attributes, works non-elevated in PS 5.1 too
function ShadowStorage { $o = & vssadmin list shadowstorage 2>&1; @($o | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\S' }) }

$mode = if ($ReadOnly) { 'READ_ONLY' } else { 'APPLY' }
Lg ('MODE={0}; admin={1}; user={2}; PS {3}' -f $mode, $isAdmin, [Security.Principal.WindowsIdentity]::GetCurrent().Name, $PSVersionTable.PSVersion)
Lg ('BEFORE: C free {0:N0} B; hiberfil.sys {1:N0} B' -f (CFree), (HibBytes))
$ssBefore = ShadowStorage
Lg '--- vssadmin list shadowstorage (BEFORE) ---'; $ssBefore | ForEach-Object { Lg ('  ' + $_) }

$rs = @(); $pc = @()
if (-not $ReadOnly) {
    Lg ('--- vssadmin resize shadowstorage /for=C: /on=C: /maxsize={0} ---' -f $MaxSize)
    $rs = @(& vssadmin resize shadowstorage /for=C: /on=C: /maxsize=$MaxSize 2>&1 | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\S' })
    $rs | ForEach-Object { Lg ('  ' + $_) }
    Lg '--- powercfg /hibernate off ---'
    $pc = @(& powercfg /hibernate off 2>&1 | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\S' })
    if ($pc.Count -gt 0) { $pc | ForEach-Object { Lg ('  ' + $_) } } else { Lg '  (no output = ok)' }
    Start-Sleep -Seconds 3
} else {
    Lg 'READ_ONLY: skipping vssadmin resize and powercfg /hibernate off'
}

$ssAfter = ShadowStorage
Lg '--- vssadmin list shadowstorage (AFTER) ---'; $ssAfter | ForEach-Object { Lg ('  ' + $_) }
$hibReg = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
$hibRegText = if ($null -eq $hibReg) { 'absent (= default on)' } else { "$hibReg (0 = off)" }
Lg ('AFTER: C free {0:N0} B; hiberfil.sys {1:N0} B (0 = removed); HibernateEnabled registry = {2}' -f (CFree), (HibBytes), $hibRegText)

# ---- receipt: local first (always works), share second (best-effort) ----
$receipt = [ordered]@{
    Phase = 'F1_VSS_LIMIT_AND_HIBERNATE_OFF'; Mode = $mode; MaxSize = $MaxSize
    Authority = 'Operator 10.09.2026 15:27: vss low conservative limit + hibernate off (agreed with Hari)'
    ExecutedBy = [Security.Principal.WindowsIdentity]::GetCurrent().Name; Elevated = $isAdmin
    Timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK')
    ShadowStorageBefore = @($ssBefore); ResizeOutput = @($rs); PowercfgOutput = @($pc); ShadowStorageAfter = @($ssAfter)
    Log = @($L)
}
$json = $receipt | ConvertTo-Json -Depth 4
$localDir = Join-Path $PSScriptRoot 'receipts'
$written = @()
foreach ($dir in @($localDir, (Join-Path $env:PUBLIC 'bulmar-admin'))) {
    try { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null; $f = Join-Path $dir ('F1_ADMIN_RECEIPT_{0}_{1}.json' -f $mode, $stamp); [System.IO.File]::WriteAllText($f, $json, (New-Object System.Text.UTF8Encoding($false))); $written += $f; break } catch { Lg ('receipt dir not writable: {0} ({1})' -f $dir, $_.Exception.Message) }
}
try { $share = '\\192.168.1.35\n8n-files\STORAGE_E14_20260910'; if (Test-Path -LiteralPath $share) { $f2 = Join-Path $share ('F1_ADMIN_RECEIPT_{0}_{1}.json' -f $mode, $stamp); [System.IO.File]::WriteAllText($f2, $json, (New-Object System.Text.UTF8Encoding($false))); $written += $f2 } else { Lg 'share not reachable from this token; local receipt only' } } catch { Lg ('share copy failed: {0}' -f $_.Exception.Message) }
foreach ($w in $written) { Write-Host ('RECEIPT {0} SHA256 {1}' -f $w, (Get-FileHash -LiteralPath $w -Algorithm SHA256).Hash) -ForegroundColor Green }
Write-Host ''
Write-Host ('DONE ({0}). Check without elevation after 24 h: Get-WinEvent -FilterHashtable @{{LogName=''System''; ProviderName=''volsnap''; StartTime=(Get-Date).AddHours(-24)}} -> expect no id 24/35.' -f $mode) -ForegroundColor Cyan
if (-not $ReadOnly) { Read-Host 'Press Enter to close' | Out-Null }
exit 0   # do not leak vssadmin's exit code; the receipt carries the truth
