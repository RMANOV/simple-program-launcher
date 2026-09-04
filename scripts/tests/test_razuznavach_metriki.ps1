# test_razuznavach_metriki.ps1
# Единични тестове на ЧИСТИТЕ функции в razuznavach.ps1 — с изкуствени низове,
# без Outlook, без часовник, без екран.
#
# Файлът се дот-сорсва с RAZUZNAVACH_LIB_ONLY=1, за да не тръгне таблото.
#
#   pwsh -NoProfile -File scripts\tests\test_razuznavach_metriki.ps1
#
# Азбука: '0' свободно · '1' условно · '2' заето · '3' извън офиса · всичко друго = няма данни.
# ГРАНИЦА НА ИЗТОЧНИКА: това е КАЛЕНДАРНА наличност, не Teams presence.

$ErrorActionPreference = 'Stop'
$env:RAZUZNAVACH_LIB_ONLY = '1'
. (Join-Path $PSScriptRoot "..\razuznavach.ps1")

$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Host ("  PASS  " + $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  " + $name + "  — " + $detail) -ForegroundColor Red; $script:fail++ }
}

# 22-знаковият дневен прозорец започва на абсолютен слот 16 (08:00) в низ от 48 знака.
function W([string]$win) { ('9' * 16) + $win + ('9' * (48 - 16 - $win.Length)) }
$Z18 = '0' * 18

# ── Get-Prozorec ─────────────────────────────────────────────────────────────
$w = Get-Prozorec (W ('2' * 22))
Check "Get-Prozorec връща точно 22 знака от слот 16" ($w -eq ('2' * 22)) "върна: '$w'"
Check "Get-Prozorec връща `$null при къс низ" ($null -eq (Get-Prozorec ('0' * 20))) "не върна null"
Check "Get-Prozorec връща `$null при празен вход" ($null -eq (Get-Prozorec $null)) "не върна null"

# ── Get-SlotLabel / Get-Span ─────────────────────────────────────────────────
Check "Get-SlotLabel 0 = 08:00"  ((Get-SlotLabel 0)  -eq '08:00') (Get-SlotLabel 0)
Check "Get-SlotLabel 1 = 08:30"  ((Get-SlotLabel 1)  -eq '08:30') (Get-SlotLabel 1)
Check "Get-SlotLabel 22 = 19:00" ((Get-SlotLabel 22) -eq '19:00') (Get-SlotLabel 22)
Check "Get-Span 6,4 = 11:00-13:00" ((Get-Span 6 4) -eq '11:00-13:00') (Get-Span 6 4)

# ── Get-Runs ─────────────────────────────────────────────────────────────────
$r = @(Get-Runs '00110002' '0')
Check "Get-Runs намира 2 свободни поредици" ($r.Count -eq 2) "брой: $($r.Count)"
Check "Get-Runs първата е (0,2)" ($r[0].Start -eq 0 -and $r[0].Len -eq 2) "$($r[0].Start),$($r[0].Len)"
Check "Get-Runs втората е (4,3)" ($r[1].Start -eq 4 -and $r[1].Len -eq 3) "$($r[1].Start),$($r[1].Len)"
Check "Get-Runs върху празен низ дава 0" ((@(Get-Runs '' '0')).Count -eq 0) "не е празно"

# ── Прозорец за улавяне ──────────────────────────────────────────────────────
$long = Get-NaydalagPrazen ('00' + '2222' + '0000' + '22' + ('0' * 10))
Check "най-дългият свободен блок е 10 слота от 18" ($long.Start -eq 12 -and $long.Len -eq 10) "$($long.Start),$($long.Len)"
Check "при нула свободни слотове връща `$null" ($null -eq (Get-NaydalagPrazen ('2' * 22))) "върна стойност"

# ⚠ ЯДРОТО НА ПОПРАВКАТА: липсата на данни НЕ е свободно.
Check "низ само от неизвестни НЕ дава свободен блок" ($null -eq (Get-NaydalagPrazen ('x' * 22))) "неизвестното мина за свободно"
Check "неизвестното НЕ влиза в сечението" ((@(Get-Sechenie ('0' * 22) ('x' * 22))).Count -eq 0) "неизвестното мина за свободно"

