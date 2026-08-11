# razuznavach.ps1 — заетост на всичките 18 получателя от драфта, на живо.
# Чете free/busy през Outlook. НИЩО не се изпраща, нищо не се резервира.
#
#   .\razuznavach.ps1                 днес
#   .\razuznavach.ps1 -At 13:30       кой е зает в 13:30 (разузнаването)
#   .\razuznavach.ps1 -Days 3         три дни напред
#   .\razuznavach.ps1 -Watch          обновява на 60 сек, Ctrl+C за изход

param(
    [int]$Days = 1,
    [string]$At = "",
    [switch]$Watch,
    [int]$RefreshSec = 60
)

# 18-те получателя на драфта, групирани
$GROUPS = [ordered]@{
    "ХОРА — До" = [ordered]@{
        "Емил Попов"          = "popov@bulmar.com"
        "Юри Стоянов"         = "ystoyanov@bulmar.com"
        "Хари Емирян"         = "hemiryan@bulmar.com"
        "Красимир Николов"    = "knikolov@bulmar.com"
        "Радослав Стефанов"   = "rstefanov@bulmar.com"
    }
    "ХОРА — Копие" = [ordered]@{
        "Ал. Бояджиев"        = "aboyadzhiev@bulmar.com"
        "Мануела Богоева"     = "mbogoeva@bulmar.com"
        "Нели Стефанова"      = "nstefanova@bulmar.com"
        "Васил Байнашев"      = "vbaynashev@bulmar.com"
        "Силвия Иванова"      = "sivanova@bulmar.com"
        "Георги Димитров"     = "gdimitrov@bulmar.com"
    }
    "ЗАЛИ" = [ordered]@{
        "Голяма Зала"         = "ucheben.center1@bulmar.com"
        "Малка Зала"          = "ucheben.center2@bulmar.com"
        "Приемна 1"           = "priemna1@bulmar.com"
        "Приемна 2"           = "priemna2@bulmar.com"
        "Приемна 3"           = "priemna3@bulmar.com"
        "Приемна 4"           = "priemna4@bulmar.com"
        "Приемна 5"           = "priemna5@bulmar.com"
    }
}

$FIRST_HOUR = 8
$LAST_HOUR  = 19
$SLOT_MIN   = 30
$SLOTS_PER_DAY = 48
$COL = 20               # ширина на колоната с имената

function Get-AllStatus {
    $ns = (New-Object -ComObject Outlook.Application).GetNamespace("MAPI")
    $today = (Get-Date).Date
    $out = @{}
    foreach ($g in $GROUPS.Keys) {
        foreach ($name in $GROUPS[$g].Keys) {
            $r = $ns.CreateRecipient($GROUPS[$g][$name])
            $null = $r.Resolve()
            if (-not $r.Resolved) { $out[$name] = $null; continue }
            try   { $out[$name] = $r.FreeBusy($today, $SLOT_MIN, $false) }
            catch { $out[$name] = $null }
        }
    }
    return $out
}

function Get-SlotChar {
    param($raw, [int]$absSlot)
    if (-not $raw -or $absSlot -lt 0 -or $absSlot -ge $raw.Length) { return $null }
    return $raw[$absSlot]
}

function Write-Slot {
    param([char]$c)
    switch ($c) {
        '0' { Write-Host ". " -NoNewline -ForegroundColor DarkGray }
        '1' { Write-Host "# " -NoNewline -ForegroundColor Yellow }
        '2' { Write-Host "# " -NoNewline -ForegroundColor Red }
        '3' { Write-Host "o " -NoNewline -ForegroundColor DarkYellow }
        default { Write-Host "? " -NoNewline -ForegroundColor DarkGray }
    }
}

