# Проверки без Windows и без сети: синтаксис скриптов, config.example.psd1 и логика функций окна.
# Запуск: pwsh -File tests/check.ps1 (PowerShell 7 на Linux или Windows) или в Windows PowerShell 5.1.
# Код выхода = число проваленных проверок
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script:Fail = 0
function Check([string]$Name, $Cond) {
    if ($Cond) { Write-Host ('PASS {0}' -f $Name) }
    else { Write-Host ('FAIL {0}' -f $Name) -ForegroundColor Red; $script:Fail++ }
}
function Throws([scriptblock]$Block, [string]$Like) {
    try { & $Block | Out-Null; return $false } catch { return ($_.Exception.Message -like $Like) }
}

# ---------------------------------------------------------------- 1. синтаксис

$asts = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.ps1', '*.psd1' | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    Check ('синтаксис {0}' -f $f.Name) (-not $e.Count)
    foreach ($x in $e) { Write-Host ('   {0}:{1} {2}' -f $x.Extent.StartLineNumber, $x.Extent.StartColumnNumber, $x.Message) }
    $asts[$f.Name] = $ast
    # PowerShell 5.1 читает файл без BOM как ANSI: кириллица превратится в мусор
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $ascii = -not ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1)
    Check ('UTF-8 с BOM {0}' -f $f.Name) ($hasBom -or $ascii)
}

# ---------------------------------------------------------------- 2. функции окна без окна

# Функции из profile-move.ps1 по одной (сам скрипт без Windows не запустить: WinForms)
# Функции из profile-move.ps1 по одной (сам скрипт без Windows не запустить: WinForms). Загружать на уровне
# этого скрипта: . (Get-Fn 'Имя1', 'Имя2'); заглушки для остальных объявлять после
$all = @{}
foreach ($fd in $asts['profile-move.ps1'].FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $all[$fd.Name] = $fd.Extent.Text }
function Get-Fn([string[]]$Names) {
    [scriptblock]::Create((@($Names | ForEach-Object { if (-not $all.ContainsKey($_)) { throw "нет функции $_" }; $all[$_] }) -join "`n`n"))
}
$script:LogLines = New-Object System.Collections.Generic.List[string]
function Write-Log { param([string]$Text, [string]$Level = 'info') $script:LogLines.Add(('[{0}] {1}' -f $Level, $Text)) }
function Show-Msg([string]$Text, [string]$Icon = 'Information', [string]$Buttons = 'OK') { $script:Shown = @{ Text = $Text; Icon = $Icon; Buttons = $Buttons }; return $script:MsgAnswer }
$script:MsgAnswer = 'Cancel'

. (Get-Fn 'Initialize-Browsers', 'Get-ExcludeArgs', 'Test-BrowserRunning', 'Wait-BrowserClosed', 'Get-BrowserJobs', 'Test-Locked',
    'Get-ErrCode', 'New-ItemResult', 'Write-ItemLog', 'Get-CopyHas', 'Format-Size', 'Format-Span', 'Get-Worst', 'ConvertFrom-RoboError',
    'Invoke-Move', 'Show-Result')

# ---------------------------------------------------------------- 3. config.example.psd1 и браузеры

$cfg = Import-PowerShellDataFile (Join-Path $root 'config.example.psd1')
$script:Cfg = $cfg
Check 'config: StoreRoot пример' ($cfg.StoreRoot -like '\\*')
$b = @(Initialize-Browsers $cfg)
Check 'config: 5 браузеров' ($b.Count -eq 5)
Check 'config: ключи браузеров' ((($b | ForEach-Object { $_.Key }) -join ',') -eq 'Yandex,ChromiumGost,Chrome,Edge,Firefox')
Check 'config: признак открытого Chromium по умолчанию' (($b[0].LockFiles -join '|') -eq 'lockfile|Default\Network\Cookies')
Check 'config: DPAPI у Chromium' ($b[0].Dpapi -eq $true)
Check 'config: кэши Chromium по умолчанию' ($b[0].ExcludeDirs -contains 'Code Cache' -and $b[0].ExcludeDirs.Count -eq 19)
Check 'config: у Firefox без DPAPI' ($b[4].Dpapi -eq $false)
Check 'config: у Firefox свой признак' (($b[4].LockFiles -join '|') -eq 'Profiles\*\parent.lock')
Check 'config: у Chrome примечание' ([bool]$b[2].Note)