# ── Общи свободни прозорци ───────────────────────────────────────────────────
$sh = @(Get-Sechenie ('0011' + $Z18) ('0101' + $Z18))
Check "сечението дава 2 общи прозореца" ($sh.Count -eq 2) "брой: $($sh.Count)"
$best = $sh | Sort-Object Len -Descending | Select-Object -First 1
Check "най-дългият общ прозорец е 18 слота" ($best.Len -eq 18) "дължина: $($best.Len)"
Check "условното НЕ е свободно в сечението" ((@(Get-Sechenie ('1' * 22) ('0' * 22))).Count -eq 0) "условното мина за свободно"

# ── Време до освобождаване ───────────────────────────────────────────────────
Check "зает в слот 0 → освобождава се в слот 4" ((Get-ZaetDo ('2211' + $Z18) 0) -eq 4) (Get-ZaetDo ('2211' + $Z18) 0)
Check "свободен сега → `$null" ($null -eq (Get-ZaetDo ('0' * 22) 3)) "върна стойност"
Check "индекс извън прозореца → `$null" ($null -eq (Get-ZaetDo ('2' * 22) 99)) "върна стойност"

# ── Раздробеност ─────────────────────────────────────────────────────────────
$fr = Get-Razdrobenost ('2211' + '22' + ('0' * 16))
Check "раздробеност: 2 заети блока" ($fr.Blocks -eq 2) "блокове: $($fr.Blocks)"
Check "раздробеност: 4 заети слота (условното не е заето)" ($fr.Slots -eq 4) "слотове: $($fr.Slots)"
Check "ден без заетост → 0 блока" ((Get-Razdrobenost ('0' * 22)).Blocks -eq 0) "не е 0"

# ── Флаг „извън офиса" ───────────────────────────────────────────────────────
Check "флагът се вдига при '3' в деня" (Test-Otsustvie ('00' + '3' + ('0' * 19))) "не се вдигна"
Check "флагът мълчи без '3'" (-not (Test-Otsustvie ('2211' + $Z18))) "вдигна се без причина"

# ── Вероятно заедно ──────────────────────────────────────────────────────────
$zaedno = @(Get-Zaedno ('2222' + $Z18) ('2200' + $Z18) 2)
Check "съвпадащ зает блок: 1 брой" ($zaedno.Count -eq 1) "брой: $($zaedno.Count)"
Check "съвпадащият блок е (0,2)" ($zaedno[0].Start -eq 0 -and $zaedno[0].Len -eq 2) "$($zaedno[0].Start),$($zaedno[0].Len)"
Check "блок под 1 час не се отчита" ((@(Get-Zaedno ('2000' + $Z18) ('2000' + $Z18) 2)).Count -eq 0) "отчете се къс блок"
# ⚠ условното и неизвестното КЪСАТ блока, не го запълват
$skusen = @(Get-Zaedno ('2212' + $Z18) ('2222' + $Z18) 2)
Check "условното къса съвпадащия блок" ($skusen.Count -eq 1 -and $skusen[0].Len -eq 2) "брой $($skusen.Count)"

# ── Lift ─────────────────────────────────────────────────────────────────────
# a: 4 заети от 22 · b: 2 заети от 22 · заедно 2 ⇒ lift = 2*22/(4*2) = 5,5
Check "lift = 5,5 при 4×2 заети и 2 съвпадащи" ((Get-Lift ('2222' + $Z18) ('2200' + $Z18)) -eq 5.5) (Get-Lift ('2222' + $Z18) ('2200' + $Z18))
Check "lift е НЕИЗМЕРИМ, когато единият е зает 0 слота" ($null -eq (Get-Lift ('0' * 22) ('2222' + $Z18))) "върна число"
Check "два еднакви заети низа дават lift над 1" ((Get-Lift ('2222' + $Z18) ('2222' + $Z18)) -gt 1) "не е над 1"

Write-Host ""
if ($fail -eq 0) { Write-Host "  ВСИЧКИ ТЕСТОВЕ МИНАХА (0 провала)" -ForegroundColor Green; exit 0 }
else { Write-Host ("  ПРОВАЛИ: " + $fail) -ForegroundColor Red; exit 1 }
