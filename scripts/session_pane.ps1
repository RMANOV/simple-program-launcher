[CmdletBinding()]
param(
    [ValidateSet('Host', 'Request', 'MarkRestart', 'PrepareLayout', 'Inspect', 'SelfTest')]
    [string]$Mode = 'Inspect',

    [ValidateSet('claude', 'codex')]
    [string]$Agent = 'claude',

    [string]$SessionId,

    [string]$WorkingDirectory = $env:USERPROFILE,

    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'RManov\SessionPanes')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Agent = $Agent.ToLowerInvariant()
$StateFile = Join-Path $StateRoot "$Agent.json"
$RequestFile = Join-Path $StateRoot "$Agent.request.json"
$RestartRoot = Join-Path $StateRoot 'restart'
$LayoutFile = Join-Path $StateRoot 'layout.json'
$QuadScript = Join-Path $PSScriptRoot 'wt_quad.cmd'
$TerminalWindow = 'RManovQuad'

function Write-Audit {
    param(
        [string]$Author,
        [string]$Kind,
        [string]$Message = ''
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $suffix = if ($Message) { " $Message" } else { '' }
    Write-Host "[$stamp] [$Author] $Kind$suffix"
}

function Ensure-StateDirectories {
    [System.IO.Directory]::CreateDirectory($StateRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($RestartRoot) | Out-Null
}

function Test-ValidSessionId {
    param([string]$Value)

    $parsed = [guid]::Empty
    return (-not [string]::IsNullOrWhiteSpace($Value)) -and
        [guid]::TryParse($Value.Trim(), [ref]$parsed)
}

function Read-JsonHashtable {
    param([string]$Path)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    try {
        $object = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        foreach ($property in $object.PSObject.Properties) {
            $result[$property.Name] = $property.Value
        }
    }
    catch {
        Write-Audit 'SESSION-PANE' 'WARN' "Невалиден state файл: $Path"
    }
    return $result
}

function Write-JsonAtomic {
    param(
        [string]$Path,
        [object]$Value
    )

    Ensure-StateDirectories
    $temporary = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
    $json = $Value | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, $Utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Invoke-WithMutex {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [int]$TimeoutMilliseconds = 5000
    )

    $mutex = New-Object System.Threading.Mutex($false, "Local\RManov_$Name")
    $held = $false
    try {
        try {
            $held = $mutex.WaitOne($TimeoutMilliseconds)
        }
        catch [System.Threading.AbandonedMutexException] {
            $held = $true
        }
        if (-not $held) {
            throw "Timeout waiting for mutex $Name"
        }
        & $Action
    }
    finally {
        if ($held) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Get-AgentState {
    Invoke-WithMutex "SessionPaneState_$Agent" {
        Read-JsonHashtable $StateFile
    }
}

function Update-AgentState {
    param([hashtable]$Patch)

    Invoke-WithMutex "SessionPaneState_$Agent" {
        $state = Read-JsonHashtable $StateFile
        foreach ($key in $Patch.Keys) {
            $state[$key] = $Patch[$key]
        }
        $state['agent'] = $Agent
        $state['version'] = 2
        $state['updatedAt'] = (Get-Date).ToString('o')
        Write-JsonAtomic $StateFile $state
    }
}

function Test-PidAlive {
    param([object]$ProcessId)

    if (-not $ProcessId) {
        return $false
    }
    try {
        Get-Process -Id ([int]$ProcessId) -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-WindowsTerminalAlive {
    try {
        Get-Process -Name 'WindowsTerminal' -ErrorAction Stop | Select-Object -First 1 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-HostAlive {
    param([string]$ForAgent)

    $path = Join-Path $StateRoot "$ForAgent.json"
    $state = Invoke-WithMutex "SessionPaneState_$ForAgent" {
        Read-JsonHashtable $path
    }
    if (-not $state.Contains('hostPid') -or -not (Test-PidAlive $state['hostPid'])) {
        return $false
    }
    if ($state.Contains('hostProcessStartedAt') -and $state['hostProcessStartedAt']) {
        try {
            $process = Get-Process -Id ([int]$state['hostPid']) -ErrorAction Stop
            $expected = [datetime]::Parse([string]$state['hostProcessStartedAt'])
            if ([math]::Abs(($process.StartTime - $expected).TotalSeconds) -gt 2) {
                return $false
            }
        }
        catch {
            return $false
        }
    }
    return $true
}

function Clear-HostStateIfOwned {
    Invoke-WithMutex "SessionPaneState_$Agent" {
        $state = Read-JsonHashtable $StateFile
        if ($state.Contains('hostPid') -and ([int]$state['hostPid'] -eq $PID)) {
            $state['status'] = 'stopped'
            $state['hostPid'] = $null
            $state['stoppedAt'] = (Get-Date).ToString('o')
            $state['updatedAt'] = (Get-Date).ToString('o')
            Write-JsonAtomic $StateFile $state
        }
    }
}

function Focus-AgentPane {
    param([string]$ForAgent)

    # The quad layout is deterministic: Claude is the leftmost pane and Codex
    # is immediately to its right.  WT has no supported "send command to an
    # existing pane" CLI; the resident Host process is what makes reuse safe.
    $arguments = @('-w', $TerminalWindow, 'focus-tab', '-t', '0', ';', 'move-focus', 'first')
    if ($ForAgent -eq 'codex') {
        $arguments += @(';', 'move-focus', 'right')
    }
    try {
        & wt.exe @arguments | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Audit 'SESSION-PANE' 'WARN' "Windows Terminal focus exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Audit 'SESSION-PANE' 'WARN' 'Windows Terminal не можа да фокусира панела.'
    }
}

function Focus-TerminalWindow {
    try {
        $terminal = Get-Process -Name 'WindowsTerminal' -ErrorAction Stop |
            Where-Object { $_.MainWindowHandle -ne 0 } |
            Sort-Object StartTime -Descending |
            Select-Object -First 1
        if ($terminal) {
            $shell = New-Object -ComObject WScript.Shell
            $shell.AppActivate($terminal.Id) | Out-Null
        }
    }
    catch {
        # Focus is best-effort; the idempotence guard must still remain a no-op.
    }
}

function Get-RunningExplicitSessionId {
    param([string]$ForAgent)

    $uuid = '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    try {
        $processes = Get-CimInstance Win32_Process | Sort-Object CreationDate -Descending
        foreach ($process in $processes) {
            $commandLine = [string]$process.CommandLine
            if (-not $commandLine) {
                continue
            }
            $codexPattern = '(?i)codex(?:\.exe|\.cmd|\.js)?\S*\s+resume\s+' + $uuid
            if ($ForAgent -eq 'codex' -and $commandLine -match $codexPattern) {
                [void]$ids.Add($Matches[1].ToLowerInvariant())
            }
            $claudePattern = '(?i)claude(?:\.exe|\.cmd|\.js)?\S*\s+(?:--resume|-r)\s+' + $uuid
            if ($ForAgent -eq 'claude' -and $commandLine -match $claudePattern) {
                [void]$ids.Add($Matches[1].ToLowerInvariant())
            }
        }
    }
    catch {
        Write-Audit 'SESSION-PANE' 'WARN' 'Неуспешна проверка на активните процеси.'
    }
    if ($ids.Count -eq 1) {
        return @($ids)[0]
    }
    return $null
}

function Test-AnyInteractiveAgentProcess {
    param([string]$ForAgent)

    try {
        if ($ForAgent -eq 'claude') {
            return $null -ne (Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Select-Object -First 1)
        }

        $processes = Get-CimInstance Win32_Process | Where-Object {
            $line = [string]$_.CommandLine
            $line -and
            $line -match '(?i)(?:@openai[\\/]codex|codex\.js|codex\.exe)' -and
            $line -notmatch '(?i)\bapp-server\b'
        }
        return $null -ne ($processes | Select-Object -First 1)
    }
    catch {
        return $false
    }
}

function Test-CodexWriterLocked {
    param([string]$Id)

    if (-not (Test-ValidSessionId $Id)) {
        return $false
    }
    $lockPath = Join-Path (Join-Path $env:USERPROFILE '.codex\thread-writer-locks') "$Id.lock"
    if (-not (Test-Path -LiteralPath $lockPath)) {
        return $false
    }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        return $false
    }
    catch [System.IO.IOException] {
        return $true
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Test-SessionAlreadyActive {
    param(
        [string]$ForAgent,
        [string]$Id
    )

    if ($ForAgent -eq 'codex') {
        return Test-CodexWriterLocked $Id
    }

    # Claude has no equivalent public writer-lock file. A bare `claude` or
    # `--continue` process does not expose its UUID in the command line, so a
    # conservative no-op is safer than creating a duplicate writer.
    return Test-AnyInteractiveAgentProcess 'claude'
}

function Write-AgentRequest {
    param([string]$RequestedSessionId)

    $payload = [ordered]@{
        agent = $Agent
        sessionId = $RequestedSessionId
        cwd = $WorkingDirectory
        requestedAt = (Get-Date).ToString('o')
        requestedBy = $env:USERNAME
    }
    Write-JsonAtomic $RequestFile $payload
}

function Get-RestartMarkerPath {
    $paneId = if ($env:WT_SESSION) { $env:WT_SESSION } else { "pid-$PID" }
    $safePaneId = $paneId -replace '[^0-9A-Za-z_-]', '_'
    return Join-Path $RestartRoot "$Agent.$safePaneId.json"
}

function Get-LatestRestartMarker {
    $markers = Get-ChildItem -LiteralPath $RestartRoot -Filter "$Agent.*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    foreach ($marker in $markers) {
        $value = Read-JsonHashtable $marker.FullName
        if ($value.Contains('sessionId') -and (Test-ValidSessionId ([string]$value['sessionId']))) {
            return [pscustomobject]@{
                Path = $marker.FullName
                SessionId = ([string]$value['sessionId']).Trim().ToLowerInvariant()
            }
        }
    }
    return $null
}

function Claim-LatestRestartMarker {
    Invoke-WithMutex "SessionPaneRestart_$Agent" {
        $marker = Get-LatestRestartMarker
        if (-not $marker) {
            return $null
        }
        $inFlight = "$($marker.Path).inflight.$PID.$([guid]::NewGuid().ToString('N'))"
        Move-Item -LiteralPath $marker.Path -Destination $inFlight -Force
        return [pscustomobject]@{
            OriginalPath = $marker.Path
            InFlightPath = $inFlight
            SessionId = $marker.SessionId
        }
    }
}

function Restore-ClaimedRestartMarker {
    param(
        [string]$InFlightPath,
        [string]$OriginalPath
    )

    Invoke-WithMutex "SessionPaneRestart_$Agent" {
        if (-not (Test-Path -LiteralPath $InFlightPath)) {
            return
        }
        if (Test-Path -LiteralPath $OriginalPath) {
            # A newer /restart marker already owns the canonical path.
            Remove-Item -LiteralPath $InFlightPath -Force -ErrorAction SilentlyContinue
        }
        else {
            Move-Item -LiteralPath $InFlightPath -Destination $OriginalPath -Force
        }
    }
}

function Get-LatestCodexSessionId {
    $root = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $root)) {
        return $null
    }

    $files = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 80
    foreach ($file in $files) {
        try {
            $line = Get-Content -LiteralPath $file.FullName -TotalCount 1
            $event = $line | ConvertFrom-Json
            $id = [string]$event.payload.id
            $cwd = [string]$event.payload.cwd
            if ((Test-ValidSessionId $id) -and
                $cwd -and
                ([System.IO.Path]::GetFullPath($cwd).TrimEnd('\') -ieq
                    [System.IO.Path]::GetFullPath($WorkingDirectory).TrimEnd('\'))) {
                return $id.ToLowerInvariant()
            }
        }
        catch {
            continue
        }
    }
    return $null
}

function Get-LatestClaudeSessionId {
    $root = Join-Path $env:USERPROFILE '.claude\projects'
    if (-not (Test-Path -LiteralPath $root)) {
        return $null
    }

    $projectName = $WorkingDirectory -replace '[^A-Za-z0-9]', '-'
    $projectRoot = Join-Path $root $projectName
    if (-not (Test-Path -LiteralPath $projectRoot)) {
        return $null
    }
    $files = Get-ChildItem -LiteralPath $projectRoot -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Where-Object { Test-ValidSessionId $_.BaseName } |
        Sort-Object LastWriteTime -Descending
    $candidate = $files | Select-Object -First 1
    if ($candidate) {
        return $candidate.BaseName.ToLowerInvariant()
    }
    return $null
}

function Invoke-AgentCli {
    param(
        [string]$Id,
        [bool]$AllowLastFallback
    )

    if ($Id -and (Test-SessionAlreadyActive $Agent $Id)) {
        Write-Audit ($Agent.ToUpperInvariant()) 'ACTIVE' "Session $Id вече има writer; reuse/focus, без втори launch."
        Update-AgentState @{
            status = 'external-active'
            sessionId = $Id
            lastError = 'active-writer'
        }
        return 73
    }

    Update-AgentState @{
        status = 'running'
        sessionId = $Id
        hostPid = $PID
        hostWtSession = $env:WT_SESSION
        cwd = $WorkingDirectory
        startedAt = (Get-Date).ToString('o')
        lastError = $null
    }

    Push-Location -LiteralPath $WorkingDirectory
    try {
        if ($Agent -eq 'claude') {
            $prePatch = Join-Path $env:USERPROFILE '.claude\hooks\pre_launch_patch.py'
            if (Test-Path -LiteralPath $prePatch) {
                & python $prePatch 2>$null
            }
            $executable = (Get-Command 'claude.exe' -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
            if ($Id) {
                Write-Audit 'SESSION-PANE' 'RESULT' "Claude resume $Id"
                & $executable --resume $Id
            }
            elseif ($AllowLastFallback) {
                Write-Audit 'SESSION-PANE' 'RESULT' 'Claude continue (първо свързване; UUID ще бъде запомнен).'
                & $executable --continue
            }
            else {
                throw 'Липсва Claude session ID.'
            }
        }
        else {
            $executable = (Get-Command 'codex.cmd' -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
            if ($Id) {
                Write-Audit 'SESSION-PANE' 'RESULT' "Codex resume $Id"
                & $executable resume $Id
            }
            elseif ($AllowLastFallback) {
                Write-Audit 'SESSION-PANE' 'RESULT' 'Codex resume --last (първо свързване; UUID ще бъде запомнен).'
                & $executable resume --last
            }
            else {
                throw 'Липсва Codex session ID.'
            }
        }

        if ($null -eq $LASTEXITCODE) {
            return 0
        }
        return [int]$LASTEXITCODE
    }
    catch {
        Write-Audit 'SESSION-PANE' 'ERROR' $_.Exception.Message
        return 1
    }
    finally {
        Pop-Location
    }
}

function Invoke-AgentWithRestartLoop {
    param([string]$InitialSessionId)

    $id = $InitialSessionId
    $allowFallback = -not (Test-ValidSessionId $id)
    $markerInFlight = $null
    $markerOriginal = $null

    # A marker may have been created in a legacy/non-host pane before this host
    # existed. Claim it before the first resume so it cannot trigger a second
    # resume after that session later exits normally.
    $initialMarker = Claim-LatestRestartMarker
    if ($initialMarker) {
        $markerOriginal = $initialMarker.OriginalPath
        $markerInFlight = $initialMarker.InFlightPath
        $id = $initialMarker.SessionId
        $allowFallback = $false
        Update-AgentState @{ sessionId = $id; status = 'starting' }
    }

    while ($true) {
        $exitCode = Invoke-AgentCli $id $allowFallback

        if ($markerInFlight) {
            if ($exitCode -eq 0) {
                Remove-Item -LiteralPath $markerInFlight -Force -ErrorAction SilentlyContinue
            }
            else {
                Restore-ClaimedRestartMarker $markerInFlight $markerOriginal
                Update-AgentState @{
                    status = 'resume-failed'
                    sessionId = $id
                    lastExitCode = $exitCode
                    lastError = 'resume-failed-state-retained'
                }
                Write-Audit 'SESSION-PANE' 'STATE-KEPT' "Resume не успя; UUID $id остава записан."
                break
            }
            $markerInFlight = $null
            $markerOriginal = $null
        }

        if ($exitCode -eq 0 -and -not (Test-ValidSessionId $id)) {
            $id = if ($Agent -eq 'claude') {
                Get-LatestClaudeSessionId
            }
            else {
                Get-LatestCodexSessionId
            }
            if (Test-ValidSessionId $id) {
                Update-AgentState @{ sessionId = $id; capturedAt = (Get-Date).ToString('o') }
                Write-Audit 'SESSION-PANE' 'STATE' "Запомнен UUID: $id"
            }
        }

        $nextMarker = Claim-LatestRestartMarker
        if (-not $nextMarker) {
            $finalStatus = if ($exitCode -eq 73) { 'external-active' } else { 'idle' }
            Update-AgentState @{
                status = $finalStatus
                sessionId = $id
                lastExitCode = $exitCode
                endedAt = (Get-Date).ToString('o')
            }
            break
        }

        $markerOriginal = $nextMarker.OriginalPath
        $markerInFlight = $nextMarker.InFlightPath
        $id = $nextMarker.SessionId
        $allowFallback = $false
        Update-AgentState @{ sessionId = $id; status = 'restarting' }
        Write-Audit 'SESSION-PANE' 'RESTART' "Същата $Agent сесия $id се връща в този панел."
    }
}

function Run-Host {
    $hostMutex = New-Object System.Threading.Mutex($false, "Local\RManov_SessionPaneHost_$Agent")
    $hostHeld = $false
    try {
        try {
            $hostHeld = $hostMutex.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            $hostHeld = $true
        }
        if (-not $hostHeld) {
            Write-Audit 'SESSION-PANE' 'NOOP' "Вече има активен $Agent host."
            # The pane supervisor treats this as a clean "not my slot" exit.
            # It must not keep spawning duplicate hosts in another pane.
            exit 88
        }

        Ensure-StateDirectories
        $hostProcessStartedAt = (Get-Process -Id $PID).StartTime.ToString('o')
        $initialStatus = if (Test-Path -LiteralPath $RequestFile) { 'queued' } else { 'idle' }
        Update-AgentState @{
            hostPid = $PID
            hostWtSession = $env:WT_SESSION
            status = $initialStatus
            cwd = $WorkingDirectory
            hostStartedAt = (Get-Date).ToString('o')
            hostProcessStartedAt = $hostProcessStartedAt
        }
        $host.UI.RawUI.WindowTitle = "RManov $($Agent.ToUpperInvariant()) pane"
        Write-Audit ($Agent.ToUpperInvariant()) 'READY' 'Този панел е постоянният launcher slot.'

        while ($true) {
            $inFlight = $null
            try {
                $inFlight = Invoke-WithMutex "SessionPaneRequest_$Agent" {
                    if (-not (Test-Path -LiteralPath $RequestFile)) {
                        return $null
                    }
                    $claimed = "$RequestFile.inflight.$PID"
                    Move-Item -LiteralPath $RequestFile -Destination $claimed -Force
                    Update-AgentState @{ status = 'starting'; hostPid = $PID }
                    return $claimed
                }
            }
            catch {
                Write-Audit 'SESSION-PANE' 'WARN' "Request claim: $($_.Exception.Message)"
            }
            if ($inFlight) {
                try {
                    $request = Read-JsonHashtable $inFlight
                    $state = Get-AgentState
                    $id = $null
                    if ($request.Contains('sessionId') -and (Test-ValidSessionId ([string]$request['sessionId']))) {
                        $id = ([string]$request['sessionId']).Trim().ToLowerInvariant()
                    }
                    elseif ($state.Contains('sessionId') -and (Test-ValidSessionId ([string]$state['sessionId'])) ) {
                        $id = ([string]$state['sessionId']).Trim().ToLowerInvariant()
                    }

                    Remove-Item -LiteralPath $inFlight -Force -ErrorAction SilentlyContinue
                    Invoke-AgentWithRestartLoop $id
                    Write-Audit ($Agent.ToUpperInvariant()) 'READY' 'Сесията е запомнена; launcher-ът може да я върне тук.'
                }
                catch {
                    Write-Audit 'SESSION-PANE' 'ERROR' $_.Exception.Message
                    if (Test-Path -LiteralPath $inFlight) {
                        Invoke-WithMutex "SessionPaneRequest_$Agent" {
                            if (-not (Test-Path -LiteralPath $RequestFile)) {
                                Move-Item -LiteralPath $inFlight -Destination $RequestFile -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                    Update-AgentState @{ status = 'host-error'; lastError = $_.Exception.Message }
                }
            }
            Start-Sleep -Milliseconds 250
        }
    }
    finally {
        if ($hostHeld) {
            Clear-HostStateIfOwned
            $hostMutex.ReleaseMutex()
        }
        $hostMutex.Dispose()
    }
}

function Run-Request {
    Invoke-WithMutex "SessionPaneRequest_$Agent" {
        Ensure-StateDirectories
        $state = Get-AgentState
        $hostAlive = Test-HostAlive $Agent
        $id = $null
        if ($state.Contains('sessionId') -and (Test-ValidSessionId ([string]$state['sessionId'])) ) {
            $id = ([string]$state['sessionId']).Trim().ToLowerInvariant()
        }
        if (-not $id) {
            $id = Get-RunningExplicitSessionId $Agent
            if ($id) {
                Update-AgentState @{ sessionId = $id; adoptedAt = (Get-Date).ToString('o') }
            }
        }

        if ($hostAlive) {
            Focus-AgentPane $Agent
            $status = if ($state.Contains('status')) { [string]$state['status'] } else { '' }
            if ($status -eq 'external-active' -and $id -and (Test-SessionAlreadyActive $Agent $id)) {
                return
            }
            $retryable = @('', 'idle', 'stopped', 'resume-failed', 'host-error', 'external-active')
            if ($status -notin $retryable) {
                return
            }
            Write-AgentRequest $id
            Update-AgentState @{ status = 'queued'; sessionId = $id }
            return
        }

        if ($id -and (Test-SessionAlreadyActive $Agent $id)) {
            Update-AgentState @{
                status = 'external-active'
                sessionId = $id
                lastError = $null
            }
            # The launcher popup closes back to the pane that already owns the
            # writer.  Do not create another tab and do not kill that writer.
            Focus-TerminalWindow
            return
        }

        if (-not $id -and (Test-AnyInteractiveAgentProcess $Agent)) {
            Update-AgentState @{
                status = 'external-active-unidentified'
                lastError = 'run-/restart-once-to-capture-id'
            }
            Focus-TerminalWindow
            return
        }

        $status = if ($state.Contains('status')) { [string]$state['status'] } else { '' }
        $busy = @('queued', 'starting', 'restarting', 'restart-marked')
        if ($status -in $busy) {
            # A second click is deliberately idempotent even while the canonical
            # window is being opened.  It never creates another tab.
            Focus-TerminalWindow
            return
        }

        # Resume is a consumer of the already-created canonical workspace.  The
        # launcher button must never bootstrap WT: doing so creates a second
        # window beside the user's four-pane tab.  Keep the exact UUID/request
        # pending; the Host consumes it after the user opens WT Quad (4).
        Write-AgentRequest $id
        Update-AgentState @{
            status = 'queued'
            sessionId = $id
            lastError = 'canonical-pane-not-ready-open-WT-Quad-4'
        }
        Write-Audit 'SESSION-PANE' 'QUEUED' 'Няма здрав canonical pane; заявката остава записана без нов Terminal tab.'
        Focus-TerminalWindow
    }
}

function Run-MarkRestart {
    if (-not $SessionId) {
        $SessionId = if ($Agent -eq 'claude') {
            $env:CLAUDE_CODE_SESSION_ID
        }
        else {
            $env:CODEX_THREAD_ID
        }
    }
    if (-not (Test-ValidSessionId $SessionId)) {
        throw "Не е наличен валиден $Agent session UUID; state не е променен."
    }
    $id = $SessionId.Trim().ToLowerInvariant()
    Ensure-StateDirectories

    $marker = [ordered]@{
        agent = $Agent
        sessionId = $id
        wtSession = $env:WT_SESSION
        author = $env:USERNAME
        markedAt = (Get-Date).ToString('o')
    }
    Invoke-WithMutex "SessionPaneRestart_$Agent" {
        Write-JsonAtomic (Get-RestartMarkerPath) $marker
    }
    Update-AgentState @{
        sessionId = $id
        sourceWtSession = $env:WT_SESSION
        status = 'restart-marked'
        restartMarkedAt = (Get-Date).ToString('o')
        lastError = $null
    }

    Write-Audit ($Agent.ToUpperInvariant()) 'RESTART-MARKED' "Session ID $id е запомнен. Излез от TUI; същата сесия ще се върне в същия/назначения панел."
}

function Run-PrepareLayout {
    $exitCode = Invoke-WithMutex 'SessionPaneLayout' {
        $claudeAlive = Test-HostAlive 'claude'
        $codexAlive = Test-HostAlive 'codex'
        if ($claudeAlive -and $codexAlive) {
            Focus-AgentPane 'claude'
            return 0
        }

        if ($claudeAlive -or $codexAlive) {
            # Never append a tab to repair a half-live topology.  The surviving
            # host owns a real pane; only a full canonical-window rebuild is
            # safe after the active sessions have been left intact.
            Write-Audit 'SESSION-PANE' 'LAYOUT-DAMAGED' 'Само един host е жив; нов tab няма да бъде създаден.'
            return 20
        }

        $layout = Read-JsonHashtable $LayoutFile
        $terminalAlive = Test-WindowsTerminalAlive
        if ($terminalAlive) {
            # An existing WT process with no healthy hosts is either the user's
            # old four-pane layout or a damaged canonical window.  Public wt.exe
            # has no reliable pane injection/rename operation, so fail closed.
            Write-Audit 'SESSION-PANE' 'CANONICAL-NOT-READY' 'Затвори стария/повреден RManovQuad и стартирай WT Quad (4) за пълен rebuild.'
            return 20
        }

        if ($layout.Contains('startedAt')) {
            try {
                $started = [datetime]::Parse([string]$layout['startedAt'])
                # No WindowsTerminal process remains, therefore an old layout
                # marker is stale and may be replaced by a full bootstrap.
                if (((Get-Date) - $started).TotalSeconds -lt 15) { return 10 }
            }
            catch {
                # Replace invalid/stale layout state below.
            }
        }
        Write-JsonAtomic $LayoutFile ([ordered]@{
            startedAt = (Get-Date).ToString('o')
            pid = $PID
        })
        return 10
    }
    exit ([int]$exitCode)
}

function Run-SelfTest {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "RManovSessionPaneSelfTest-$PID"
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTest.StartsWith($resolvedTemp + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Self-test path escaped the temporary directory.'
    }

    try {
        [System.IO.Directory]::CreateDirectory($testRoot) | Out-Null
        $path = Join-Path $testRoot 'state.json'
        $id = [guid]::NewGuid().ToString()
        Write-JsonAtomic $path ([ordered]@{ agent = 'codex'; sessionId = $id; status = 'idle' })
        $roundTrip = Read-JsonHashtable $path
        if (-not $roundTrip.Contains('sessionId') -or $roundTrip['sessionId'] -ne $id) {
            throw 'Atomic JSON round-trip failed.'
        }
        if (-not (Test-ValidSessionId $id)) {
            throw 'UUID validation failed.'
        }
        Write-Audit 'SESSION-PANE' 'SELFTEST-OK' 'atomic state + UUID validation'
    }
    finally {
        if (Test-Path -LiteralPath $resolvedTest) {
            Remove-Item -LiteralPath $resolvedTest -Recurse -Force
        }
    }
}

switch ($Mode) {
    'Host'          { Run-Host; break }
    'Request'       { Run-Request; break }
    'MarkRestart'   { Run-MarkRestart; break }
    'PrepareLayout' { Run-PrepareLayout; break }
    'Inspect'       {
        Ensure-StateDirectories
        [pscustomobject](Get-AgentState) | Format-List
        break
    }
    'SelfTest'      { Run-SelfTest; break }
}