# config.psd1 до версии 1.4: один Яндекс из YandexPath
$legacy = @{
    StoreRoot = '\\nas\Migrate'; Domain = 'example.local'; EnableYandex = $true
    Folders = @(@{ Key = 'Desktop'; Title = 'Рабочий стол'; Path = 'Desktop' })
    YandexPath = 'AppData\Local\Yandex\YandexBrowser\User Data'
    YandexExcludeDirs = @('Cache', 'Code Cache', 'GPUCache'); YandexExcludeFiles = @('lockfile', '*.tmp')
    YandexExe = @('a.exe', 'b.exe', 'c.exe')
}
$bo = @(Initialize-Browsers $legacy)
Check 'старый config: один Яндекс' ($bo.Count -eq 1 -and $bo[0].Key -eq 'Yandex')
Check 'старый config: путь' ($bo[0].UserData[0] -eq 'AppData\Local\Yandex\YandexBrowser\User Data')
Check 'старый config: свои исключения' ($bo[0].ExcludeDirs.Count -eq 3 -and ($bo[0].ExcludeFiles -join ',') -eq 'lockfile,*.tmp')
Check 'старый config: exe' ($bo[0].Exe.Count -eq 3)
$legacy.EnableYandex = $false
Check 'старый config: EnableYandex = $false' (@(Initialize-Browsers $legacy).Count -eq 0)

$bad = $cfg.Clone()
$bad.Browsers = @(@{ Key = 'Chrome Beta'; Title = 'X'; UserData = @('a') })
Check 'ошибка: Key с пробелом' (Throws { Initialize-Browsers $bad } '*Key*')
$bad.Browsers = @(@{ Key = 'Desktop'; Title = 'X'; UserData = @('a') })
Check 'ошибка: Key занят папкой' (Throws { Initialize-Browsers $bad } '*Desktop*')
$bad.Browsers = @(@{ Key = 'A'; Title = 'X'; UserData = @('a') }, @{ Key = 'A'; Title = 'Y'; UserData = @('b') })
Check 'ошибка: Key повторяется' (Throws { Initialize-Browsers $bad } '*«A»*')
$bad.Browsers = @(@{ Key = 'A'; Title = 'X' })
Check 'ошибка: нет UserData' (Throws { Initialize-Browsers $bad } '*UserData*')
$bad.Browsers = @(@{ Key = 'A'; Title = 'X'; UserData = @('a'); Enabled = $false })
Check 'Enabled = $false: браузера нет' (@(Initialize-Browsers $bad).Count -eq 0)
$bad.Browsers = @()
Check 'пустой список браузеров' (@(Initialize-Browsers $bad).Count -eq 0)

# ---------------------------------------------------------------- 4. robocopy: исключения и ошибки

Check 'исключения: пусто' (@(Get-ExcludeArgs @() @()).Count -eq 0)
Check 'исключения: папки и файлы' ((@(Get-ExcludeArgs @('a b', 'c') @('*.tmp')) -join '|') -eq '/XD|a b|c|/XF|*.tmp')
Check 'исключения: только файлы' ((@(Get-ExcludeArgs $null @('desktop.ini', '~$*')) -join '|') -eq '/XF|desktop.ini|~$*')

