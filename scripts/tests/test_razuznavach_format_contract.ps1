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

Write-Host ""
if ($fail -eq 0) { Write-Host "  ДОГОВОРЪТ Е СПАЗЕН (0 провала)" -ForegroundColor Green; exit 0 }
else { Write-Host ("  ПРОВАЛИ: " + $fail) -ForegroundColor Red; exit 1 }
