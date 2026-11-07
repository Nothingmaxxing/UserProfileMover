# Проверки без Windows и без сети: синтаксис скриптов, config.example.psd1 и логика функций окна.
# Запуск: pwsh -File tests/check.ps1 (PowerShell 7 на Linux или Windows) или в Windows PowerShell 5.1.
# Код выхода = число проваленных проверок
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }   # кириллица в журнале GitHub Actions
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
# Фильтр по расширению, а не -Include: в Windows PowerShell 5.1 -Include вместе с -LiteralPath не работает
foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psd1') -and $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
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

. (Get-Fn 'T', 'Set-Language', 'Initialize-Browsers', 'Get-ExcludeArgs', 'Test-BrowserRunning', 'Wait-BrowserClosed', 'Get-BrowserJobs', 'Test-Locked',
    'Get-ErrCode', 'New-ItemResult', 'Write-ItemLog', 'Get-CopyHas', 'Format-Size', 'Format-Span', 'Get-Worst', 'ConvertFrom-RoboError',
    'Invoke-Move', 'Show-Result', 'ConvertTo-HtmlText', 'Get-ActStatus', 'New-Act')
Set-Language 'ru' $root   # проверки ниже ждут русские тексты

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
function Remove-Staging([string]$Dir) { $script:Calls.Add(('wipe {0}' -f $Dir)) }
function Find-UserProfile($Pc, $User) { [pscustomobject]@{ Unc = $script:NewProfile; Local = 'C:\Users\ivanov' } }
function Invoke-Capture([string]$Login, [string]$PcName, [string[]]$Groups, $Resolved, [string]$Password, [switch]$KeepData) {
    $script:Calls.Add(('capture {0}' -f $Resolved.Name))
    $p = '\\nas\Migrate\ivanov\copy'
    [pscustomobject]@{ Path = $p; DataDir = $(if ($Password) { 'C:\stage' } else { $p }); Encrypted = [bool]$Password; Status = 'ok'; Bytes = 3GB; Head = 'h'; LongText = '' }
}
function Invoke-Restore($Copy, [string]$PcName, [string[]]$Groups, $Resolved, [string]$Password, [string]$DataDir) {
    $script:Calls.Add(('restore {0} {1} {2}' -f $Copy.Path, $Resolved.Name, $DataDir))
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
Check 'перенос: снять, потом развернуть эту копию' (($script:Calls -join '; ') -eq 'capture PC-OLD; restore \\nas\Migrate\ivanov\copy PC-NEW \\nas\Migrate\ivanov\copy')
Check 'перенос: итог худший из двух' ($mv.Status -eq 'warn')
Check 'перенос: заголовок' ($mv.Head -like '*Иванов И. И. (ivanov)*PC-OLD*PC-NEW*3,0*' -or $mv.Head -like '*Иванов И. И. (ivanov)*PC-OLD*PC-NEW*3.0*')
$script:RestoreFails = $true
Check 'перенос: развернуть не удалось, копия остаётся' (Throws { Invoke-Move 'ivanov' 'pc-old' 'pc-new' @('Desktop') } 'Копия снята, но развернуть на PC-NEW не удалось: нет связи*')
$script:RestoreFails = $false
$script:Calls.Clear()
$mv2 = Invoke-Move 'ivanov' 'pc-old' 'pc-new' @('Desktop') 'Passw0rd!'
Check 'перенос с шифрованием: развернуть из временной папки и стереть её' (($script:Calls -join '; ') -eq 'capture PC-OLD; restore \\nas\Migrate\ivanov\copy PC-NEW C:\stage; wipe C:\stage' -and $mv2.Head -like '*зашифрована*')
$script:Calls.Clear(); $script:RestoreFails = $true
Check 'перенос с шифрованием: при ошибке временная папка тоже стирается' ((Throws { Invoke-Move 'ivanov' 'pc-old' 'pc-new' @('Desktop') 'Passw0rd!' } 'Копия снята*') -and ($script:Calls -join '; ') -like '*wipe C:\stage')
$script:RestoreFails = $false

Show-Result $mv
Check 'итоговое сообщение: заголовок, замечания, что проверить' ($script:Shown.Text -like ($mv.Head + '*замечания*Проверить с сотрудником*') -and $script:Shown.Icon -eq 'Warning')
Show-Result ([pscustomobject]@{ Status = 'ok'; Head = 'Копия снята.'; LongText = '' }) 'Дальше: развернуть.'
Check 'итоговое сообщение: без замечаний' ($script:Shown.Text -eq ('Копия снята.' + "`r`n`r`n" + 'Дальше: развернуть.') -and $script:Shown.Icon -eq 'Information')

# ---------------------------------------------------------------- 7. акт переноса

$script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('pmtest-logs-' + [guid]::NewGuid().ToString('N'))
$script:Version = 'profile-move test'
$script:Titles = [ordered]@{ Desktop = 'Рабочий стол'; Yandex = 'Яндекс Браузер'; Dpapi = 'Ключи DPAPI' }
$script:Cfg = @{ RetentionDays = 30; OrgName = 'ООО <Ромашка> & Ко' }
try {
    $man = '{"Login":"ivanov","Name":"Иванов <b>И. И.</b>","SourcePC":"PC-OLD","Created":"2026-11-08T10:05:00","Operator":"EX\\adm (окно: EX\\me на ME)",
      "Items":[{"Key":"Desktop","Title":"Рабочий стол","Status":"ok","Files":12,"Bytes":1048576,"Note":""},
               {"Key":"Chrome","Title":"Google Chrome","Status":"none","Files":0,"Bytes":0,"Note":"на этом ПК его нет"}],
      "Restores":[]}' | ConvertFrom-Json
    $rec = [ordered]@{ PC = 'PC-NEW'; Date = '2026-11-08T11:30:00'; Operator = 'EX\adm'; Status = 'warn'; Items = @(
        [ordered]@{ Key = 'Dpapi'; Title = 'Ключи DPAPI'; Status = 'ok'; Files = 3; Bytes = 2048; Note = '' }
        [ordered]@{ Key = 'Desktop'; Title = 'Рабочий стол'; Status = 'warn'; Files = 12; Bytes = 1048576; Note = 'не скопировано 1 файл(ов): файл открыт в программе — 1' }
        [ordered]@{ Key = 'Yandex'; Title = 'Яндекс Браузер'; Status = 'skip'; Files = 0; Bytes = 0; Note = 'браузер был открыт' }
    ) }
    $p = New-Act $man $rec
    $html = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
    Check 'акт: файл в logs\acts' ((Split-Path (Split-Path $p -Parent) -Leaf) -eq 'acts' -and (Split-Path $p -Leaf) -eq '2026-11-08_1130_ivanov_PC-NEW.html')
    Check 'акт: HTML экранирован' ($html -like '*Иванов &lt;b&gt;И. И.&lt;/b&gt;*' -and $html -like '*ООО &lt;Ромашка&gt; &amp; Ко*' -and $html -notlike '*<b>И. И.</b>*')
    Check 'акт: перенос на другой ПК' ($html -like '*переноса данных пользователя на другой компьютер*' -and $html -like '*PC-NEW, данные перенесены 08.11.2026 11:30*')
    Check 'акт: строки таблицы' (([regex]::Matches($html, '<tr><td class="c">')).Count -eq 3)
    Check 'акт: замечания и пропуск' ($html -like '*с замечаниями, см. графу*' -and $html -like '*пропущено*' -and $html -like '*файл открыт в программе*')
    Check 'акт: строки для подписи' ($html -like '*Перенос выполнил*' -and $html -like '*Данные проверил, претензий нет*')
    $p2 = New-Act $man $null
    $html2 = [IO.File]::ReadAllText($p2, [Text.Encoding]::UTF8)
    Check 'акт без развёртывания: о резервной копии' ($html2 -like '*резервного копирования*' -and $html2 -like '*снята полностью*' -and $html2 -notlike '*Google Chrome*')
    $rec.PC = 'pc-old'
    $html3 = [IO.File]::ReadAllText((New-Act $man $rec), [Text.Encoding]::UTF8)
    Check 'акт: тот же ПК = восстановление' ($html3 -like '*восстановления данных*' -and $html3 -like '*Восстановлено:*')
} finally { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------- 8. шифрование: пароль и настоящий 7-Zip, если он есть

. (Get-Fn 'Test-CopyPassword', 'Get-7zMessage', 'Format-Arg', 'Stop-Child', 'Invoke-7z', 'Compress-Copy', 'Test-ArchivePassword', 'Expand-Copy', 'Get-EncryptPassword')
Check 'пароль: короткий' ((Test-CopyPassword 'Abc123!') -like '*8*')
Check 'пароль: русские буквы' ((Test-CopyPassword 'Пароль12345') -like '*латинские*')
Check 'пароль: пробел в конце' ((Test-CopyPassword 'Passw0rd! ') -like '*пробелов*')
Check 'пароль: годный, с пробелом внутри и знаками' ((Test-CopyPassword 'Pa ss"w0rd''$%^&*') -eq '')
$eb = [pscustomobject]@{ Check = [pscustomobject]@{ Checked = $true }; P1 = [pscustomobject]@{ Text = 'Passw0rd!' }; P2 = [pscustomobject]@{ Text = 'passw0rd!' } }
Check 'пароль: повтор с другим регистром не совпадает' ((Get-EncryptPassword $eb).Error -like '*не совпадают*')
$eb.P2.Text = 'Passw0rd!'
$gp = Get-EncryptPassword $eb
Check 'пароль: совпал' ($gp.Error -eq '' -and $gp.Password -eq 'Passw0rd!')
$eb.Check.Checked = $false
Check 'без шифрования: пароля нет' ((Get-EncryptPassword $eb).Password -eq '')

$z7 = @('C:\Program Files\7-Zip\7z.exe', '/usr/bin/7zz', '/usr/bin/7z') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $z7) { Write-Host 'SKIP 7-Zip не найден: проверки архива пропущены' -ForegroundColor Yellow }
else {
    # DoEvents из WinForms: в PowerShell 7 на Linux его нет, хватит пустого
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop } catch { }
    if (-not ('System.Windows.Forms.Application' -as [type])) { Add-Type -TypeDefinition 'namespace System.Windows.Forms { public static class Application { public static void DoEvents() { } } }' }
    $script:SevenZip = $z7; $script:MainForm = $null; $script:AppTitle = 'test'; $script:ProgressLogSec = 30; $script:Aborting = $false
    $script:Titles['Archive'] = 'Шифрование'
    $zt = Join-Path ([IO.Path]::GetTempPath()) ('pmtest-7z-' + [guid]::NewGuid().ToString('N'))
    try {
        $src = Join-Path $zt 'stage 1'
        New-Item -ItemType Directory -Path (Join-Path $src 'Desktop/Папка с пробелом') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $src 'DPAPI') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'Desktop/Папка с пробелом/документ.txt'), 'Привет, мир')
        [IO.File]::WriteAllBytes((Join-Path $src 'DPAPI/key'), [byte[]](1..255))
        $pw = 'Pa ss"w0rd''$%^&*'
        $arch = Join-Path $zt 'copy/data.7z'
        New-Item -ItemType Directory -Path (Split-Path $arch) -Force | Out-Null
        $res7 = New-Object System.Collections.Generic.List[object]
        $size = Compress-Copy $src $arch $pw $res7
        Check '7-Zip: архив создан' ((Test-Path -LiteralPath $arch) -and $size -gt 0 -and $res7[0].Status -eq 'ok' -and $res7[0].Key -eq 'Archive')
        Check '7-Zip: пароль подходит' ((Test-ArchivePassword $arch $pw) -eq '')
        Check '7-Zip: неверный пароль' ((Test-ArchivePassword $arch 'Wrong-password-1') -eq 'Неверный пароль копии.')
        # Через Invoke-7z, а не & 7z 2>&1: в Windows PowerShell 5.1 stderr программы при ErrorAction Stop обрывает скрипт
        $lst = Invoke-7z @('l', '--', $arch) 'Wrong-password-1' 'test'
        Check '7-Zip: без пароля имена файлов не видны' ($lst.Code -ge 2 -and $lst.Output -notlike '*документ*' -and $lst.Output -notlike '*DPAPI*')
        $out = Join-Path $zt 'out'
        New-Item -ItemType Directory -Path $out | Out-Null
        Expand-Copy $arch $out $pw
        Check '7-Zip: распаковано как было' (([IO.File]::ReadAllText((Join-Path $out 'Desktop/Папка с пробелом/документ.txt'))) -eq 'Привет, мир' -and ([IO.File]::ReadAllBytes((Join-Path $out 'DPAPI/key'))).Length -eq 255)
        Check '7-Zip: распаковка с неверным паролем' (Throws { Expand-Copy $arch (Join-Path $zt 'out2') 'Wrong-password-1' } 'Неверный пароль копии')
        # Архив не создать (на месте папки файл): строка «Шифрование» с ошибкой, недоделанного архива нет
        $res8 = New-Object System.Collections.Generic.List[object]
        [IO.File]::WriteAllText((Join-Path $zt 'file'), 'x')
        $bad7 = Join-Path $zt 'file/data.7z'
        [void](Compress-Copy $src $bad7 $pw $res8)
        Check '7-Zip: ошибка, архива нет' ($res8[0].Status -eq 'err' -and $res8[0].Note -like '*код 2*' -and -not (Test-Path -LiteralPath $bad7))
    } finally { Remove-Item -LiteralPath $zt -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------- 9. версия и проверка обновлений

. (Get-Fn 'ConvertTo-AppVersion', 'Show-Update')
Check 'версия из тега' ((ConvertTo-AppVersion 'v1.5') -eq [version]'1.5' -and (ConvertTo-AppVersion '1.5.1') -eq [version]'1.5.1' -and -not (ConvertTo-AppVersion 'latest'))
$verLine = @(Select-String -LiteralPath (Join-Path $root 'profile-move.ps1') -Pattern "^\`$script:AppVersion = '([^']+)'")
$appVer = if ($verLine.Count) { $verLine[0].Matches[0].Groups[1].Value } else { '' }
Check 'AppVersion в profile-move.ps1' ([bool](ConvertTo-AppVersion $appVer))
$readme = [IO.File]::ReadAllText((Join-Path $root 'README.md'), [Text.Encoding]::UTF8)
Check 'README: в «Версиях» первой идёт AppVersion' ($readme -match '## Версии\s+- \*\*([\d.]+)\*\*' -and $Matches[1] -eq $appVer)
$script:AppVersion = '1.5'
$script:UpdateLink = [pscustomobject]@{ Text = ''; Tag = ''; Visible = $false }
Show-Update ([pscustomobject]@{ Repo = 'a/b'; Tag = 'v1.5'; Url = 'https://github.com/a/b/releases/tag/v1.5' })
Check 'обновление: та же версия, ссылки нет' (-not $script:UpdateLink.Visible)
Show-Update ([pscustomobject]@{ Repo = 'a/b'; Tag = 'v1.6'; Url = 'http://example.com/x' })
Check 'обновление: новая версия, ссылка только на GitHub' ($script:UpdateLink.Visible -and $script:UpdateLink.Tag -eq 'https://github.com/a/b/releases/latest' -and $script:UpdateLink.Text -like '*1.6*')

# ---------------------------------------------------------------- 10. английский интерфейс (lang\en.psd1)

$tr = Import-PowerShellDataFile (Join-Path $root 'lang/en.psd1')
$keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$naked = New-Object System.Collections.Generic.List[string]
foreach ($f in @('profile-move.ps1', 'start.ps1')) {
    foreach ($c in $asts[$f].FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'T' }, $true)) {
        $a = $c.CommandElements[1]
        if ($a -is [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$keys.Add($a.Value.TrimStart(' ')) }
    }
    # Русский текст вне T не переведётся: каждый литерал '...' с кириллицей должен быть первым аргументом T,
    # в "..." кириллицы быть не должно (here-string @'...'@ с кодом C# не в счёт: там только комментарии)
    foreach ($n in $asts[$f].FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $args[0].StringConstantType -eq 'SingleQuoted' -and $args[0].Value -match '[Ѐ-ӿ]' }, $true)) {
        $p = $n.Parent
        $inT = ($p -is [System.Management.Automation.Language.CommandAst] -and $p.GetCommandName() -eq 'T' -and $p.CommandElements[1] -eq $n)
        if (-not $inT) { $naked.Add(('{0}:{1} {2}' -f $f, $n.Extent.StartLineNumber, $n.Value)) }
    }
    $tk = $null; $te = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$tk, [ref]$te)
    foreach ($x in $tk) {
        if ($x.Kind -in @('StringExpandable', 'HereStringExpandable') -and $x.Text -match '[Ѐ-ӿ]') { $naked.Add(('{0}:{1} {2}' -f $f, $x.Extent.StartLineNumber, $x.Text)) }
    }
}
$cfgRu = Import-PowerShellDataFile (Join-Path $root 'config.example.psd1')
foreach ($x in $cfgRu.Folders) { [void]$keys.Add([string]$x.Title) }
foreach ($x in $cfgRu.Browsers) { [void]$keys.Add([string]$x.Title); if ($x.Note) { [void]$keys.Add([string]$x.Note) } }
$need = @($keys | Where-Object { $_ -match '[^\x00-\x7F]' })
foreach ($x in $naked) { Write-Host ('   без T: {0}' -f $x) }
Check 'перевод: весь русский текст скриптов в T' ($naked.Count -eq 0)
$miss = @($need | Where-Object { -not $tr.ContainsKey($_) })
foreach ($x in $miss) { Write-Host ('   нет перевода: {0}' -f $x) }
Check ('перевод: у всех {0} строк есть английский' -f $need.Count) ($need.Count -gt 300 -and $miss.Count -eq 0)
$extra = @($tr.Keys | Where-Object { -not $keys.Contains($_) })
foreach ($x in $extra) { Write-Host ('   лишний перевод: {0}' -f $x) }
Check 'перевод: нет лишних строк' ($extra.Count -eq 0)
$ph = '\{\d+(?::[^}]*)?\}'
$badPh = @($tr.Keys | Where-Object {
    $k = [string]$_; $v = [string]$tr[$_]
    ((@([regex]::Matches($k, $ph) | ForEach-Object { $_.Value } | Sort-Object) -join ' ') -cne (@([regex]::Matches($v, $ph) | ForEach-Object { $_.Value } | Sort-Object) -join ' ')) -or
    ($k.EndsWith(' ') -ne $v.EndsWith(' ')) -or ($v -match '[Ѐ-ӿ]') -or -not $v.Trim() })