$long = 'Очень длинное имя документа ' * 5 + '.docx'   # 145 знаков, больше 255 байт в UTF-8
$e = ConvertFrom-RoboError ('0x0000007B Копирование файла \\10.0.0.15\C$\Users\u\Desktop\' + $long) '\\10.0.0.15\C$\Users\u\Desktop' ($cfg.StoreRoot + '\u\2026-01-01_1200_PC\Desktop')
Check 'ошибка robocopy: имя длиннее 255 байт для NAS' ($e.Long -and $e.Code -eq 123 -and $e.Shown -like 'C:\Users\u\Desktop\*')
$e = ConvertFrom-RoboError '0x00000020 Копирование файла \\10.0.0.15\C$\Users\u\Documents\a.xlsx'
Check 'ошибка robocopy: файл открыт' ($e.Code -eq 32 -and -not $e.Long -and $e.Text -like '*C:\Users\u\Documents\a.xlsx')

# ---------------------------------------------------------------- 5. браузеры: что снимать и разворачивать

$script:Browsers = $b
$script:Titles = @{}
foreach ($x in $b) { $script:Titles[$x.Key] = $x.Title }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('pmtest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $tmp 'AppData/Local/Yandex/YandexBrowser/User Data/Default') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmp 'AppData/Roaming/Mozilla/Firefox/Profiles/abc.default-release') -Force | Out-Null
try {
    $prof = [pscustomobject]@{ Unc = $tmp }
    $pc = [pscustomobject]@{ Name = 'PC-1' }
    $res = New-Object System.Collections.Generic.List[object]
    $jobs = Get-BrowserJobs $prof $pc @('Desktop', 'Yandex', 'ChromiumGost', 'Chrome', 'Edge', 'Firefox') $null $res
    Check 'снятие: 2 браузера есть' ($jobs.Count -eq 2)
    Check 'снятие: какие' ((@($jobs | ForEach-Object { $_.B.Key }) -join ',') -eq 'Yandex,Firefox')
    Check 'снятие: путь профиля' ($jobs[0].Rel -eq 'AppData\Local\Yandex\YandexBrowser\User Data')
    Check 'снятие: 3 браузера «нет на ПК»' ($res.Count -eq 3 -and @($res | Where-Object { $_.Status -eq 'none' }).Count -eq 3)
    $res2 = New-Object System.Collections.Generic.List[object]
    $jobs2 = Get-BrowserJobs $prof $pc @('Desktop') $null $res2
    Check 'снятие: браузеры не отмечены' ($jobs2.Count -eq 0 -and $res2.Count -eq 0)

    $m = [pscustomobject]@{ Items = @(
        [pscustomobject]@{ Key = 'Yandex'; Status = 'ok' }
        [pscustomobject]@{ Key = 'Firefox'; Status = 'warn'; Src = 'AppData\Roaming\Mozilla\Firefox' }
        [pscustomobject]@{ Key = 'Chrome'; Status = 'none'; Src = '' }
    ) }
    $res3 = New-Object System.Collections.Generic.List[object]
    $jobs3 = Get-BrowserJobs $prof $pc @('Yandex', 'Chrome', 'Firefox', 'Edge') $m $res3
    Check 'развёртывание: 2 браузера из копии' ($jobs3.Count -eq 2)
    Check 'развёртывание: путь по умолчанию (копия 1.3)' ($jobs3[0].Rel -eq 'AppData\Local\Yandex\YandexBrowser\User Data')
    Check 'развёртывание: путь из копии (Src)' ($jobs3[1].Rel -eq 'AppData\Roaming\Mozilla\Firefox')
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force }

$r = New-ItemResult 'Yandex' 'ok'
$r.Src = 'x\y'
Check 'результат: Src и название' ($r.Src -eq 'x\y' -and $r.Title -eq $b[0].Title)
Check 'итог: худший' ((Get-Worst @(@{ Status = 'ok' }, @{ Status = 'none' }, @{ Status = 'warn' })) -eq 'warn')
Check 'итог: пусто = ok' ((Get-Worst @()) -eq 'ok')

# ---------------------------------------------------------------- 6. «Перенести сразу» (сеть, AD и копирование: заглушки)

function Get-PmUser([string]$Login) { [pscustomobject]@{ Login = $Login; Name = 'Иванов И. И.'; Sid = 'S-1-5-21-1-2-3-1001'; Enabled = $true } }
function Resolve-Pc([string]$Name) { [pscustomobject]@{ Name = $Name.ToUpper(); Host = $script:Hosts[$Name]; Ips = @(); Os = ''; ByIp = $false } }
function Test-PcAccess($Pc) { }
function Restore-RemoteRegistry { }
function Find-UserProfile($Pc, $User) { [pscustomobject]@{ Unc = $script:NewProfile; Local = 'C:\Users\ivanov' } }
function Invoke-Capture([string]$Login, [string]$PcName, [string[]]$Groups, $Resolved) {
    $script:Calls.Add(('capture {0}' -f $Resolved.Name))
    [pscustomobject]@{ Path = '\\nas\Migrate\ivanov\copy'; Status = 'ok'; Bytes = 3GB; Head = 'h'; LongText = '' }
}
function Invoke-Restore($Copy, [string]$PcName, [string[]]$Groups, $Resolved) {
    $script:Calls.Add(('restore {0} {1}' -f $Copy.Path, $Resolved.Name))
    if ($script:RestoreFails) { throw 'нет связи' }
    [pscustomobject]@{ Status = 'warn'; Head = 'h'; LongText = ''; Checks = 'Проверить с сотрудником: файлы.' }
}
$script:Hosts = @{ 'pc-old' = '10.0.0.1'; 'pc-new' = '10.0.0.2'; 'pc-same' = '10.0.0.1' }
$script:Calls = New-Object System.Collections.Generic.List[string]
$script:NewProfile = '\\10.0.0.2\C$\Users\ivanov'
Check 'перенос: тот же ПК не переносим' ((Throws { Invoke-Move 'ivanov' 'pc-old' 'pc-same' @('Desktop') } '*один и тот же*') -and -not $script:Calls.Count)
$script:NewProfile = $null
Check 'перенос: нет профиля на новом ПК, копию не снимаем' ((Throws { Invoke-Move 'ivanov' 'pc-old' 'pc-new' @('Desktop') } '*ещё не входил*') -and -not $script:Calls.Count)
$script:NewProfile = '\\10.0.0.2\C$\Users\ivanov'
$mv = Invoke-Move 'ivanov' 'pc-old' 'pc-new' @('Desktop')
Check 'перенос: снять, потом развернуть эту копию' (($script:Calls -join '; ') -eq 'capture PC-OLD; restore \\nas\Migrate\ivanov\copy PC-NEW')
Check 'перенос: итог худший из двух' ($mv.Status -eq 'warn')
Check 'перенос: заголовок' ($mv.Head -like '*Иванов И. И. (ivanov)*PC-OLD*PC-NEW*3,0*' -or $mv.Head -like '*Иванов И. И. (ivanov)*PC-OLD*PC-NEW*3.0*')
$script:RestoreFails = $true
Check 'перенос: развернуть не удалось, копия остаётся' (Throws { Invoke-Move 'ivanov' 'pc-old' 'pc-new' @('Desktop') } 'Копия снята, но развернуть на PC-NEW не удалось: нет связи*')
$script:RestoreFails = $false

Show-Result $mv
Check 'итоговое сообщение: заголовок, замечания, что проверить' ($script:Shown.Text -like ($mv.Head + '*замечания*Проверить с сотрудником*') -and $script:Shown.Icon -eq 'Warning')
Show-Result ([pscustomobject]@{ Status = 'ok'; Head = 'Копия снята.'; LongText = '' }) 'Дальше: развернуть.'
Check 'итоговое сообщение: без замечаний' ($script:Shown.Text -eq ('Копия снята.' + "`r`n`r`n" + 'Дальше: развернуть.') -and $script:Shown.Icon -eq 'Information')

# ----------------------------------------------------------------

Write-Host ''
if ($script:Fail) { Write-Host ('Не прошло проверок: {0}' -f $script:Fail) -ForegroundColor Red } else { Write-Host 'Все проверки прошли' -ForegroundColor Green }
exit $script:Fail
