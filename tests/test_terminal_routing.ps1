param(
    [string]$Receipt,
    [string]$BaselineRef = '61eb12b2b009d97297d0ca5d53e35c19d60c727a'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
Set-StrictMode -Version 2.0
$repo = Split-Path $PSScriptRoot
$source = Join-Path $repo 'scripts\session_pane.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    Invoke-Expression $definition.Extent.Text
}

$script:checks = New-Object 'System.Collections.Generic.List[string]'
function Check([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:checks.Add($Name)
}
function Write-Audit { param($Author, $Kind, $Message) }
function Invoke-WithMutex { param($Name, [scriptblock]$Action) & $Action }
function Read-JsonHashtable { param($Path) return $script:state }
function Get-CimInstance { param($ClassName, $Filter) return $script:processes }
function Get-Process { param($Id, $ErrorAction) return [pscustomobject]@{Id=$Id;MainWindowHandle=0} }
function Start-Sleep { param($Milliseconds) }
function cmd.exe {
    $script:calls.Add(@{command='cmd';arguments=@($args)})
    $global:LASTEXITCODE = 0
}
function wtcli.exe {
    $script:calls.Add(@{command='wtcli';arguments=@($args);clsid=$env:WT_COM_CLSID})
    $global:LASTEXITCODE = $script:nativeExit
    if ($args -contains 'pane-status') { $script:paneStatus | ConvertTo-Json -Compress }
}

$StateRoot = 'C:\test-state-never-written'
$TerminalWindow = 'RManovQuad'
$stamp = [datetime]'2026-11-11T12:00:00'
$session = 'd1f91e47-ff79-4d82-aef4-c7ef002614dc'
$intelli = 'C:\Program Files\WindowsApps\Microsoft.IntelligentTerminal_0.3.3083.0_x64__8wekyb3d8bbwe\WindowsTerminal.exe'
$classic = 'C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_1.24.0.0_x64__8wekyb3d8bbwe\WindowsTerminal.exe'
$shell = 'C:\Program Files\PowerShell\7\pwsh.exe'

function Reset-Fixture([string]$Brand = 'intelligent') {
    $terminalPath = if ($Brand -eq 'intelligent') { $intelli } else { $classic }
    $script:processes = @(
        [pscustomobject]@{ProcessId=30;ParentProcessId=20;ExecutablePath=$shell;CreationDate=$stamp},
        [pscustomobject]@{ProcessId=20;ParentProcessId=10;ExecutablePath='C:\Windows\System32\cmd.exe';CreationDate=$stamp.AddSeconds(-1)},
        [pscustomobject]@{ProcessId=10;ParentProcessId=0;ExecutablePath=$terminalPath;CreationDate=$stamp.AddSeconds(-10)}
    )
    $script:state = [ordered]@{hostPid=30;hostProcessStartedAt=$stamp.ToString('o');hostWtSession=$session;hostExecutablePath=$shell;hostTerminalApp=$Brand}
    $script:calls = New-Object 'System.Collections.Generic.List[object]'
    $script:nativeExit = 0
    $script:paneStatus = @{session_id=$session;state='running';pid=20}
}

Reset-Fixture
Check 'Intelli identity uses package path' ((Get-AgentTerminalTarget 'codex').brand -eq 'intelligent')
Check 'Known shell ancestor captured for native pane ownership' (20 -in (Get-AgentTerminalTarget 'codex').lineage)
Reset-Fixture 'classic'
Check 'Live classic host remains classic' ((Get-AgentTerminalTarget 'claude').brand -eq 'classic')
$script:state.Remove('hostExecutablePath')
$script:state.Remove('hostTerminalApp')
Check 'Existing unstamped live classic host stays supported' ((Get-AgentTerminalTarget 'claude').brand -eq 'classic')

Reset-Fixture
$script:state.hostProcessStartedAt = $stamp.AddSeconds(-15).ToString('o')
Check 'Reused host PID rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:state.Remove('hostProcessStartedAt')
Check 'Missing process start identity rejected' (-not (Test-HostAlive 'codex'))
Reset-Fixture
$script:state.hostExecutablePath = 'C:\different\pwsh.exe'
Check 'Changed executable rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:processes[0].ExecutablePath = 'C:\Windows\System32\notepad.exe'
Check 'Unrelated PID executable rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:processes[1].CreationDate = $stamp.AddSeconds(1)
Check 'Reused ancestor PID rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:processes[1].ParentProcessId = 30
Check 'Cyclic ancestry rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:processes[2].ExecutablePath = 'C:\other\WindowsTerminal.exe'
Check 'Same basename without known package rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:state.hostTerminalApp = 'classic'
Check 'Recorded app mismatch rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:state.hostWtSession = 'not-a-pane'
Check 'Invalid pane identity rejected' ($null -eq (Get-AgentTerminalTarget 'codex'))
Reset-Fixture
$script:state.hostPid = 999
Check 'Stale state cannot authorize a creating focus command' ((Focus-AgentPane 'codex') -eq 20 -and $script:calls.Count -eq 0)
Check 'Stale layout cannot impersonate canonical host' (-not (Test-CanonicalWorkspaceExpected))

Reset-Fixture
$savedClsid = $env:WT_COM_CLSID
try {
    $env:WT_COM_CLSID = 'test-original'
    Check 'Intelli focus succeeds only after exact native pane status' ((Focus-AgentPane 'codex') -eq 0 -and $script:calls.Count -eq 2)
    Check 'Intelli uses only explicit target GUID' (($script:calls[0].arguments -join '|') -eq "--json|pane-status|-t|$session" -and ($script:calls[1].arguments -join '|') -eq "--json|focus-pane|-t|$session")
    Check 'Intelli COM selection is process local and restored' ($script:calls[0].clsid -eq '{A2E4F6B8-1C3D-4E5F-A6B7-C8D9E0F1A2B3}' -and $env:WT_COM_CLSID -eq 'test-original')
    Reset-Fixture
    $script:paneStatus.session_id = '96143d86-89c8-438c-a4ba-cff7c78fc600'
    Check 'Wrong returned pane does not focus' ((Focus-AgentPane 'codex') -eq 20 -and $script:calls.Count -eq 1)
    Reset-Fixture
    $script:paneStatus.pid = 31
    Check 'Pane outside known host lineage does not focus' ((Focus-AgentPane 'codex') -eq 20 -and $script:calls.Count -eq 1)
    Reset-Fixture
    $script:paneStatus.state = 'exited'
    Check 'Exited pane does not focus' ((Focus-AgentPane 'codex') -eq 20 -and $script:calls.Count -eq 1)
    Reset-Fixture
    $script:nativeExit = 1
    Check 'Native lookup error has no fallback launch' ((Focus-AgentPane 'codex') -eq 20 -and $script:calls.Count -eq 1 -and $env:WT_COM_CLSID -eq 'test-original')
    Reset-Fixture 'classic'
    Check 'Known classic host retains legacy focus command' ((Focus-AgentPane 'codex') -eq 0 -and $script:calls.Count -eq 1 -and $script:calls[0].command -eq 'cmd' -and ($script:calls[0].arguments -join '|') -eq '/d|/c|wt.exe|-w|RManovQuad|focus-tab|-t|0|\;|move-focus|first|\;|move-focus|right')
}
finally { $env:WT_COM_CLSID = $savedClsid }

foreach ($name in @('wt_quad.cmd','wt_trio.cmd','wt_duo.cmd','wt_dashboard.cmd','wt_grid6.cmd','razuznavach.cmd')) {
    $path = Join-Path $repo "scripts\$name"
    $candidate = [IO.File]::ReadAllText($path).Replace("`r`n", "`n")
    $baseline = (& git -C $repo show "${BaselineRef}:scripts/$name") -join "`n"
    Check "$name preserves all launch arguments and only replaces alias" ($candidate.Replace('wtai.exe', 'wt.exe').TrimEnd("`n") -eq $baseline.TrimEnd("`n") -and ([regex]::Matches($candidate,'wtai\.exe').Count -eq 1))
}

$result = [ordered]@{status='PASS';count=$script:checks.Count;checks=@($script:checks);paid_calls=0;live_agent_launches=0;process_priority=[string](Microsoft.PowerShell.Management\Get-Process -Id $PID).PriorityClass;at=(Get-Date).ToString('o')}
if ($Receipt) { $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Receipt -Encoding utf8 }
$result | ConvertTo-Json -Depth 4