function Show-Board {
    param($fb, [int]$dayOffset)

    $day = (Get-Date).Date.AddDays($dayOffset)
    $isToday = ($dayOffset -eq 0)
    $firstSlot = $FIRST_HOUR * 2
    $slotCount = ($LAST_HOUR - $FIRST_HOUR) * 2
    $dni = @("неделя","понеделник","вторник","сряда","четвъртък","петък","събота")

    $nowSlot = -1
    if ($isToday) {
        $n = Get-Date
        $nowSlot = ($n.Hour * 2 + [int]($n.Minute / 30)) - $firstSlot
    }

    Write-Host ""
    Write-Host ("  " + $dni[[int]$day.DayOfWeek] + ", " + $day.ToString("dd.MM.yyyy")) -NoNewline -ForegroundColor White
    if ($isToday) { Write-Host ("    " + (Get-Date).ToString("HH:mm")) -ForegroundColor DarkGray } else { Write-Host "" }

    $hdr = "  " + (" " * $COL)
    for ($h = $FIRST_HOUR; $h -lt $LAST_HOUR; $h++) { $hdr += ("{0:d2}  " -f $h) }
    Write-Host $hdr -ForegroundColor DarkGray

    if ($nowSlot -ge 0 -and $nowSlot -lt $slotCount) {
        Write-Host ("  " + (" " * $COL) + (" " * (2 * $nowSlot)) + "v") -ForegroundColor Yellow
    }

    foreach ($g in $GROUPS.Keys) {
        Write-Host ("  " + $g) -ForegroundColor DarkCyan
        foreach ($name in $GROUPS[$g].Keys) {
            $raw = $fb[$name]
            Write-Host ("   {0,-$($COL-1)}" -f $name) -NoNewline -ForegroundColor White
            if (-not $raw) { Write-Host "няма достъп до календара" -ForegroundColor DarkRed; continue }
            $start = $dayOffset * $SLOTS_PER_DAY + $firstSlot
            if ($raw.Length -lt $start + $slotCount) { Write-Host "(няма данни)" -ForegroundColor DarkRed; continue }
            $win = $raw.Substring($start, $slotCount)
            for ($i = 0; $i -lt $win.Length; $i++) { Write-Slot $win[$i] }
            Write-Host ""
        }
    }
    Write-Host ("  " + (" " * $COL) + ".  свободно     # заето     o  извън офиса") -ForegroundColor DarkGray
}

function Show-Snapshot {
    param($fb, [string]$timeText, [int]$dayOffset = 0)

    $parts = $timeText -split ":"
    $h = [int]$parts[0]; $m = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $abs = $dayOffset * $SLOTS_PER_DAY + $h * 2 + [int]($m / 30)
    $when = (Get-Date).Date.AddDays($dayOffset).AddHours($h).AddMinutes($m)

    Write-Host ""
    Write-Host ("  СРЕЗ в {0:HH:mm} на {0:dd.MM}" -f $when) -ForegroundColor White
    Write-Host ("  " + ("-" * 46)) -ForegroundColor DarkGray

    $busy = @(); $free = @(); $blind = @()
    foreach ($g in $GROUPS.Keys) {
        foreach ($name in $GROUPS[$g].Keys) {
            $c = Get-SlotChar $fb[$name] $abs
            if ($null -eq $c)      { $blind += $name }
            elseif ($c -eq '0')    { $free  += $name }
            else {
                # докога
                $raw = $fb[$name]; $end = $abs
                $dayEnd = ($dayOffset + 1) * $SLOTS_PER_DAY
                while ($end -lt $dayEnd -and $raw[$end] -ne '0') { $end++ }
                $endT = (Get-Date).Date.AddMinutes($end * $SLOT_MIN)
                $st = if ($c -eq '1') { "условно" } elseif ($c -eq '2') { "заето  " } else { "извън  " }
                $busy += ("{0,-20} {1}  до {2:HH:mm}" -f $name, $st, $endT)
            }
        }
    }

    Write-Host ("  ЗАЕТИ ({0}):" -f $busy.Count) -ForegroundColor Yellow
    if ($busy.Count -eq 0) { Write-Host "    никой" -ForegroundColor DarkGray }
    foreach ($b in $busy) { Write-Host ("    " + $b) -ForegroundColor Yellow }

    Write-Host ("  свободни ({0}): {1}" -f $free.Count, ($free -join ", ")) -ForegroundColor DarkGray
    if ($blind.Count) {
        Write-Host ("  БЕЗ ВИДИМОСТ ({0}): {1}" -f $blind.Count, ($blind -join ", ")) -ForegroundColor DarkRed
    }
}

do {
    if ($Watch) { Clear-Host }
    Write-Host ""
    Write-Host "  СТАТУС — 18 получателя" -ForegroundColor White
    $fb = Get-AllStatus
    for ($d = 0; $d -lt $Days; $d++) { Show-Board -fb $fb -dayOffset $d }
    if ($At) { Show-Snapshot -fb $fb -timeText $At }
    if ($Watch) {
        Write-Host ""
        Write-Host ("  обновяване на {0} сек — Ctrl+C за изход" -f $RefreshSec) -ForegroundColor DarkGray
        Start-Sleep -Seconds $RefreshSec
    }
} while ($Watch)
