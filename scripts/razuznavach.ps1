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
        "г-н Попов"           = "popov@bulmar.com"
        "г-н Стоянов"         = "ystoyanov@bulmar.com"
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

$ME_EMAIL  = "rmanov@bulmar.com"   # моята заетост — само за сечението „общи свободни прозорци"
$MIN_ZAEDNO = 2                    # минимум слота (1 час) за ред в „ВЕРОЯТНО ЗАЕДНО"

# Ключовите фигури, за които се смятат метриките и се пише дневникът.
$KLYUCHOVI = [ordered]@{
    "г-н Попов"        = "popov@bulmar.com"
    "г-н Стоянов"      = "ystoyanov@bulmar.com"
    "Силвия Иванова"   = "sivanova@bulmar.com"
    "Красимир Николов" = "knikolov@bulmar.com"
}

function Get-AllStatus {
    $ns = (New-Object -ComObject Outlook.Application).GetNamespace("MAPI")
    $today = (Get-Date).Date
    $out = @{}
    foreach ($g in $GROUPS.Keys) {
        foreach ($name in $GROUPS[$g].Keys) {
            $r = $ns.CreateRecipient($GROUPS[$g][$name])
            $null = $r.Resolve()
            if (-not $r.Resolved) { $out[$name] = $null; continue }
            # ПЪЛЕН формат ($true): '0' свободно · '1' условно · '2' заето · '3' извън офиса —
            # точно това, което Write-Slot и Show-Snapshot рисуват и надписват.
            # Простият формат ($false) връща само '0'/'1' и на 04.09.2026 даваше ЕП зает 08:00–19:00,
            # докато пълният за същия ден: 0000002222000022222200 (свободен 08–11 и 13–15).
            try   { $out[$name] = $r.FreeBusy($today, $SLOT_MIN, $true) }
            catch { $out[$name] = $null }
        }
    }
    # моята собствена заетост — не се рисува на таблото, служи само за сечението
    $me = $ns.CreateRecipient($ME_EMAIL)
    $null = $me.Resolve()
    if ($me.Resolved) {
        try   { $out["__az"] = $me.FreeBusy($today, $SLOT_MIN, $true) }
        catch { $out["__az"] = $null }
    } else { $out["__az"] = $null }
    return $out
}

# --- дневник (04.09.2026): един ред на извадка за ключовите фигури, за корелации във времето.
# Локален файл, НЕ в OneDrive и НЕ в репото — данните за заетост не излизат навън.
$LOG_FILE = Join-Path $env:LOCALAPPDATA "bulmar-launcher\razuznavach_status.jsonl"
# Показваното име се смени на „г-н Фамилия" на 04.09.2026; ключът за свързване
# във времето е EMAIL-ът, не името — редовете отпреди смяната остават сравними.
$LOG_PEOPLE = $KLYUCHOVI
function Write-StatusLog {
    param($fb)
    try {
        $dir = Split-Path $LOG_FILE -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $now = Get-Date
        $slot = $now.Hour * 2 + [int]($now.Minute / 30)
        $ts = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        foreach ($name in $LOG_PEOPLE.Keys) {
            $c = Get-SlotChar $fb[$name] $slot
            $av = switch ("$c") { '0' { 'free' } '1' { 'tentative' } '2' { 'busy' } '3' { 'oof' } default { 'unknown' } }
            # Целият ДНЕВЕН прозорец, не само текущият слот: с един знак на извадка
            # „работен прозорец/дрейф" и знаменателят на „отклонение от базата" НИКОГА
            # не стават изчислими, колкото и дълго да се пълни дневникът. Полето само
            # СЪБИРА данните — метриките се строят по RAZUZNAVACH_METRIKI_SPEC.md, след прага.
            $row = [ordered]@{
                ts_utc = $ts; person = $name; email = $LOG_PEOPLE[$name]
                availability = $av; slot_char = "$c"; slot = $slot
                slot_window = (Get-Prozorec $fb[$name]); window_start_slot = ($FIRST_HOUR * 2)
                source = "outlook_freebusy_complete"   # календарна заетост, НЕ Teams presence
            }
            Add-Content -Path $LOG_FILE -Value ($row | ConvertTo-Json -Compress) -Encoding utf8
        }
    } catch { }   # дневникът никога не бламира таблото
}