foreach ($x in $badPh) { Write-Host ('   не сходится: {0} = {1}' -f $x, $tr[$x]) }
Check 'перевод: те же {0}, пробел в конце, без кириллицы' ($badPh.Count -eq 0)

Set-Language 'en' $root
Check 'язык en: перевод с отступом' ((T '   профиль: {0}{1}') -ceq '   profile: {0}{1}' -and $script:Lang -eq 'en')
Check 'язык en: нет перевода, остаётся как есть' ((T 'Такой строки нет') -ceq 'Такой строки нет' -and (T 'Chromium-Gost') -ceq 'Chromium-Gost')
Check 'язык en: даты' ($script:DateFmt -eq 'yyyy-MM-dd HH:mm' -and $script:DayFmt -eq 'yyyy-MM-dd')
Check 'язык en: размер' ((Format-Size 3GB) -like '3?0 GB' -and (Format-Size 10) -eq '10 B')
$ben = @(Initialize-Browsers $cfgRu)
Check 'язык en: названия браузеров и примечания' ($ben[0].Title -eq 'Yandex Browser' -and $ben[2].Note -like 'Since version 127*')
Set-Language 'xx' $root
Check 'язык без файла перевода: русский' ($script:Lang -eq 'ru' -and (T 'Отмена') -ceq 'Отмена' -and $script:DateFmt -eq 'dd.MM.yyyy HH:mm')
Set-Language 'ru' $root
Check 'язык ru' ((T '   профиль: {0}{1}') -ceq '   профиль: {0}{1}')
$fnSame = foreach ($n in @('T', 'Set-Language')) {
    $x = @($asts['start.ps1'].FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $n }, $false))
    ($x.Count -eq 1 -and $x[0].Extent.Text -ceq $all[$n])
}
Check 'T и Set-Language в start.ps1 такие же, как в profile-move.ps1' (@($fnSame | Where-Object { -not $_ }).Count -eq 0)

