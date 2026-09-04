# test_razuznavach_format_contract.ps1
# Договорен тест: форматът, с който razuznavach.ps1 ЧЕТЕ, трябва да съвпада с формата, който МАПВА.
#
# Outlook COM Recipient.FreeBusy(Start, MinPerChar, CompleteFormat):
#   CompleteFormat = $false → ПРОСТ формат: само '0' (свободно) и '1' (заето, какъвто и да е видът)
#   CompleteFormat = $true  → ПЪЛЕН формат: '0' свободно · '1' условно · '2' заето · '3' извън офиса
# Скриптът рисува и надписва '0/1/2/3' (пълен формат) ⇒ трябва да чете с $true.
# Наблюдавана вреда 04.09.2026: при $false Емил Попов излиза ЗАЕТ 08:00–19:00 („1111…"),
# докато пълният формат за същия ден дава „0000002222000022222200" (свободен 08–11 и 13–15).
#
#   pwsh -NoProfile -File scripts\tests\test_razuznavach_format_contract.ps1

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot "..\razuznavach.ps1"
$src = Get-Content $script -Raw
$fail = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Host ("  PASS  " + $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  " + $name + "  — " + $detail) -ForegroundColor Red; $script:fail++ }
}

# 1. Четенето трябва да иска ПЪЛНИЯ формат.
$m = [regex]::Match($src, '\.FreeBusy\(\s*\$today\s*,\s*\$SLOT_MIN\s*,\s*\$(true|false)\s*\)')
Check "FreeBusy се вика с CompleteFormat = `$true" ($m.Success -and $m.Groups[1].Value -eq 'true') `
      ("намерено: CompleteFormat = `$" + $(if ($m.Success) { $m.Groups[1].Value } else { "<няма съвпадение>" }))

# 2. Мапването покрива и четирите стойности на пълния формат.
foreach ($pair in @(@('0','свободно'), @('1','условно'), @('2','заето'), @('3','извън'))) {
    Check ("мапване за '" + $pair[0] + "' присъства") ($src -match ("'" + $pair[0] + "'")) "липсва клон за тази стойност"
}

# 3. Легендата обещава три различни състояния — те съществуват само в пълния формат.
Check "легендата описва свободно/заето/извън офиса" ($src -match 'свободно' -and $src -match 'заето' -and $src -match 'извън офиса') "легендата е сменена"

# 4. Легендата трябва да покрива ВСИЧКИТЕ пет състояния, не само трите приятни.
#    Наблюдавана вреда: легендата обещаваше по-малко, отколкото форматът връща.
Check "легендата включва условното състояние" ($src -match 'условно') "условното липсва от легендата"
Check "легендата включва липсата на данни" ($src -match 'няма данни') "неизвестното липсва от легендата"

# 5. Знакът, не само цветът, различава условното от заетото — цветът се губи при копиране.
$m1 = [regex]::Match($src, "'1'\s*\{\s*Write-Host\s+`"(.)\s")
$m2 = [regex]::Match($src, "'2'\s*\{\s*Write-Host\s+`"(.)\s")
Check "условно и заето се рисуват с РАЗЛИЧНИ знака" `
      ($m1.Success -and $m2.Success -and $m1.Groups[1].Value -ne $m2.Groups[1].Value) `
      ("'1'→'" + $m1.Groups[1].Value + "' срещу '2'→'" + $m2.Groups[1].Value + "'")

# 6. Границата на източника стои до таблото, не само в паметта.
Check "до таблото пише, че наличността е КАЛЕНДАРНА" ($src -match 'КАЛЕНДАРНА наличност') "границата на източника не е изписана"
Check "изрично: липсата на данни НЕ е свободен слот" ($src -match '\?\s+НЕ е свободен') "неизвестното може да мине за свободно"

Write-Host ""
if ($fail -eq 0) { Write-Host "  ДОГОВОРЪТ Е СПАЗЕН (0 провала)" -ForegroundColor Green; exit 0 }
else { Write-Host ("  ПРОВАЛИ: " + $fail) -ForegroundColor Red; exit 1 }