function Get-SlotChar {
    param($raw, [int]$absSlot)
    if (-not $raw -or $absSlot -lt 0 -or $absSlot -ge $raw.Length) { return $null }
    return $raw[$absSlot]
}

function Write-Slot {
    param([char]$c)
    # Знакът, не само цветът, различава състоянията — цветът се губи при копиране.
    switch ($c) {
        '0' { Write-Host ". " -NoNewline -ForegroundColor DarkGray }
        '1' { Write-Host "~ " -NoNewline -ForegroundColor Yellow }
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
    Write-Host ("  " + (" " * $COL) + ".  свободно   ~  условно   #  заето   o  извън офиса   ?  няма данни") -ForegroundColor DarkGray
    Write-Host ("  " + (" " * $COL) + "?  НЕ е свободен — то е липса на данни и стои в отделна кофа.") -ForegroundColor DarkGray
    Write-Host ("  " + (" " * $COL) + "Това е КАЛЕНДАРНА наличност. Човек на среща без запис в календара излиза свободен.") -ForegroundColor DarkGray
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

# ═══ ЧИСТИ ФУНКЦИИ върху низа на заетостта ═══════════════════════════════════
# Не пипат Outlook, часовника или екрана — затова се тестват с изкуствени низове.
# Навсякъде: '0' свободно · '1' условно · '2' заето · '3' извън офиса · липса = няма данни.
# „Няма данни" НИКОГА не се брои за свободно и не влиза в знаменател на свободното.

function Get-Prozorec {
    # дневният прозорец 08:00–19:00; $null, ако низът не го покрива
    param([string]$raw, [int]$dayOffset = 0)
    if (-not $raw) { return $null }
    $start = $dayOffset * $SLOTS_PER_DAY + $FIRST_HOUR * 2
    $count = ($LAST_HOUR - $FIRST_HOUR) * 2
    if ($raw.Length -lt $start + $count) { return $null }
    return $raw.Substring($start, $count)
}

function Get-Runs {
    # непрекъснатите поредици, чиито знаци са в $chars
    param([string]$win, [string]$chars)
    # Връща ГОЛ масив — извикващият винаги го обгражда с @(...). Водеща запетая тук
    # би увила масива втори път и $r[0] щеше да е целият списък, не първата поредица.
    $runs = @()
    if (-not $win) { return $runs }
    $i = 0
    while ($i -lt $win.Length) {
        if ($chars.IndexOf($win[$i]) -ge 0) {
            $j = $i
            while ($j -lt $win.Length -and $chars.IndexOf($win[$j]) -ge 0) { $j++ }
            $runs += [pscustomobject]@{ Start = $i; Len = $j - $i }
            $i = $j
        } else { $i++ }
    }
    return $runs
}

function Get-SlotLabel {
    param([int]$i)
    '{0:d2}:{1:d2}' -f ($FIRST_HOUR + [int][math]::Floor($i * $SLOT_MIN / 60)), (($i * $SLOT_MIN) % 60)
}

function Get-Span { param([int]$start, [int]$len) (Get-SlotLabel $start) + "-" + (Get-SlotLabel ($start + $len)) }

function Get-NaydalagPrazen {
    param([string]$win)
    return (@(Get-Runs $win '0') | Sort-Object Len -Descending | Select-Object -First 1)
}

function Get-Sechenie {
    # общите СВОБОДНИ прозорци на двама; условно/заето/няма данни не е свободно
    param([string]$mine, [string]$theirs)
    if (-not $mine -or -not $theirs) { return @() }
    $n = [math]::Min($mine.Length, $theirs.Length)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $n; $i++) {
        [void]$sb.Append($(if ($mine[$i] -eq '0' -and $theirs[$i] -eq '0') { '0' } else { 'x' }))
    }
    return @(Get-Runs $sb.ToString() '0')
}

function Get-ZaetDo {
    # индексът на първия свободен слот след $i; $null, ако е свободен сега
    param([string]$win, [int]$i)
    if (-not $win -or $i -lt 0 -or $i -ge $win.Length) { return $null }
    if ($win[$i] -eq '0') { return $null }
    $j = $i
    while ($j -lt $win.Length -and $win[$j] -ne '0') { $j++ }
    return $j
}

function Get-Razdrobenost {
    # брой отделни ЗАЕТИ блока и общо заети слотове; условното не е заето
    param([string]$win)
    $r = @(Get-Runs $win '2')
    $slots = 0
    foreach ($b in $r) { $slots += $b.Len }
    return [pscustomobject]@{ Blocks = $r.Count; Slots = $slots }
}

function Test-Otsustvie { param([string]$win) return [bool]($win -and $win.IndexOf('3') -ge 0) }

function Get-Zaedno {
    # блокове, в които ДВАМАТА са заети; условно, свободно и липса на данни КЪСАТ блока
    param([string]$a, [string]$b, [int]$minLen = 2)
    if (-not $a -or -not $b) { return @() }
    $n = [math]::Min($a.Length, $b.Length)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $n; $i++) {
        [void]$sb.Append($(if ($a[$i] -eq '2' -and $b[$i] -eq '2') { '2' } else { 'x' }))
    }
    return @(@(Get-Runs $sb.ToString() '2') | Where-Object { $_.Len -ge $minLen })
}