# Английский пример настроек: те же параметры и пути, что в config.example.psd1 (свои названия, примечания и включённость)
$cfgEn = Import-PowerShellDataFile (Join-Path $root 'config.example.en.psd1')
Check 'config.example.en: те же параметры' (((@($cfgRu.Keys | Sort-Object) -join ',') -ceq (@($cfgEn.Keys | Sort-Object) -join ',')))
$diff = New-Object System.Collections.Generic.List[string]
foreach ($k in $cfgRu.Keys) {
    if ($k -in @('Folders', 'Browsers', 'EnableCryptoPro')) { continue }
    if ((@($cfgRu[$k]) -join '|') -cne (@($cfgEn[$k]) -join '|')) { $diff.Add($k) }
}
$fr = @($cfgRu.Folders | ForEach-Object { '{0}={1}' -f $_.Key, $_.Path }) -join ';'
$fe = @($cfgEn.Folders | ForEach-Object { '{0}={1}' -f $_.Key, $_.Path }) -join ';'
if ($fr -cne $fe) { $diff.Add('Folders') }
$sig = { param($x) (@('UserData', 'Exe', 'LockFiles', 'ExcludeDirs', 'ExcludeFiles', 'Dpapi') | ForEach-Object { '{0}:{1}' -f $_, (@($x[$_]) -join '|') }) -join ';' }
$br = @{}; foreach ($x in $cfgRu.Browsers) { $br[$x.Key] = & $sig $x }
foreach ($x in $cfgEn.Browsers) { if (-not $br.ContainsKey($x.Key) -or $br[$x.Key] -cne (& $sig $x)) { $diff.Add('Browsers.' + $x.Key) } }
if (@($cfgEn.Browsers).Count -ne @($cfgRu.Browsers).Count) { $diff.Add('Browsers') }
foreach ($x in $diff) { Write-Host ('   отличается: {0}' -f $x) }
Check 'config.example.en: значения и пути как в config.example.psd1' ($diff.Count -eq 0)
Check 'config.example.en: включены Chrome, Edge, Firefox' ((@(Initialize-Browsers $cfgEn | ForEach-Object { $_.Key }) -join ',') -eq 'Chrome,Edge,Firefox')
$readmeEn = [IO.File]::ReadAllText((Join-Path $root 'README.en.md'), [Text.Encoding]::UTF8)
Check 'README.en: в «Versions» первой идёт AppVersion' ($readmeEn -match '## Versions\s+- \*\*([\d.]+)\*\*' -and $Matches[1] -eq $appVer)
Check 'README.en: раздел «Preparing the storage»' ($readmeEn -match '(?m)^#+ Preparing the storage')

# ----------------------------------------------------------------

Write-Host ''
if ($script:Fail) { Write-Host ('Не прошло проверок: {0}' -f $script:Fail) -ForegroundColor Red } else { Write-Host 'Все проверки прошли' -ForegroundColor Green }
exit $script:Fail