function Get-Lift {
    # P(двамата заети) / (P(A зает) × P(B зает)). $null = НЕИЗМЕРИМ (някой е зает 0 слота).
    param([string]$a, [string]$b)
    if (-not $a -or -not $b) { return $null }
    $n = [math]::Min($a.Length, $b.Length)
    if ($n -eq 0) { return $null }
    $ca = 0; $cb = 0; $cab = 0
    for ($i = 0; $i -lt $n; $i++) {
        $x = ($a[$i] -eq '2'); $y = ($b[$i] -eq '2')
        if ($x) { $ca++ }
        if ($y) { $cb++ }
        if ($x -and $y) { $cab++ }
    }
    if ($ca -eq 0 -or $cb -eq 0) { return $null }
    return [math]::Round(($cab * $n) / ($ca * $cb), 2)
}

# ═══ ИЗХОД ═══════════════════════════════════════════════════════════════════

function Show-Zaedno {
    param($fb)
    $n = ($LAST_HOUR - $FIRST_HOUR) * 2
    Write-Host ""
    Write-Host "  ВЕРОЯТНО ЗАЕДНО" -ForegroundColor White
    Write-Host ("  " + ("-" * 46)) -ForegroundColor DarkGray
    $names = @($KLYUCHOVI.Keys)
    $redove = 0
    for ($i = 0; $i -lt $names.Count; $i++) {
        for ($j = $i + 1; $j -lt $names.Count; $j++) {
            $wa = Get-Prozorec $fb[$names[$i]]
            $wb = Get-Prozorec $fb[$names[$j]]
            if (-not $wa -or -not $wb) { continue }
            $blocks = @(Get-Zaedno $wa $wb $MIN_ZAEDNO)
            if ($blocks.Count -eq 0) { continue }
            $lift = Get-Lift $wa $wb
            $liftText = if ($null -eq $lift) { "lift НЕИЗМЕРИМ" } else { "lift {0}" -f $lift }
            foreach ($b in $blocks) {
                Write-Host ("    вероятно {0} има среща с {1}, {2}" -f $names[$i], $names[$j], (Get-Span $b.Start $b.Len)) -ForegroundColor Yellow
                Write-Host ("      блок {0} слота ({1} ч) · {2} · знаменател {3} слота" -f $b.Len, ($b.Len * $SLOT_MIN / 60), $liftText, $n) -ForegroundColor DarkGray
                $redove++
            }
        }
    }
    if ($redove -eq 0) { Write-Host "    няма съвпадащ зает блок от поне 1 час" -ForegroundColor DarkGray }
    Write-Host "    lift ≈ 1 = случайно съвпадение · lift значително над 1 = вероятна връзка." -ForegroundColor DarkGray
}

function Show-Metriki {
    param($fb)
    $n = ($LAST_HOUR - $FIRST_HOUR) * 2
    $mine = Get-Prozorec $fb["__az"]
    $now = Get-Date
    $nowSlot = ($now.Hour * 2 + [int]($now.Minute / 30)) - $FIRST_HOUR * 2

    Write-Host ""
    Write-Host ("  МЕТРИКИ — една извадка, днес · знаменател {0} слота ({1:d2}:00-{2:d2}:00)" -f $n, $FIRST_HOUR, $LAST_HOUR) -ForegroundColor White
    Write-Host ("  " + ("-" * 46)) -ForegroundColor DarkGray

    foreach ($name in $KLYUCHOVI.Keys) {
        $w = Get-Prozorec $fb[$name]
        Write-Host ("   {0}" -f $name) -ForegroundColor White
        if (-not $w) { Write-Host "      БЕЗ ВИДИМОСТ — няма данни за деня" -ForegroundColor DarkRed; continue }

        $free = Get-NaydalagPrazen $w
        if ($free) { Write-Host ("      прозорец за улавяне: {0} ({1} ч)" -f (Get-Span $free.Start $free.Len), ($free.Len * $SLOT_MIN / 60)) }
        else       { Write-Host "      прозорец за улавяне: НЯМА свободен слот днес" -ForegroundColor Yellow }

        if ($mine) {
            $sh = @(Get-Sechenie $mine $w)
            if ($sh.Count -gt 0) {
                $best = $sh | Sort-Object Len -Descending | Select-Object -First 1
                Write-Host ("      общи свободни с мен: {0} бр., най-дълъг {1} ({2} ч)" -f $sh.Count, (Get-Span $best.Start $best.Len), ($best.Len * $SLOT_MIN / 60))
            } else { Write-Host "      общи свободни с мен: НЯМА" -ForegroundColor Yellow }
        } else { Write-Host "      общи свободни с мен: НЕИЗМЕРИМО — моят календар не се чете" -ForegroundColor DarkRed }

        if ($nowSlot -lt 0 -or $nowSlot -ge $n) {
            Write-Host "      време до освобождаване: сега е извън прозореца на таблото"
        } else {
            $kraj = Get-ZaetDo $w $nowSlot
            if ($null -eq $kraj) { Write-Host "      време до освобождаване: свободен сега" }
            else { Write-Host ("      време до освобождаване: зает до {0}" -f (Get-SlotLabel $kraj)) -ForegroundColor Yellow }
        }

        $fr = Get-Razdrobenost $w
        if ($fr.Blocks -eq 0) { Write-Host "      раздробеност: 0 заети блока" }
        else {
            $duma = if ($fr.Blocks -eq 1) { "блок" } else { "блока" }
            Write-Host ("      раздробеност: {0} {1} / {2} слота заето (среден блок {3} ч)" -f $fr.Blocks, $duma, $fr.Slots, [math]::Round($fr.Slots / $fr.Blocks * $SLOT_MIN / 60, 1))
        }

        if (Test-Otsustvie $w) { Write-Host "      ФЛАГ ИЗВЪН ОФИСА — денят преди и след отсъствие е предсказуемо претоварен" -ForegroundColor DarkYellow }
    }
    Write-Host "    Всяко число е за НАЛИЧНОСТТА В КАЛЕНДАРА, не за човека." -ForegroundColor DarkGray
}

# Тестовете дот-сорсват файла само заради функциите — този флаг спира таблото.
if (-not $env:RAZUZNAVACH_LIB_ONLY) {

do {
    if ($Watch) { Clear-Host }
    Write-Host ""
    Write-Host "  СТАТУС — 18 получателя" -ForegroundColor White
    $fb = Get-AllStatus
    Write-StatusLog -fb $fb
    for ($d = 0; $d -lt $Days; $d++) { Show-Board -fb $fb -dayOffset $d }
    Show-Zaedno -fb $fb
    Show-Metriki -fb $fb
    if ($At) { Show-Snapshot -fb $fb -timeText $At }
    if ($Watch) {
        Write-Host ""
        Write-Host ("  обновяване на {0} сек — Ctrl+C за изход" -f $RefreshSec) -ForegroundColor DarkGray
        Start-Sleep -Seconds $RefreshSec
    }
} while ($Watch)

}
