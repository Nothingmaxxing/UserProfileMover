#Requires -Version 5.1
# Окно «Перенос профиля»: перенос данных сотрудника со старого ПК на новый через хранилище копий (NAS, шара или локальная папка).
# Запуск: profile-move.cmd → start.ps1 спрашивает учётку администратора ПК и запускает это окно так,
# что к ПК и сетевому хранилищу оно ходит под ней (как runas /netonly), а на этом ПК работает под вашей учёткой.
#  - «Снять с ПК»: рабочий стол, документы, загрузки (список папок в config.psd1), профили браузеров (Яндекс,
#    Chromium-Gost, Chrome, Edge, Firefox; список в config.psd1), ключи DPAPI сотрудника, подписи КриптоПро
#    (папка «Директория» и контейнеры из реестра), личные сертификаты
#    → <StoreRoot>\<логин>\<дата>_<время>_<ПК>.
#  - «Развернуть на ПК»: то же обратно в профиль сотрудника на новом ПК (сотрудник должен один раз войти туда).
#  - «Перенести сразу»: оба шага подряд, когда старый и новый ПК включены.
# На старом ПК ничего не удаляется и не меняется. Для реестра ПК окно на время работы включает службу
# «Удалённый реестр» и потом возвращает её как было. Пароли и куки браузеров на Chromium переносятся вместе
# с ключами DPAPI: учётка доменная, SID тот же, поэтому на новом ПК Windows их расшифрует.
# К ПК окно ходит по IP: адреса берёт у DNS контроллера домена (DcIp в config.psd1, если задан), так что работает,
# даже когда VPN/прокси на ПК администратора подменяет DNS. Что по адресу отвечает нужный ПК, проверяет по имени,
# которое сообщает сам ПК.
# https://github.com/Nothingmaxxing/UserProfileMover, лицензия MIT.
# -NoGui: только загрузить функции без окна (для проверки: . .\profile-move.ps1 -NoGui)
param([string]$NetUser = '', [switch]$NoGui)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.DirectoryServices, System.ServiceProcess
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = $PSScriptRoot

# Браузеры из config.psd1 с настройками по умолчанию. В config.psd1 до версии 1.4 браузер один: Яндекс из YandexPath
function Initialize-Browsers($Cfg) {
    $chDirs = @('Cache', 'Code Cache', 'GPUCache', 'GrShaderCache', 'GraphiteDawnCache', 'ShaderCache',
        'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'CacheStorage', 'ScriptCache',
        'Crashpad', 'Crash Reports', 'BrowserMetrics', 'optimization_guide_model_store',
        'component_crx_cache', 'extensions_crx_cache', 'Safe Browsing', 'SwReporter')
    $chFiles = @('lockfile', '*.tmp', '*.pma')
    $chLocks = @('lockfile', 'Default\Network\Cookies')
    if ($Cfg.ContainsKey('ChromiumExcludeDirs')) { $chDirs = @($Cfg.ChromiumExcludeDirs | Where-Object { $_ }) }
    if ($Cfg.ContainsKey('ChromiumExcludeFiles')) { $chFiles = @($Cfg.ChromiumExcludeFiles | Where-Object { $_ }) }
    if ($Cfg.ContainsKey('ChromiumLockFiles')) { $chLocks = @($Cfg.ChromiumLockFiles | Where-Object { $_ }) }
    $src = @($Cfg.Browsers | Where-Object { $_ })
    if (-not $Cfg.ContainsKey('Browsers') -and $Cfg.YandexPath) {
        $src = @(@{ Key = 'Yandex'; Title = 'Яндекс Браузер'; Enabled = ($Cfg.EnableYandex -ne $false); UserData = @($Cfg.YandexPath)
            ExcludeDirs = $Cfg.YandexExcludeDirs; ExcludeFiles = $Cfg.YandexExcludeFiles; Exe = $Cfg.YandexExe })
    }
    $taken = @('Dpapi', 'Crypto', 'CryptoReg', 'CryptoDir', 'CertsMy', 'CertsCrypto') + @($Cfg.Folders | ForEach-Object { [string]$_.Key })
    $seen = @{}
    foreach ($b in $src) {
        $key = [string]$b.Key
        if ($key -notmatch '^[A-Za-z0-9]+$') { throw ('браузер «{0}»: Key должен быть из латинских букв и цифр, а он «{1}»' -f $b.Title, $key) }
        if ($taken -contains $key -or $seen.ContainsKey($key)) { throw ('браузер «{0}»: Key «{1}» уже занят папкой, подписями или другим браузером' -f $b.Title, $key) }
        $seen[$key] = $true
        if ($b.Enabled -eq $false) { continue }
        $ud = @($b.UserData | Where-Object { $_ })
        if (-not $ud.Count) { throw ('браузер «{0}»: не указан UserData' -f $b.Title) }
        [pscustomobject]@{
            Key          = $key
            Title        = $(if ($b.Title) { [string]$b.Title } else { $key })
            UserData     = $ud
            Dpapi        = ($b.Dpapi -ne $false)
            LockFiles    = $(if ($b.ContainsKey('LockFiles')) { @($b.LockFiles | Where-Object { $_ }) } else { $chLocks })
            ExcludeDirs  = $(if ($b.ContainsKey('ExcludeDirs')) { @($b.ExcludeDirs | Where-Object { $_ }) } else { $chDirs })
            ExcludeFiles = $(if ($b.ContainsKey('ExcludeFiles')) { @($b.ExcludeFiles | Where-Object { $_ }) } else { $chFiles })
            Exe          = @($b.Exe | Where-Object { $_ })
            Note         = [string]$b.Note
        }
    }
}

# Ошибку в config.psd1 показываем окном: этот скрипт запускается без консоли
try {
    $script:Cfg = Import-PowerShellDataFile -Path (Join-Path $script:Root 'config.psd1')
    if (-not $script:Cfg.Domain) { $script:Cfg.Domain = $env:USERDNSDOMAIN }
    if ($null -eq $script:Cfg.EnableCryptoPro) { $script:Cfg.EnableCryptoPro = $true }
    $script:Browsers = @(Initialize-Browsers $script:Cfg)
} catch {
    if ($NoGui) { throw }
    [void][System.Windows.Forms.MessageBox]::Show(('Ошибка в config.psd1: {0}' -f $_.Exception.Message), 'Перенос профиля', 'OK', 'Error')
    exit 1
}
$script:LogDir = Join-Path $script:Root 'logs'
New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
$script:LogFile = Join-Path $script:LogDir ('{0:yyyy-MM-dd}_{1}.log' -f (Get-Date), $env:COMPUTERNAME)
$script:NetUser = if ($NetUser) { $NetUser } else { '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME }
$script:Version = 'profile-move 1.4 (08.11.2026)'
$script:AppTitle = 'Перенос профиля'
$script:Busy = $false
$script:LogBox = $null
$script:Grid = $null
$script:InfoLabel = $null
$script:MainForm = $null
$script:Copies = @()
$script:Buttons = @()
$script:RrState = @{}
$script:HklmCache = @{}
$script:HostNames = @{}     # IP → имя ПК, для журнала
$script:AdPath = $null      # путь LDAP, через который AD ответил (DC по IP или по имени домена)
$script:AdRoots = @{}
$script:ProgressLogSec = 30   # как часто строка с процентом пишется в журнал (в заголовке окна процент каждые 2 с)
$script:LongPaths = New-Object System.Collections.Generic.List[string]   # не скопированные из-за длинного пути, за одну операцию

$script:Titles = [ordered]@{
    Yandex      = 'Яндекс Браузер'
    Dpapi       = 'Ключи DPAPI'
    CryptoReg   = 'КриптоПро: контейнеры в реестре'
    CryptoDir   = 'КриптоПро: папка «Директория»'
    CertsMy     = 'Личные сертификаты'
    CertsCrypto = 'Ключи Windows к сертификатам'
}
foreach ($f in $script:Cfg.Folders) { $script:Titles[[string]$f.Key] = [string]$f.Title }
foreach ($b in $script:Browsers) { $script:Titles[$b.Key] = $b.Title }
# Галочки в окнах: группа «Подписи» = все части КриптоПро и сертификатов
$script:CryptoKeys = @('CryptoReg', 'CryptoDir', 'CertsMy', 'CertsCrypto')

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PmDisk {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool GetDiskFreeSpaceEx(string dir, out ulong freeForUser, out ulong total, out ulong totalFree);
    public static long Free(string dir) {
        ulong a, b, c;
        if (!dir.EndsWith("\\")) dir += "\\";
        if (!GetDiskFreeSpaceEx(dir, out a, out b, out c)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return (long)a;
    }
}
public static class PmNet {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WKSTA_INFO_100 { public int platform_id; public string computername; public string langroup; public int ver_major; public int ver_minor; }
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode)]
    static extern int NetWkstaGetInfo(string server, int level, out IntPtr buf);
    [DllImport("netapi32.dll")]
    static extern int NetApiBufferFree(IntPtr buf);
    // Имя ПК (NetBIOS) и домен, как их сообщает сам ПК по адресу server (через SMB)
    public static string[] Info(string server) {
        IntPtr p;
        int rc = NetWkstaGetInfo("\\\\" + server, 100, out p);
        if (rc != 0) throw new System.ComponentModel.Win32Exception(rc);
        try {
            WKSTA_INFO_100 w = (WKSTA_INFO_100)Marshal.PtrToStructure(p, typeof(WKSTA_INFO_100));
            return new string[] { w.computername, w.langroup };
        } finally { NetApiBufferFree(p); }
    }
}
'@

# ---------------------------------------------------------------- общее

function Write-Log {
    param([string]$Text, [string]$Level = 'info')
    $Text = $Text -replace "`r?`n", "`r`n"
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $Text
    try { Add-Content -LiteralPath $script:LogFile -Value ('{0:yyyy-MM-dd} {1} [{2}] [{3}]' -f (Get-Date), $line, $env:USERNAME, $Level) -Encoding UTF8 } catch { }
    $rb = $script:LogBox
    if ($rb) {
        $rb.SelectionStart = $rb.TextLength
        $rb.SelectionLength = 0
        $rb.SelectionColor = switch ($Level) {
            'err'  { [Drawing.Color]::Firebrick }
            'warn' { [Drawing.Color]::DarkOrange }
            'ok'   { [Drawing.Color]::ForestGreen }
            'head' { [Drawing.Color]::Navy }
            default { [Drawing.Color]::Black }
        }
        $rb.AppendText($line + "`r`n")
        $rb.SelectionColor = $rb.ForeColor
        $rb.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Wait-Ui([double]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
}

function Show-Msg([string]$Text, [string]$Icon = 'Information', [string]$Buttons = 'OK') {
    [System.Windows.Forms.MessageBox]::Show($Text, $script:AppTitle, $Buttons, $Icon)
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} ГБ' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} МБ' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} КБ' -f ($Bytes / 1KB)) }
    return ('{0:N0} Б' -f $Bytes)
}

function Format-Span([TimeSpan]$T) {
    if ($T.TotalMinutes -ge 1) { return ('{0} мин {1} с' -f [int][Math]::Floor($T.TotalMinutes), $T.Seconds) }
    return ('{0} с' -f [int]$T.TotalSeconds)
}

function Get-ErrCode($Err) {
    $e = $Err.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    return ($e.HResult -band 0xFFFF)
}

# Файл занят другим процессом (32/33 = sharing/lock violation). -Write: проверка на запись (для lockfile браузера)
function Test-Locked([string]$Path, [switch]$Write) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $acc = if ($Write) { [IO.FileAccess]::Write } else { [IO.FileAccess]::Read }
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, $acc, [IO.FileShare]'ReadWrite, Delete')
        $fs.Close()
        return $false
    } catch {
        $code = Get-ErrCode $_
        return ($code -eq 32 -or $code -eq 33)
    }
}

function Test-Port([string]$TargetHost, [int]$Port = 445, [int]$TimeoutMs = 2500) {
    $c = New-Object Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $c.EndConnect($ar)
        return $true
    } catch { return $false }
    finally { $c.Close() }
}

function Get-Stamp { return (Get-Date -Format 'yyyy-MM-dd_HHmm') }

# ПК администратора или нет (та же функция в start.ps1, там предупреждение до ввода пароля; здесь только запись в журнал)
function Get-AdminCheck($Cfg) {
    $r = [pscustomobject]@{ Pc = $env:COMPUTERNAME; Dn = ''; AdminPc = $false; AdminUser = $false; User = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME) }
    if (-not $Cfg.AdminPcOu -and -not @($Cfg.AdminPCs | Where-Object { $_ }).Count) { $r.AdminPc = $true }   # проверка ПК не настроена
    try { $r.Dn = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine' -Name 'Distinguished-Name' -ErrorAction Stop).'Distinguished-Name' } catch { }
    if ($Cfg.AdminPcOu -and $r.Dn -and $r.Dn.EndsWith(',' + $Cfg.AdminPcOu, [StringComparison]::OrdinalIgnoreCase)) { $r.AdminPc = $true }
    if (@($Cfg.AdminPCs) -contains $env:COMPUTERNAME) { $r.AdminPc = $true }
    # Без повышения прав «Администраторы домена» в токене только «для запрета», и WindowsIdentity.Groups их не показывает,
    # поэтому SID групп берём ещё и у whoami /groups
    $sids = New-Object System.Collections.Generic.List[string]
    try { foreach ($g in [Security.Principal.WindowsIdentity]::GetCurrent().Groups) { $sids.Add($g.Value) } } catch { }
    try { foreach ($l in @(& whoami.exe /groups /fo csv /nh)) { if ($l -match '"(S-1-5-21-[\d-]+)"') { $sids.Add($Matches[1]) } } } catch { }
    foreach ($s in ($sids | Select-Object -Unique)) {
        if ($s -match '^S-1-5-21-.+-512$') { $r.AdminUser = $true; break }
        if ($s -notmatch '^S-1-5-21-') { continue }
        try { $n = ((New-Object Security.Principal.SecurityIdentifier $s).Translate([Security.Principal.NTAccount]).Value -split '\\')[-1] } catch { continue }
        if (@($Cfg.AdminGroups) -contains $n) { $r.AdminUser = $true; break }
    }
    return $r
}

# ---------------------------------------------------------------- AD (чтение)

# AD спрашиваем у DC по IP из config.psd1 (если задан), если он не ответил, то по имени домена: VPN/прокси
# на ПК администратора может подменять DNS, и DC по имени домена тогда не находится. Путь, через который AD ответил, запоминаем
function Get-AdPaths {
    $base = 'DC=' + (($script:Cfg.Domain -split '\.') -join ',DC=')
    $all = @($script:AdPath)
    if ($script:Cfg.DcIp) { $all += 'LDAP://{0}/{1}' -f $script:Cfg.DcIp, $base }
    $all += 'LDAP://{0}/{1}' -f $script:Cfg.Domain, $base
    @($all | Where-Object { $_ } | Select-Object -Unique)
}

function Find-Ad([string]$Filter, [string[]]$Props) {
    $paths = @(Get-AdPaths)
    $last = $null
    foreach ($path in $paths) {
        # Учётка окна (runas /netonly), Negotiate с подписью, как требует DC. Конструктор с одним путём:
        # $null в параметрах-строках PowerShell передал бы как пустые строки
        if (-not $script:AdRoots.ContainsKey($path)) { $script:AdRoots[$path] = New-Object DirectoryServices.DirectoryEntry($path) }
        $ds = New-Object DirectoryServices.DirectorySearcher
        $ds.SearchRoot = $script:AdRoots[$path]
        $ds.Filter = $Filter
        $ds.PageSize = 500
        foreach ($p in $Props) { [void]$ds.PropertiesToLoad.Add($p) }
        try {
            $r = @($ds.FindAll())
            if ($script:AdPath -and $script:AdPath -ne $path) { Write-Log ('   AD не ответил через {0}, работаю через {1}' -f $script:AdPath, $path) 'warn' }
            $script:AdPath = $path
            return $r
        } catch {
            $last = $_.Exception
            [void]$script:AdRoots.Remove($path)
        } finally { $ds.Dispose() }
    }
    throw ('Нет связи с AD ({0}): {1}' -f ($paths -join ', '), $(if ($last) { $last.Message } else { '' }))
}

function Get-AdProp($R, [string]$N) {
    $v = $R.Properties[$N]
    if ($null -ne $v -and $v.Count -gt 0) { $v[0] } else { $null }
}

function Get-PmUser([string]$Login) {
    if ($Login -notmatch '^[A-Za-z0-9._-]{1,64}$') { throw "Логин «$Login» не похож на логин AD (латиница, цифры, точка, подчёркивание)" }
    $r = @(Find-Ad "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$Login))" @('samaccountname', 'displayname', 'objectsid', 'useraccountcontrol'))
    if (-not $r.Count) { throw "В AD нет пользователя $Login" }
    $x = $r[0]
    $sid = (New-Object Security.Principal.SecurityIdentifier([byte[]](Get-AdProp $x 'objectsid'), 0)).Value
    [pscustomobject]@{
        Login   = [string](Get-AdProp $x 'samaccountname')
        Name    = [string](Get-AdProp $x 'displayname')
        Sid     = $sid
        Enabled = -not ([int](Get-AdProp $x 'useraccountcontrol') -band 2)
    }
}

# ---------------------------------------------------------------- ПК: имя → IP

# 198.18.0.0/15: такие адреса вместо настоящих отдают VPN/прокси-клиенты в режиме fake-ip (Clash, sing-box, Xray и т. п.)
function Test-FakeIp([string]$Ip) { return ($Ip -match '^198\.(18|19)\.') }

# IPv4 имени: у DNS контроллера домена напрямую; если он имени не знает, то у системного DNS без подменных адресов
function Resolve-PcIp([string]$Fqdn) {
    $ips = @()
    if ($script:Cfg.DcIp) {
        try {
            $ips = @(Resolve-DnsName -Name $Fqdn -Type A -Server $script:Cfg.DcIp -DnsOnly -QuickTimeout -ErrorAction Stop |
                Where-Object { [string]$_.Type -eq 'A' } | ForEach-Object { [string]$_.IPAddress })
        } catch { Write-Log ('   DNS контроллера домена ({0}) не знает {1}: {2}' -f $script:Cfg.DcIp, $Fqdn, $_.Exception.Message) 'warn' }
    }
    if (-not $ips.Count) {
        try {
            $ips = @([Net.Dns]::GetHostAddresses($Fqdn) | Where-Object { [string]$_.AddressFamily -eq 'InterNetwork' } |
                ForEach-Object { $_.ToString() } | Where-Object { -not (Test-FakeIp $_) })
        } catch { }
    }
    $ips
}

# ПК по имени: имя и FQDN из AD, все IPv4 этого имени из DNS контроллера домена (нужный выберет Test-PcAccess).
# IP принимаем как есть, имя ПК тогда узнаём у него самого
function Resolve-Pc([string]$Name) {
    $Name = $Name.Trim()
    if ($Name -match '^\d{1,3}(\.\d{1,3}){3}$') { return [pscustomobject]@{ Name = $Name; Host = $Name; Ips = @($Name); Os = ''; ByIp = $true } }
    if ($Name -notmatch '^[A-Za-z0-9-]{1,63}(\.[A-Za-z0-9.-]+)?$') { throw "Имя ПК «$Name» не похоже на имя компьютера" }
    $short = ($Name -split '\.')[0]
    $pc = [pscustomobject]@{ Name = $short.ToUpper(); Host = ''; Ips = @(); Os = ''; ByIp = $false }
    $fqdn = if ($Name -match '\.') { $Name } else { '{0}.{1}' -f $short, $script:Cfg.Domain }
    $r = @(Find-Ad "(&(objectCategory=computer)(name=$short))" @('name', 'dnshostname', 'operatingsystem'))
    if ($r.Count) {
        $pc.Name = ([string](Get-AdProp $r[0] 'name')).ToUpper()
        $pc.Os = [string](Get-AdProp $r[0] 'operatingsystem')
        $dns = [string](Get-AdProp $r[0] 'dnshostname')
        if ($dns) { $fqdn = $dns }
    } else { Write-Log "   ПК $short в AD не найден, ищу его в DNS" 'warn' }
    $pc.Ips = @(Resolve-PcIp $fqdn)
    if (-not $pc.Ips.Count) { throw ('Не нашёл IP {0} в DNS{1}: ПК давно не включался? Введите вместо имени его IP' -f $fqdn, $(if ($script:Cfg.DcIp) { ' контроллера домена (' + $script:Cfg.DcIp + ')' } else { '' })) }
    $pc.Host = $pc.Ips[0]
    return $pc
}

# ---------------------------------------------------------------- удалённый реестр ПК

function Enable-RemoteRegistry([string]$TargetHost) {
    if ($script:RrState.ContainsKey($TargetHost)) { return }
    $svc = New-Object System.ServiceProcess.ServiceController('RemoteRegistry', $TargetHost)
    try {
        $state = @{ StartType = [string]$svc.StartType; WasRunning = ($svc.Status -eq 'Running'); Changed = $false }
        if (-not $state.WasRunning) {
            if ($state.StartType -eq 'Disabled') {
                $out = & sc.exe "\\$TargetHost" config RemoteRegistry start= demand 2>&1
                if ($LASTEXITCODE -ne 0) { throw ('sc config: {0}' -f ($out -join ' ')) }
                $state.Changed = $true
            }
            $script:RrState[$TargetHost] = $state      # запомнить до запуска: вернуть как было, даже если запуск упадёт
            $svc.Start()
            $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
            Write-Log ('   служба «Удалённый реестр» на {0} включена на время работы (была: {1})' -f (Get-HostLabel $TargetHost), $state.StartType)
        }
        $script:RrState[$TargetHost] = $state
    } finally { $svc.Dispose() }
}

function Restore-RemoteRegistry {
    foreach ($k in @($script:HklmCache.Keys)) { try { $script:HklmCache[$k].Close() } catch { } }
    $script:HklmCache = @{}
    foreach ($h in @($script:RrState.Keys)) {
        $st = $script:RrState[$h]
        if ($st.WasRunning) { continue }
        try {
            $svc = New-Object System.ServiceProcess.ServiceController('RemoteRegistry', $h)
            try { if ($svc.Status -ne 'Stopped') { $svc.Stop(); $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30)) } } finally { $svc.Dispose() }
            if ($st.Changed) {
                $out = & sc.exe "\\$h" config RemoteRegistry start= disabled 2>&1
                if ($LASTEXITCODE -ne 0) { throw ('sc config: {0}' -f ($out -join ' ')) }
            }
            Write-Log ('   служба «Удалённый реестр» на {0} возвращена как была ({1}, остановлена)' -f (Get-HostLabel $h), $st.StartType)
        } catch {
            Write-Log ('   не удалось вернуть службу «Удалённый реестр» на {0}: {1}. Вернуть руками: services.msc на этом ПК' -f (Get-HostLabel $h), $_.Exception.Message) 'warn'
        }
    }
    $script:RrState = @{}
}

function Open-RemoteHklm([string]$TargetHost) {
    if ($script:HklmCache.ContainsKey($TargetHost)) { return $script:HklmCache[$TargetHost] }
    Enable-RemoteRegistry $TargetHost
    $last = $null
    for ($i = 0; $i -lt 4; $i++) {
        try {
            $k = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $TargetHost, [Microsoft.Win32.RegistryView]::Registry64)
            $script:HklmCache[$TargetHost] = $k
            return $k
        } catch { $last = $_; Wait-Ui 2 }
    }
    throw ('реестр {0} недоступен: {1}' -f (Get-HostLabel $TargetHost), $last.Exception.Message)
}

function ConvertTo-Unc([string]$TargetHost, [string]$LocalPath) {
    if ($LocalPath -match '^([A-Za-z]):\\(.*)$') { return ('\\{0}\{1}$\{2}' -f $TargetHost, $Matches[1].ToUpper(), $Matches[2].TrimEnd('\')) }
    throw "Не понимаю путь профиля «$LocalPath»"
}

# Профиль сотрудника на ПК: путь из ProfileList по SID (точно), иначе папка C:\Users\<логин> (если реестр недоступен)
function Find-UserProfile($Pc, $User) {
    $res = [pscustomobject]@{ Local = $null; Unc = $null; ByRegistry = $false; Hklm = $null; Loaded = $false }
    try {
        $hk = Open-RemoteHklm $Pc.Host
        $res.Hklm = $hk
        $k = $hk.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($User.Sid)")
        if ($k) {
            try { $p = [string]$k.GetValue('ProfileImagePath', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $k.Close() }
            $p = $p -replace '(?i)%SystemDrive%', 'C:'
            if ($p) { $res.Local = $p; $res.Unc = ConvertTo-Unc $Pc.Host $p; $res.ByRegistry = $true }
        }
        $bak = $hk.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($User.Sid).bak")
        if ($bak) { $bak.Close(); Write-Log ('   на {0} у сотрудника есть запись профиля .bak: возможно, он входил во временный профиль' -f $Pc.Name) 'warn' }
    } catch {
        Write-Log ('   {0}. Профиль ищу по папке, контейнеры КриптоПро из реестра будут пропущены' -f $_.Exception.Message) 'warn'
        $guess = '\\{0}\C$\Users\{1}' -f $Pc.Host, $User.Login
        if (Test-Path -LiteralPath $guess) { $res.Local = 'C:\Users\' + $User.Login; $res.Unc = $guess }
    }
    if ($res.Unc -and -not (Test-Path -LiteralPath $res.Unc)) {
        Write-Log ('   в реестре профиль {0}, но папки нет' -f $res.Local) 'warn'
        $res.Unc = $null
    }
    if ($res.Unc) { $res.Loaded = Test-Locked (Join-Path $res.Unc 'NTUSER.DAT') }
    return $res
}

# Имя, которое сообщает о себе ПК по адресу (NetWkstaGetInfo через SMB, «Удалённый реестр» для этого не нужен)
function Get-RemoteName([string]$TargetHost) { return [string](([PmNet]::Info($TargetHost))[0]) }

function Get-HostLabel([string]$H) {
    if ($script:HostNames.ContainsKey($H)) { return ('{0} ({1})' -f $script:HostNames[$H], $H) }
    return $H
}

# Проверки ПК: SMB 445, что по адресу отвечает именно этот ПК (запись DNS могла устареть), доступ к C$
function Test-PcAccess($Pc) {
    $alive = @($Pc.Ips | Where-Object { Test-Port $_ 445 })
    if (-not $alive.Count) {
        throw ('{0} ({1}) не отвечает по SMB (порт 445): ПК выключен, не в сети или брандмауэр на нём не пускает SMB с этого ПК' -f $Pc.Name, ($Pc.Ips -join ', '))
    }
    $chosen = $null; $unchecked = $null; $others = @()
    foreach ($ip in $alive) {
        $nm = $null
        try { $nm = Get-RemoteName $ip } catch { Write-Log ('   по адресу {0} не удалось спросить имя ПК: {1}' -f $ip, $_.Exception.Message) 'warn' }
        if (-not $nm) { if (-not $unchecked) { $unchecked = $ip }; continue }
        if ($Pc.ByIp) { $Pc.Name = $nm.ToUpper(); $chosen = $ip; break }
        if ($nm -ieq $Pc.Name) { $chosen = $ip; break }
        $others += ('{0} = {1}' -f $ip, $nm.ToUpper())
    }
    if (-not $chosen) {
        if (-not $unchecked) {
            throw ('В DNS {0} = {1}, но там отвечает другой ПК ({2}): запись DNS устарела. Введите вместо имени настоящий IP {0}' -f $Pc.Name, ($alive -join ', '), ($others -join '; '))
        }
        $chosen = $unchecked
        Write-Log ('   что по адресу {0} отвечает именно {1}, проверить не удалось' -f $chosen, $Pc.Name) 'warn'
    }
    $Pc.Host = $chosen
    $script:HostNames[$chosen] = $Pc.Name
    if (-not (Test-Path -LiteralPath ('\\{0}\C$\Windows' -f $Pc.Host))) {
        throw ('Нет доступа к \\{0}\C$ ({1}) под учёткой {2}: она не администратор на этом ПК?' -f $Pc.Host, $Pc.Name, $script:NetUser)
    }
}

# ---------------------------------------------------------------- реестр КриптоПро: чтение, запись, .reg

function Read-RegTree($Key, [string]$Rel, $Out) {
    $vals = New-Object System.Collections.Generic.List[object]
    foreach ($n in $Key.GetValueNames()) {
        $kind = $Key.GetValueKind($n)
        $data = $Key.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $d = switch ([string]$kind) {
            'Binary'      { [Convert]::ToBase64String([byte[]]$data) }
            'DWord'       { [string][uint32]([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$data), 0)) }
            'QWord'       { [string][uint64]([BitConverter]::ToUInt64([BitConverter]::GetBytes([long]$data), 0)) }
            'MultiString' { , ([string[]]$data) }
            'String'      { [string]$data }
            'ExpandString' { [string]$data }
            default       { $null }
        }
        if ($null -eq $d -and [string]$kind -notin @('String', 'ExpandString')) { Write-Log ('   значение {0}\{1} типа {2} пропущено' -f $Rel, $n, $kind) 'warn'; continue }
        $vals.Add([ordered]@{ Name = $n; Kind = [string]$kind; Data = $d })
    }
    $Out.Add([ordered]@{ Path = $Rel; Vals = $vals })
    foreach ($s in $Key.GetSubKeyNames()) {
        $sk = $Key.OpenSubKey($s)
        try { Read-RegTree $sk $(if ($Rel) { "$Rel\$s" } else { $s }) $Out } finally { $sk.Close() }
    }
}

function ConvertFrom-RegData($V) {
    switch ([string]$V.Kind) {
        'Binary'      { return , ([Convert]::FromBase64String([string]$V.Data)) }
        'DWord'       { return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32][string]$V.Data), 0) }
        'QWord'       { return [BitConverter]::ToInt64([BitConverter]::GetBytes([uint64][string]$V.Data), 0) }
        'MultiString' { return , ([string[]]@($V.Data)) }
        default       { return [string]$V.Data }
    }
}

function ConvertTo-RegHex([byte[]]$Bytes) { return (($Bytes | ForEach-Object { $_.ToString('x2') }) -join ',') }

function ConvertTo-RegText([string]$RootPath, $Entries) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('Windows Registry Editor Version 5.00')
    foreach ($e in $Entries) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine(('[{0}{1}]' -f $RootPath, $(if ($e.Path) { '\' + $e.Path } else { '' })))
        foreach ($v in $e.Vals) {
            $name = if ($v.Name) { '"' + ($v.Name -replace '\\', '\\' -replace '"', '\"') + '"' } else { '@' }
            $data = ConvertFrom-RegData $v
            $txt = switch ([string]$v.Kind) {
                'String'       { '"' + ($data -replace '\\', '\\' -replace '"', '\"') + '"' }
                'DWord'        { 'dword:' + ([uint32][string]$v.Data).ToString('x8') }
                'QWord'        { 'hex(b):' + (ConvertTo-RegHex ([BitConverter]::GetBytes([uint64][string]$v.Data))) }
                'Binary'       { 'hex:' + (ConvertTo-RegHex $data) }
                'ExpandString' { 'hex(2):' + (ConvertTo-RegHex ([Text.Encoding]::Unicode.GetBytes([string]$data + [char]0))) }
                'MultiString'  { 'hex(7):' + (ConvertTo-RegHex ([Text.Encoding]::Unicode.GetBytes((($data | ForEach-Object { $_ + [char]0 }) -join '') + [char]0))) }
            }
            [void]$sb.AppendLine($name + '=' + $txt)
        }
    }
    return $sb.ToString()
}

# Снять контейнеры «Реестр» сотрудника: keys.json для окна и keys.reg для ручного импорта
function Export-CryptoReg($Hklm, $User, [string]$Dst) {
    foreach ($tpl in $script:Cfg.CryptoProRegKeys) {
        $path = $tpl -replace '\{SID\}', $User.Sid
        $k = $Hklm.OpenSubKey($path)
        if (-not $k) { continue }
        try {
            $entries = New-Object System.Collections.Generic.List[object]
            Read-RegTree $k '' $entries
        } finally { $k.Close() }
        $names = @($entries | Where-Object { $_.Path -and $_.Path -notmatch '\\' } | ForEach-Object { $_.Path })
        if (-not $names.Count) { return [pscustomobject]@{ Count = 0; Names = @(); Path = $path } }
        New-Item -ItemType Directory -Path $Dst -Force | Out-Null
        $obj = [ordered]@{ KeyPath = $path; Sid = $User.Sid; Entries = $entries }
        [IO.File]::WriteAllText((Join-Path $Dst 'keys.json'), (ConvertTo-Json -InputObject $obj -Depth 8), (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $Dst 'keys.reg'), (ConvertTo-RegText ('HKEY_LOCAL_MACHINE\' + $path) $entries), [Text.Encoding]::Unicode)
        return [pscustomobject]@{ Count = $names.Count; Names = $names; Path = $path }
    }
    return [pscustomobject]@{ Count = 0; Names = @(); Path = '' }
}

# Развернуть контейнеры «Реестр»: существующие на ПК контейнеры с тем же именем не трогаем
function Import-CryptoReg($Hklm, $User, [string]$Src) {
    $obj = [IO.File]::ReadAllText((Join-Path $Src 'keys.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $path = [string]$obj.KeyPath
    if ($path -match '\\WOW6432Node\\' -and -not $Hklm.OpenSubKey('SOFTWARE\WOW6432Node')) { $path = $path -replace '\\WOW6432Node', '' }
    $userKeyPath = $path -replace '\\Keys$', ''
    # Сначала ветка Users\<SID> с полным доступом сотрудника: всё, что создадим ниже, его унаследует
    $aclNote = ''
    $uk = $Hklm.CreateSubKey($userKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
    try {
        $acl = $uk.GetAccessControl()
        $sidObj = New-Object Security.Principal.SecurityIdentifier($User.Sid)
        $rule = New-Object Security.AccessControl.RegistryAccessRule($sidObj, [Security.AccessControl.RegistryRights]::FullControl, [Security.AccessControl.InheritanceFlags]::ContainerInherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
        $uk.SetAccessControl($acl)
    } catch {
        $aclNote = 'права сотрудника на ветку реестра не выставлены ({0}); если КриптоПро скажет «Отказано в доступе» (0x80090010), дать сотруднику полный доступ к HKLM\{1} в regedit' -f $_.Exception.Message, $userKeyPath
    } finally { $uk.Close() }
    $base = $Hklm.CreateSubKey($path, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
    $added = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]
    try {
        $existing = @($base.GetSubKeyNames())
        $skipTop = @{}
        foreach ($e in @($obj.Entries)) {
            $rel = [string]$e.Path
            if (-not $rel) { continue }
            $top = ($rel -split '\\')[0]
            if (-not $skipTop.ContainsKey($top)) {
                $skipTop[$top] = ($existing -contains $top)
                if ($skipTop[$top]) { $skipped.Add($top) } else { $added.Add($top) }
            }
            if ($skipTop[$top]) { continue }
            $k = $base.CreateSubKey($rel, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
            try {
                foreach ($v in $e.Vals) {
                    $k.SetValue([string]$v.Name, (ConvertFrom-RegData $v), [Microsoft.Win32.RegistryValueKind]([string]$v.Kind))
                }
            } finally { $k.Close() }
        }
    } finally { $base.Close() }
    return [pscustomobject]@{ Added = @($added); Skipped = @($skipped); Path = $path; AclNote = $aclNote }
}

# ---------------------------------------------------------------- robocopy

function Format-Arg([string]$A) {
    if ($A -match '[\s"]') { return '"' + $A.TrimEnd('\') + '"' }
    return $A
}

function Read-RoboLog([string]$LogPath) {
    $r = [pscustomobject]@{ Files = 0; Copied = 0; Skipped = 0; Failed = 0; Bytes = 0; BytesCopied = 0; Errors = @() }
    if (-not (Test-Path -LiteralPath $LogPath)) { return $r }
    $lines = [IO.File]::ReadAllLines($LogPath, [Text.Encoding]::Unicode)
    $rows = New-Object System.Collections.Generic.List[object]
    $errs = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($l -match '^\s*[^\d\s:][^:]*:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$') {
            $rows.Add(@([long]$Matches[1], [long]$Matches[2], [long]$Matches[3], [long]$Matches[4], [long]$Matches[5], [long]$Matches[6]))
        } elseif ($l -match '\((0x[0-9A-Fa-f]{8})\)\s*(.*)$') {
            $t = ('{0} {1}' -f $Matches[1], $Matches[2]).Trim()
            if (-not $errs.Contains($t)) { $errs.Add($t) }
        }
    }
    # Итоговая таблица: строки «Каталогов», «Файлов», «Байт» (с /BYTES все числа целые) последние три
    if ($rows.Count -ge 3) {
        $f = $rows[$rows.Count - 2]; $b = $rows[$rows.Count - 1]
        $r.Files = $f[0]; $r.Copied = $f[1]; $r.Skipped = $f[2]; $r.Failed = $f[4]
        $r.Bytes = $b[0]; $r.BytesCopied = $b[1]
    }
    $r.Errors = @($errs)
    return $r
}

# Ошибка robocopy («0x0000007B Копирование файла \\ПК\C$\...») понятными словами. $Src/$Dst: откуда и куда копировали,
# по ним считаем, каким будет путь в месте назначения.
# Пути длиннее 260 знаков robocopy копирует сам, это не ошибка. Ошибка бывает, когда имя не принимает место назначения:
#  - NAS на Linux (Samba поверх ZFS, ext4, btrfs: TrueNAS, Synology и т. п.): имя файла или папки не длиннее 255 байт
#    в UTF-8 (русская буква = 2 байта, около 127 букв), полный путь не длиннее 1024 байт;
#  - ПК (NTFS): имя не длиннее 255 знаков.
# Long = не скопирован из-за длины имени или пути: такие окно перечисляет ещё и в итоговом сообщении
function ConvertFrom-RoboError([string]$E, [string]$Src = '', [string]$Dst = '') {
    $o = [pscustomobject]@{ Code = 0; Reason = ''; Path = ''; Shown = ''; DstPath = ''; Short = ''; Long = $false; Text = $E }
    if ($E -notmatch '^0x([0-9A-Fa-f]{8})\s*(.*)$') { return $o }
    $o.Code = [Convert]::ToInt32($Matches[1], 16) -band 0xFFFF
    $rest = $Matches[2]
    if ($rest -match '(\\\\[^\\].*|[A-Za-z]:\\.*)$') { $o.Path = $Matches[1].Trim() }
    # Путь так, как его видит Windows на самом ПК: \\10.0.0.15\C$\Users\... → C:\Users\...
    $o.Shown = $o.Path -replace '^\\\\[^\\]+\\([A-Za-z])\$(\\|$)', '$1:\'
    # Путь в месте назначения: robocopy пишет в ошибке путь источника
    $s = $Src.TrimEnd('\'); $d = $Dst.TrimEnd('\')
    $o.DstPath = if ($s -and $o.Path.StartsWith($s + '\', [StringComparison]::OrdinalIgnoreCase)) { $d + $o.Path.Substring($s.Length) } else { $o.Path }
    # Ограничения NAS считаем только для сетевого хранилища (\\сервер\шара); локальная папка или USB-диск = NTFS
    $toNas = ($d -and $script:Cfg.StoreRoot -like '\\*' -and $d.StartsWith($script:Cfg.StoreRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase))
    $u8 = New-Object Text.UTF8Encoding $false
    # самое длинное в байтах имя в пути назначения (имя файла или одной из папок)
    $parts = @($o.DstPath -split '\\' | Where-Object { $_ })
    $worst = ''; foreach ($p in $parts) { if ($u8.GetByteCount($p) -gt $u8.GetByteCount($worst)) { $worst = $p } }
    $worstB = $u8.GetByteCount($worst)
    # путь на NAS внутри шары (без \\сервер\шара), в байтах; на самом NAS к нему добавится ещё /mnt/<пул>/<шара>/
    $nasB = if ($toNas) { $u8.GetByteCount((($o.DstPath -replace '^\\\\[^\\]+\\[^\\]+', '') -replace '\\', '/')) } else { 0 }
    $isName = if ($worst -eq ($parts | Select-Object -Last 1)) { 'имя файла' } else { 'имя папки' }
    switch ($o.Code) {
        { $_ -in 3, 123, 206 } {
            if ($toNas -and $worstB -gt 255) {
                $o.Long = $true
                $o.Reason = 'имя длиннее 255 байт для NAS'
                $o.Short = ('{0} {1} знаков = {2} байт, NAS принимает до 255' -f $isName, $worst.Length, $worstB)
                $o.Text = ('не скопирован: {0} {1} знаков = {2} байт в UTF-8, а NAS (ZFS, ext4) принимает имена не длиннее 255 байт (русская буква = 2 байта, это около 127 букв): {3}' -f $isName, $worst.Length, $worstB, $o.Shown)
            } elseif ($toNas -and $nasB -gt 1000) {
                $o.Long = $true
                $o.Reason = 'путь длиннее 1024 байт для NAS'
                $o.Short = ('путь на NAS около {0} байт, NAS принимает до 1024' -f $nasB)
                $o.Text = ('не скопирован: путь на NAS около {0} байт в UTF-8, а NAS принимает путь не длиннее 1024 байт (русская буква = 2 байта): {1}' -f $nasB, $o.Shown)
            } elseif (-not $toNas -and $worst.Length -gt 255) {
                $o.Long = $true
                $o.Reason = 'имя длиннее 255 знаков'
                $o.Short = ('{0} {1} знаков, Windows принимает до 255' -f $isName, $worst.Length)
                $o.Text = ('не скопирован: {0} {1} знаков, а Windows (NTFS) принимает имена не длиннее 255 знаков: {2}' -f $isName, $worst.Length, $o.Shown)
            } elseif ($_ -eq 3) {
                $o.Reason = 'путь не найден'
                $o.Text = ('не скопирован: папка не найдена (переименовали или удалили во время копирования?): {0}' -f $o.Shown)
            } else {
                $o.Reason = 'недопустимое имя'
                $o.Text = ('не скопирован: в имени файла или папки недопустимые знаки (например, точка или пробел в конце): {0}' -f $o.Shown)
            }
            break
        }
        { $_ -in 32, 33 } { $o.Reason = 'файл открыт в программе'; $o.Text = ('не скопирован: файл открыт в программе (Word, Excel и т. п.): {0}' -f $o.Shown); break }
        5 { $o.Reason = 'нет доступа'; $o.Text = ('не скопирован: нет доступа к файлу: {0}' -f $o.Shown); break }
        112 { $o.Reason = 'нет места на диске'; $o.Text = ('не скопирован: на диске нет места: {0}' -f $o.Shown); break }
        2 { $o.Reason = 'файл удалён во время копирования'; $o.Text = ('не скопирован: файл пропал во время копирования: {0}' -f $o.Shown); break }
        { $_ -in 53, 59, 64, 121, 1231, 1236 } { $o.Reason = 'обрыв сети'; $o.Text = ('не скопирован: оборвалась связь по сети ({0}): {1}' -f $o.Code, $o.Shown); break }
        default { $o.Reason = ('ошибка {0}' -f $o.Code); $o.Text = $E }
    }
    return $o
}

# Счётчик для процента: дочитывает журнал robocopy (UTF-16) с места прошлого чтения и складывает размеры
# файлов из строк вида «<таб>  Новый файл  <таб><таб>  12345<таб>путь». Журнал robocopy держит открытым,
# поэтому читаем с FileShare.ReadWrite; если не вышло, просто пробуем в следующий раз
function Update-RoboProgress($St) {
    try {
        $fs = [IO.File]::Open($St.Log, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
    } catch { return }
    try {
        if ($fs.Length -le $St.Pos) { return }
        [void]$fs.Seek($St.Pos, [IO.SeekOrigin]::Begin)
        $n = [int]($fs.Length - $St.Pos)
        $n -= ($n % 2)
        $buf = New-Object byte[] $n
        $got = $fs.Read($buf, 0, $n)
        $got -= ($got % 2)
        $txt = [Text.Encoding]::Unicode.GetString($buf, 0, $got)
        $cut = $txt.LastIndexOf("`n")
        if ($cut -lt 0) { return }
        $St.Pos += [Text.Encoding]::Unicode.GetByteCount($txt.Substring(0, $cut + 1))
        foreach ($l in $txt.Substring(0, $cut + 1).TrimStart([char]0xFEFF) -split "`r?`n") {
            if ($l -match '^\t[^\t]*\t\t\s*(\d+)\t') { $St.Bytes += [long]$Matches[1]; $St.Files++ }
        }
    } finally { $fs.Close() }
}

function Format-Percent($St, [long]$TotalBytes, [long]$TotalFiles) {
    $pct = if ($TotalBytes -gt 0) { [Math]::Floor(100.0 * [Math]::Min($St.Bytes, $TotalBytes) / $TotalBytes) } else { 0 }
    if ($pct -gt 99) { $pct = 99 }   # 100% пишет только итог: последний файл в журнале появляется до конца копирования
    return ('{0}% ({1} из {2}, файлов {3} из {4})' -f $pct, (Format-Size $St.Bytes), (Format-Size $TotalBytes), [Math]::Min($St.Files, $TotalFiles), $TotalFiles)
}

# robocopy без окна; окно программы при этом не замирает. $OnTick вызывается примерно раз в 2 с
function Start-RoboWait([string[]]$RoboArgs, [scriptblock]$OnTick) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    $psi.Arguments = $RoboArgs -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $tick = Get-Date
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
        if ($OnTick -and ((Get-Date) - $tick).TotalSeconds -ge 2) { & $OnTick; $tick = Get-Date }
    }
    $p.WaitForExit()
    $code = $p.ExitCode
    $p.Dispose()
    return $code
}

# Сначала robocopy /L считает, сколько надо скопировать (без копирования), потом копирует.
# Процент виден в заголовке окна всё время и раз в 30 с пишется в журнал
function Invoke-Robo([string]$Src, [string]$Dst, [string]$Title, [string]$LogPath, [string[]]$Extra = @()) {
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add((Format-Arg $Src.TrimEnd('\'))); $a.Add((Format-Arg $Dst.TrimEnd('\')))
    foreach ($x in $Extra) { $a.Add((Format-Arg $x)) }
    foreach ($x in @('/R:1', '/W:1', '/NP', '/NDL', '/BYTES', '/XJ', ('/MT:{0}' -f $script:Cfg.RoboThreads))) { $a.Add($x) }
    $form = $script:MainForm
    $title0 = if ($form) { $form.Text } else { '' }
    $t0 = Get-Date
    try {
        # 1. Подсчёт
        $planLog = $LogPath -replace '\.log$', '.plan.log'
        if ($planLog -eq $LogPath) { $planLog = $LogPath + '.plan' }
        if ($form) { $form.Text = ('{0}: {1}, считаю файлы…' -f $script:AppTitle, $Title) }
        # Блоки ниже выполняются внутри Start-RoboWait и видят переменные этой функции ($Title, $st, $state…)
        $state = @{ Next = $script:ProgressLogSec }
        [void](Start-RoboWait (@($a) + @('/L', (Format-Arg ('/UNILOG:' + $planLog)))) {
            $el = (Get-Date) - $t0
            if ($el.TotalSeconds -ge $state.Next) { Write-Log ('   … {0}: считаю файлы, прошло {1}' -f $Title, (Format-Span $el)); $state.Next += $script:ProgressLogSec }
        })
        $plan = Read-RoboLog $planLog
        try { Remove-Item -LiteralPath $planLog -Force } catch { }
        $totB = [long]$plan.BytesCopied; $totF = [long]$plan.Copied

        # 2. Копирование
        $st = [pscustomobject]@{ Log = $LogPath; Pos = 0L; Bytes = 0L; Files = 0L }
        $t1 = Get-Date
        $state = @{ Next = $script:ProgressLogSec }
        $code = Start-RoboWait (@($a) + @((Format-Arg ('/UNILOG:' + $LogPath)))) {
            Update-RoboProgress $st
            $pt = if ($totB -gt 0) { Format-Percent $st $totB $totF } else { '' }
            if ($form) { $form.Text = ('{0}: {1} {2}' -f $script:AppTitle, $Title, $(if ($pt) { ($pt -split ' ')[0] } else { '…' })) }
            $el = (Get-Date) - $t1
            if ($el.TotalSeconds -ge $state.Next) {
                if ($pt) { Write-Log ('   … {0}: {1}, прошло {2}' -f $Title, $pt, (Format-Span $el)) }
                else { Write-Log ('   … {0}: копирование идёт, прошло {1}' -f $Title, (Format-Span $el)) }
                $state.Next += $script:ProgressLogSec
            }
        }
    } finally {
        if ($form) { $form.Text = $title0 }
    }
    $r = Read-RoboLog $LogPath
    $r | Add-Member -NotePropertyName Code -NotePropertyValue $code
    $r | Add-Member -NotePropertyName Time -NotePropertyValue ((Get-Date) - $t0)
    return $r
}

function New-ItemResult([string]$Key, [string]$Status, [string]$Note = '', $Robo = $null) {
    # Src: откуда в профиле сняли (у браузеров, чтобы развернуть туда же)
    $o = [ordered]@{ Key = $Key; Title = $script:Titles[$Key]; Status = $Status; Files = 0; Copied = 0; Skipped = 0; Failed = 0; Bytes = 0; Note = $Note; Src = '' }
    if ($Robo) { $o.Files = $Robo.Files; $o.Copied = $Robo.Copied; $o.Skipped = $Robo.Skipped; $o.Failed = $Robo.Failed; $o.Bytes = $Robo.Bytes }
    return $o
}

function Write-ItemLog($R, [string[]]$Errors = @()) {
    $lvl = switch ($R.Status) { 'ok' { 'ok' } 'warn' { 'warn' } 'err' { 'err' } default { 'info' } }
    $mark = switch ($R.Status) { 'ok' { 'готово' } 'warn' { 'с замечаниями' } 'err' { 'ОШИБКА' } 'none' { 'нечего переносить' } 'skip' { 'пропущено' } default { $R.Status } }
    $txt = '   {0}: {1}' -f $R.Title, $mark
    if ($R.Files -or $R.Bytes) { $txt += (', файлов {0}, {1}' -f $R.Files, (Format-Size $R.Bytes)) }
    if ($R.Note) { $txt += ('. ' + $R.Note) }
    Write-Log $txt $lvl
    $n = 0
    foreach ($e in $Errors) { if ($n -ge 8) { Write-Log ('      … и ещё {0}, полный список в журнале robocopy' -f ($Errors.Count - $n)) 'warn'; break }; Write-Log ('      ' + $e) 'warn'; $n++ }
}

# Одна папка через robocopy: результат в $Results и в журнал окна
function Invoke-RoboItem([string]$Key, [string]$Src, [string]$Dst, [string]$LogDir, [string[]]$Extra = @(), $Results) {
    if (-not (Test-Path -LiteralPath $Src)) {
        $r = New-ItemResult $Key 'none' 'папки нет'
        $Results.Add($r); Write-ItemLog $r
        return $r
    }
    $log = Join-Path $LogDir ('{0}.log' -f $Key)
    $robo = Invoke-Robo $Src $Dst $script:Titles[$Key] $log $Extra
    $errs = @($robo.Errors | ForEach-Object { ConvertFrom-RoboError $_ $Src $Dst })
    if ($robo.Code -ge 16) {
        $r = New-ItemResult $Key 'err' ('robocopy {0}: копирование не выполнено' -f $robo.Code) $robo
    } elseif ($robo.Code -ge 8 -or $robo.Failed -gt 0) {
        # Причины по-русски: «не скопировано 3 файл(ов): слишком длинный путь — 1, файл открыт в программе — 2»
        $why = @($errs | Where-Object { $_.Reason } | Group-Object Reason | ForEach-Object { '{0} — {1}' -f $_.Name, $_.Count })
        $note = if ($why.Count) { 'не скопировано {0} файл(ов): {1}' -f $robo.Failed, ($why -join ', ') } else { 'не скопировано {0} файл(ов): заняты или нет доступа' -f $robo.Failed }
        $r = New-ItemResult $Key 'warn' $note $robo
    } else {
        $note = ''
        if ($robo.Skipped -gt 0) { $note = ('пропущено {0}: уже были на месте или служебные' -f $robo.Skipped) }
        $r = New-ItemResult $Key 'ok' $note $robo
    }
    $Results.Add($r)
    Write-ItemLog $r @($errs | ForEach-Object { $_.Text })
    $long = @($errs | Where-Object { $_.Long })
    if ($long.Count) {
        foreach ($e in $long) { $script:LongPaths.Add(('{0} ({1})' -f $e.Shown, $e.Short)) }
        Write-Log '      что сделать: на ПК сотрудника сократить имя (для NAS до ~120 русских букв) и повторить эту часть; или перенести такие файлы вручную' 'warn'
    }
    return $r
}

function Get-Worst($Items) {
    $rank = @{ err = 3; warn = 2; ok = 1 }
    $w = 'ok'
    foreach ($i in $Items) {
        $s = [string]$i.Status
        if ($rank.ContainsKey($s) -and $rank[$s] -gt $rank[$w]) { $w = $s }
    }
    return $w
}

# Удалить большую папку с длинными путями (Remove-Item в PowerShell 5.1 на них падает): зеркалим пустую папку
function Remove-LongDir([string]$Path) {
    $empty = Join-Path $env:TEMP ('pm-empty-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $empty | Out-Null
    try {
        $log = Join-Path $env:TEMP ('pm-purge-' + [guid]::NewGuid().ToString('N') + '.log')
        [void](Invoke-Robo $empty $Path 'удаление' $log @('/MIR'))
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Path -Recurse -Force
    } finally { Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------- копии в хранилище (StoreRoot)

function Save-Manifest([string]$Dir, $M) {
    [IO.File]::WriteAllText((Join-Path $Dir 'manifest.json'), (ConvertTo-Json -InputObject $M -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

function Read-Manifest([string]$Dir) {
    $p = Join-Path $Dir 'manifest.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return ([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Test-Store {
    if (-not (Test-Path -LiteralPath $script:Cfg.StoreRoot)) {
        if ($script:Cfg.StoreRoot -like '\\*') {
            throw ('Нет доступа к {0} под учёткой {1}. Есть ли эта шара (StoreRoot в config.psd1) и есть ли у учётки доступ к ней?' -f $script:Cfg.StoreRoot, $script:NetUser)
        }
        throw ('Нет папки {0} (StoreRoot в config.psd1): создайте её (см. README, «Подготовка хранилища») или поправьте путь. USB-диск подключён?' -f $script:Cfg.StoreRoot)
    }
}

function Get-Copies {
    Test-Store
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($ud in @(Get-ChildItem -LiteralPath $script:Cfg.StoreRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($cd in @(Get-ChildItem -LiteralPath $ud.FullName -Directory -ErrorAction SilentlyContinue)) {
            if ($cd.Name -notmatch '^(\d{4}-\d{2}-\d{2})_(\d{4})_(.+)$') { continue }
            $pcName = $Matches[3]
            $when = [datetime]::ParseExact(($Matches[1] + ' ' + $Matches[2]), 'yyyy-MM-dd HHmm', $null)
            $m = Read-Manifest $cd.FullName
            $status = 'нет manifest.json'
            $name = ''; $size = 0; $restored = ''
            if ($m) {
                $name = [string]$m.Name
                $size = [long]$m.Bytes
                $status = switch ([string]$m.Status) { 'ok' { 'готово' } 'warn' { 'с замечаниями' } 'err' { 'с ошибками' } 'running' { 'прервано' } default { [string]$m.Status } }
                $last = @($m.Restores) | Where-Object { $_ } | Select-Object -Last 1
                if ($last) { $restored = '{0}, {1}' -f $last.PC, ([datetime]$last.Date).ToString('dd.MM HH:mm') }
            }
            $list.Add([pscustomobject]@{ Login = $ud.Name; Name = $name; Pc = $pcName; When = $when; Bytes = $size; Status = $status; Restored = $restored; Path = $cd.FullName; Manifest = $m })
        }
    }
    return @($list | Sort-Object When -Descending)
}

function Update-Grid {
    $script:Copies = @(Get-Copies)
    $g = $script:Grid
    $g.Rows.Clear()
    foreach ($c in $script:Copies) {
        $i = $g.Rows.Add($c.Login, $c.Name, $c.Pc, $c.When.ToString('dd.MM.yyyy HH:mm'), (Format-Size $c.Bytes), $c.Status, $c.Restored)
        $g.Rows[$i].Tag = $c.Path
    }
    $free = ''
    try { $free = ', свободно ' + (Format-Size ([PmDisk]::Free($script:Cfg.StoreRoot))) } catch { }
    $script:InfoLabel.Text = ('Копии: {0}{1}. Всего копий: {2}. К ПК и хранилищу окно ходит под {3}' -f $script:Cfg.StoreRoot, $free, $script:Copies.Count, $script:NetUser)
}

function Get-SelectedCopy {
    $g = $script:Grid
    if ($g.SelectedRows.Count -eq 0) { return $null }
    $path = [string]$g.SelectedRows[0].Tag
    return ($script:Copies | Where-Object { $_.Path -eq $path } | Select-Object -First 1)
}

function Remove-Copy($C) {
    Write-Log ('=== Удаление копии {0} ({1})' -f $C.Path, (Format-Size $C.Bytes)) 'head'
    Remove-LongDir $C.Path
    $parent = Split-Path $C.Path -Parent
    if (-not @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $parent -Force }
    Write-Log '   удалена' 'ok'
}

function Invoke-Cleanup {
    $days = [int]$script:Cfg.RetentionDays
    $old = @($script:Copies | Where-Object { $_.When -lt (Get-Date).AddDays(-$days) })
    if (-not $old.Count) { return }
    $txt = ($old | Select-Object -First 15 | ForEach-Object { '{0} {1} с {2}, {3}' -f $_.When.ToString('dd.MM.yyyy'), $_.Login, $_.Pc, (Format-Size $_.Bytes) }) -join "`r`n"
    if ($old.Count -gt 15) { $txt += "`r`n…" }
    $q = 'В хранилище {0} копий старше {1} дней:{2}{2}{3}{2}{2}В копиях лежат пароли браузера и подписи сотрудников. Удалить их?' -f $old.Count, $days, "`r`n", $txt
    if ((Show-Msg $q 'Question' 'YesNo') -ne 'Yes') { return }
    foreach ($c in $old) {
        try { Remove-Copy $c } catch { Write-Log ('   не удалось удалить {0}: {1}' -f $c.Path, $_.Exception.Message) 'err' }
    }
    Update-Grid
}

# ---------------------------------------------------------------- Снять с ПК

function Wait-BrowserClosed($B, [string]$UserData, [string]$PcName) {
    while (Test-BrowserRunning $B $UserData) {
        $a = Show-Msg ('У сотрудника на {0} открыт {1}. Пока он открыт, профиль браузера не скопировать.{2}{2}Попросите закрыть браузер и нажмите «Повторить». «Отмена»: перенести всё остальное без этого браузера.' -f $PcName, $B.Title, "`r`n") 'Warning' 'RetryCancel'
        if ($a -ne 'Retry') { return $false }
    }
    return $true
}

# Браузер открыт, если занят хотя бы один из его LockFiles (путь внутри UserData, можно с * и ?)
function Test-BrowserRunning($B, [string]$UserData) {
    if (-not (Test-Path -LiteralPath $UserData)) { return $false }
    foreach ($lf in $B.LockFiles) {
        $paths = if ($lf -match '[*?]') { @(Get-ChildItem -Path (Join-Path $UserData $lf) -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) } else { @(Join-Path $UserData $lf) }
        foreach ($p in $paths) { if (Test-Locked $p -Write) { return $true } }
    }
    return $false
}

# Ключи robocopy /XD и /XF; пустые списки не передаём
function Get-ExcludeArgs($Dirs, $Files) {
    $d = @($Dirs | Where-Object { $_ })
    $f = @($Files | Where-Object { $_ })
    if ($d.Count) { '/XD'; $d }
    if ($f.Count) { '/XF'; $f }
}

# Браузеры из галочек, профиль которых можно копировать: Rel = путь UserData внутри профиля, Ud = он же на ПК.
# $Manifest: при развёртывании берём путь, с которого сняли; $null: при снятии ищем первый существующий UserData.
# Пропущенные (нет на ПК, открыт) записываются в $Results
function Get-BrowserJobs($Prof, $Pc, [string[]]$Groups, $Manifest, $Results) {
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($b in @($script:Browsers | Where-Object { $Groups -contains $_.Key })) {
        $rel = $null
        if ($Manifest) {
            if (-not (Get-CopyHas $Manifest $b.Key)) { continue }
            $it = @($Manifest.Items) | Where-Object { $_.Key -eq $b.Key } | Select-Object -First 1
            $rel = [string]$it.Src
            if (-not $rel) { $rel = $b.UserData[0] }   # копии до версии 1.4
        } else {
            foreach ($c in $b.UserData) { if (Test-Path -LiteralPath (Join-Path $Prof.Unc $c)) { $rel = $c; break } }
            if (-not $rel) { $r = New-ItemResult $b.Key 'none' 'на этом ПК его нет'; $Results.Add($r); Write-ItemLog $r; continue }
        }
        $ud = Join-Path $Prof.Unc $rel
        if (-not (Wait-BrowserClosed $b $ud $Pc.Name)) {
            $Results.Add((New-ItemResult $b.Key 'skip' 'браузер был открыт'))
            Write-Log ('   {0} пропущен: открыт у сотрудника' -f $b.Title) 'warn'
            continue
        }
        $jobs.Add([pscustomobject]@{ B = $b; Rel = $rel; Ud = $ud })
    }
    return , $jobs
}

function Get-LongPathText {
    $l = $script:LongPaths
    if (-not $l.Count) { return '' }
    $n = "`r`n"
    $t = 'Не скопированы из-за слишком длинного имени, {0} шт.:{1}' -f $l.Count, $n
    foreach ($p in ($l | Select-Object -First 5)) { $t += ('• {0}{1}' -f $p, $n) }
    if ($l.Count -gt 5) { $t += ('• … и ещё {0}, все в журнале окна{1}' -f ($l.Count - 5), $n) }
    $t += 'NAS на Linux (ZFS, ext4) принимает имя файла или папки до 255 байт: русская буква занимает 2 байта, это около 127 букв. '
    $t += 'Сократите имя на ПК сотрудника и повторите, или перенесите эти файлы вручную.' + $n + $n
    return $t
}

# Снять копию. $Resolved: ПК, уже найденный и проверенный (Resolve-Pc и Test-PcAccess), для «Перенести сразу».
# Сообщение не показывает: возвращает итог (Status, Head, LongText) и копию (Path), сообщение собирает тот, кто вызвал
function Invoke-Capture([string]$Login, [string]$PcName, [string[]]$Groups, $Resolved = $null) {
    $t0 = Get-Date
    $script:LongPaths.Clear()
    Write-Log ('=== Снять с ПК: {0} с {1}' -f $Login, $PcName) 'head'
    $user = Get-PmUser $Login
    Write-Log ('   сотрудник: {0} ({1}), SID {2}{3}' -f $user.Name, $user.Login, $user.Sid, $(if (-not $user.Enabled) { ', учётка ОТКЛЮЧЕНА' } else { '' }))
    Test-Store
    $free = [PmDisk]::Free($script:Cfg.StoreRoot)
    if ($free -lt [long]$script:Cfg.MinNasFreeGB * 1GB) { throw ('В хранилище копий свободно {0}, нужно хотя бы {1} ГБ' -f (Format-Size $free), $script:Cfg.MinNasFreeGB) }
    if ($Resolved) { $pc = $Resolved }
    else {
        $pc = Resolve-Pc $PcName
        Test-PcAccess $pc
    }
    Write-Log ('   ПК {0} ({1}) {2}: доступ есть' -f $pc.Name, $pc.Host, $pc.Os)

    $results = New-Object System.Collections.Generic.List[object]
    $dir = $null; $m = $null
    try {
        $prof = Find-UserProfile $pc $user
        if (-not $prof.Unc) { throw ('На {0} нет профиля {1}: сотрудник на этом ПК не работал?' -f $pc.Name, $user.Login) }
        Write-Log ('   профиль: {0}{1}' -f $prof.Local, $(if ($prof.ByRegistry) { ' (по реестру)' } else { ' (по имени папки)' }))
        if ($prof.Loaded) {
            $q = 'Сотрудник сейчас в Windows на {0} (или профиль ещё не выгружен). Открытые у него файлы не скопируются.{1}{1}Лучше попросить его сохранить всё и выйти из Windows. Продолжить сейчас?' -f $pc.Name, "`r`n"
            if ((Show-Msg $q 'Warning' 'YesNo') -ne 'Yes') { throw 'Отменено: сотрудник в Windows' }
            Write-Log '   сотрудник в Windows: открытые файлы могут не скопироваться' 'warn'
        }

        $bJobs = Get-BrowserJobs $prof $pc $Groups $null $results

        $dir = Join-Path (Join-Path $script:Cfg.StoreRoot $user.Login) ('{0}_{1}' -f (Get-Stamp), $pc.Name)
        $logs = Join-Path $dir '_logs'
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $m = [ordered]@{
            Tool = $script:Version; Login = $user.Login; Name = $user.Name; Sid = $user.Sid
            SourcePC = $pc.Name; SourceProfile = $prof.Local; Created = (Get-Date).ToString('s'); Finished = $null
            Operator = ('{0} (окно: {1}\{2} на {3})' -f $script:NetUser, $env:USERDOMAIN, $env:USERNAME, $env:COMPUTERNAME)
            Status = 'running'; Bytes = 0; Items = $results; Restores = @()
        }
        Save-Manifest $dir $m
        Write-Log ('   копия: {0}' -f $dir)

        $fx = @(Get-ExcludeArgs @() $script:Cfg.FileExcludes)
        $base = @('/E', '/COPY:DAT', '/DCOPY:T')
        foreach ($j in $bJobs) {
            $r = Invoke-RoboItem $j.B.Key $j.Ud (Join-Path $dir $j.B.Key) $logs ($base + @(Get-ExcludeArgs $j.B.ExcludeDirs $j.B.ExcludeFiles)) $results
            $r.Src = $j.Rel
        }
        $doCrypto = $Groups -contains 'Crypto'
        if ($doCrypto -or @($bJobs | Where-Object { $_.B.Dpapi }).Count) {
            $dp = Join-Path $prof.Unc ($script:Cfg.DpapiPath -replace '\{SID\}', $user.Sid)
            [void](Invoke-RoboItem 'Dpapi' $dp (Join-Path $dir 'DPAPI') $logs @('/E', '/COPY:DAT') $results)
        }
        if ($doCrypto) {
            if ($prof.Hklm) {
                try {
                    $cr = Export-CryptoReg $prof.Hklm $user (Join-Path $dir 'CryptoPro-Reg')
                    if ($cr.Count) { $r = New-ItemResult 'CryptoReg' 'ok' ('контейнеров {0}: {1}' -f $cr.Count, ($cr.Names -join ', ')) }
                    else { $r = New-ItemResult 'CryptoReg' 'none' 'контейнеров нет' }
                } catch { $r = New-ItemResult 'CryptoReg' 'err' $_.Exception.Message }
            } else { $r = New-ItemResult 'CryptoReg' 'warn' 'реестр ПК недоступен, контейнеры из реестра не сняты' }
            $results.Add($r); Write-ItemLog $r
            [void](Invoke-RoboItem 'CryptoDir' (Join-Path $prof.Unc $script:Cfg.CryptoProDir) (Join-Path $dir 'CryptoPro-Dir') $logs $base $results)
            [void](Invoke-RoboItem 'CertsMy' (Join-Path $prof.Unc $script:Cfg.CertsMyPath) (Join-Path $dir 'Certs-My') $logs $base $results)
            [void](Invoke-RoboItem 'CertsCrypto' (Join-Path $prof.Unc $script:Cfg.CertsCryptoPath) (Join-Path $dir 'Certs-Crypto') $logs $base $results)
        }
        foreach ($f in $script:Cfg.Folders) {
            if ($Groups -notcontains $f.Key) { continue }
            [void](Invoke-RoboItem $f.Key (Join-Path $prof.Unc $f.Path) (Join-Path $dir $f.Key) $logs ($base + $fx) $results)
        }
    } finally {
        Restore-RemoteRegistry
        if ($m) {
            $m.Status = Get-Worst $results
            $sum = 0L; foreach ($i in $results) { $sum += [long]$i.Bytes }; $m.Bytes = $sum
            $m.Finished = (Get-Date).ToString('s')
            try { Save-Manifest $dir $m } catch { Write-Log ('   manifest.json не записан: ' + $_.Exception.Message) 'err' }
        }
        try { Update-Grid } catch { }
    }

    $st = Get-Worst $results
    $lvl = if ($st -eq 'ok') { 'ok' } else { 'warn' }
    Write-Log ('=== Снято: {0}, {1}, за {2}{3}' -f $user.Login, (Format-Size $m.Bytes), (Format-Span ((Get-Date) - $t0)), $(if ($st -ne 'ok') { '. Есть замечания, см. выше' } else { '' })) $lvl
    return [pscustomobject]@{
        Path     = $dir
        Status   = $st
        User     = $user
        Pc       = $pc
        Bytes    = [long]$m.Bytes
        Head     = ('Копия снята: {0} ({1}) с {2}, {3}.' -f $user.Name, $user.Login, $pc.Name, (Format-Size $m.Bytes))
        LongText = (Get-LongPathText)
    }
}

# ---------------------------------------------------------------- Развернуть на ПК

function Get-CopyHas($M, [string]$Key) {
    $i = @($M.Items) | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    return ($i -and ($i.Status -in @('ok', 'warn')))
}

# Развернуть копию. $Resolved: как у Invoke-Capture. Возвращает итог (Status, Head, LongText, Checks)
function Invoke-Restore($Copy, [string]$PcName, [string[]]$Groups, $Resolved = $null) {
    $t0 = Get-Date
    $script:LongPaths.Clear()
    $m = Read-Manifest $Copy.Path
    if (-not $m) { throw ('В копии {0} нет manifest.json: копия неполная' -f $Copy.Path) }
    Write-Log ('=== Развернуть на ПК: {0} ({1}) из копии {2} с {3} → {4}' -f $m.Login, $m.Name, ([datetime]$m.Created).ToString('dd.MM.yyyy HH:mm'), $m.SourcePC, $PcName) 'head'
    if ($m.Status -eq 'running') { Write-Log '   копия была прервана: развернётся то, что успело скопироваться' 'warn' }
    $user = Get-PmUser ([string]$m.Login)
    if ($user.Sid -ne [string]$m.Sid) { throw ('SID сотрудника в AD ({0}) не совпадает с копией ({1}): учётку пересоздавали? Пароли браузера так не перенести' -f $user.Sid, $m.Sid) }
    if ($Resolved) { $pc = $Resolved }
    else {
        $pc = Resolve-Pc $PcName
        Test-PcAccess $pc
    }
    Write-Log ('   ПК {0} ({1}) {2}: доступ есть' -f $pc.Name, $pc.Host, $pc.Os)

    $results = New-Object System.Collections.Generic.List[object]
    $src = $Copy.Path
    $stamp = Get-Stamp
    try {
        $prof = Find-UserProfile $pc $user
        if (-not $prof.Unc) { throw ('Сотрудник ещё не входил на {0}: профиля нет. Пусть войдёт в Windows один раз, потом снова «Развернуть»' -f $pc.Name) }
        Write-Log ('   профиль: {0}{1}{2}' -f $prof.Local, $(if ($prof.ByRegistry) { ' (по реестру)' } else { ' (по имени папки)' }), $(if ($prof.Loaded) { ', сотрудник сейчас в Windows' } else { '' }))

        # Место на диске нового ПК
        $need = 0L
        foreach ($i in @($m.Items)) {
            $k = [string]$i.Key
            if ($Groups -contains $k -or ($k -in $script:CryptoKeys -and $Groups -contains 'Crypto') -or $k -eq 'Dpapi') { $need += [long]$i.Bytes }
        }
        $drive = ($prof.Local.Substring(0, 1)).ToUpper()
        $freeT = [PmDisk]::Free(('\\{0}\{1}$\' -f $pc.Host, $drive))
        if ($freeT -lt $need + [long]$script:Cfg.TargetSpareGB * 1GB) {
            throw ('На {0} диск {1}: свободно {2}, а переносим {3} (+{4} ГБ запаса)' -f $pc.Name, $drive, (Format-Size $freeT), (Format-Size $need), $script:Cfg.TargetSpareGB)
        }
        Write-Log ('   на диске {0}: свободно {1}, переносим {2}' -f $drive, (Format-Size $freeT), (Format-Size $need))

        $doCrypto = ($Groups -contains 'Crypto')
        $bJobs = Get-BrowserJobs $prof $pc $Groups $m $results

        $logs = Join-Path $src ('_logs\restore_{0}_{1}' -f $stamp, $pc.Name)
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $base = @('/E', '/COPY:DAT', '/DCOPY:T')
        $keep = @('/XC', '/XN', '/XO')

        # 1. Ключи DPAPI: только новые файлы, Preferred нового ПК не трогаем
        if (($doCrypto -or @($bJobs | Where-Object { $_.B.Dpapi }).Count) -and (Get-CopyHas $m 'Dpapi')) {
            $dp = Join-Path $prof.Unc ($script:Cfg.DpapiPath -replace '\{SID\}', $user.Sid)
            [void](Invoke-RoboItem 'Dpapi' (Join-Path $src 'DPAPI') $dp $logs (@('/E', '/COPY:DAT', '/XF', 'Preferred') + $keep) $results)
        }
        # 2. Подписи
        if ($doCrypto) {
            if (Get-CopyHas $m 'CryptoReg') {
                if ($prof.Hklm) {
                    try {
                        $ir = Import-CryptoReg $prof.Hklm $user (Join-Path $src 'CryptoPro-Reg')
                        $note = 'добавлено {0}' -f $ir.Added.Count
                        if ($ir.Added.Count) { $note += (': ' + ($ir.Added -join ', ')) }
                        if ($ir.Skipped.Count) { $note += ('; уже были на ПК, не трогал: ' + ($ir.Skipped -join ', ')) }
                        if ($ir.AclNote) { $note += ('; ' + $ir.AclNote) }
                        $r = New-ItemResult 'CryptoReg' $(if ($ir.Skipped.Count -or $ir.AclNote) { 'warn' } else { 'ok' }) $note
                    } catch { $r = New-ItemResult 'CryptoReg' 'err' $_.Exception.Message }
                } else { $r = New-ItemResult 'CryptoReg' 'err' 'реестр ПК недоступен. Можно импортировать руками CryptoPro-Reg\keys.reg на новом ПК от администратора' }
                $results.Add($r); Write-ItemLog $r
            }
            foreach ($pair in @(@('CryptoDir', 'CryptoPro-Dir', $script:Cfg.CryptoProDir), @('CertsMy', 'Certs-My', $script:Cfg.CertsMyPath), @('CertsCrypto', 'Certs-Crypto', $script:Cfg.CertsCryptoPath))) {
                if (-not (Get-CopyHas $m $pair[0])) { continue }
                [void](Invoke-RoboItem $pair[0] (Join-Path $src $pair[1]) (Join-Path $prof.Unc $pair[2]) $logs ($base + $keep) $results)
            }
            $hasCp = Test-Path -LiteralPath (ConvertTo-Unc $pc.Host $script:Cfg.CryptoProPc)
            if (-not $hasCp -and ((Get-CopyHas $m 'CryptoReg') -or (Get-CopyHas $m 'CryptoDir'))) {
                Write-Log ('   на {0} не найден КриптоПро CSP ({1}): контейнеры на месте, но без КриптоПро и его лицензии подпись не заработает' -f $pc.Name, $script:Cfg.CryptoProPc) 'warn'
            }
        }
        # 3. Браузеры: прежний профиль нового ПК (если был) в сторону, на его место профиль из копии
        foreach ($j in $bJobs) {
            $b = $j.B; $ud = $j.Ud
            $moved = ''
            $ok = $true
            if (Test-Path -LiteralPath $ud) {
                $bakName = (Split-Path $ud -Leaf) + '.old-' + $stamp
                try { Rename-Item -LiteralPath $ud -NewName $bakName; $moved = $bakName }
                catch {
                    $ok = $false
                    $r = New-ItemResult $b.Key 'err' ('не удалось убрать в сторону прежний профиль браузера на новом ПК (занят?): ' + $_.Exception.Message)
                    $results.Add($r); Write-ItemLog $r
                }
            }
            if ($ok) {
                $r = Invoke-RoboItem $b.Key (Join-Path $src $b.Key) $ud $logs $base $results
                $r.Src = $j.Rel
                if ($moved) { $r.Note = (($r.Note, ('прежний профиль браузера нового ПК лежит рядом: ' + $moved)) | Where-Object { $_ }) -join '; '; Write-Log ('      прежний профиль браузера на ПК переименован в «{0}»' -f $moved) }
            }
            if ($b.Exe.Count) {
                $exe = $false
                foreach ($e in $b.Exe) {
                    $p = if ($e -match '^[A-Za-z]:\\') { ConvertTo-Unc $pc.Host $e } else { Join-Path $prof.Unc $e }
                    if (Test-Path -LiteralPath $p) { $exe = $true; break }
                }
                if (-not $exe) { Write-Log ('   на {0} не найден {1}: установите его, профиль уже на месте' -f $pc.Name, $b.Title) 'warn' }
            }
        }
        # 4. Папки: файлы, которые на новом ПК новее, не перезаписываем
        $fx = @(Get-ExcludeArgs @() $script:Cfg.FileExcludes)
        foreach ($f in $script:Cfg.Folders) {
            if ($Groups -notcontains $f.Key -or -not (Get-CopyHas $m $f.Key)) { continue }
            [void](Invoke-RoboItem $f.Key (Join-Path $src $f.Key) (Join-Path $prof.Unc $f.Path) $logs ($base + @('/XO') + $fx) $results)
        }
    } finally {
        Restore-RemoteRegistry
        $rec = [ordered]@{ PC = $pc.Name; Date = (Get-Date).ToString('s'); Operator = $script:NetUser; Status = (Get-Worst $results); Items = $results }
        try {
            $m2 = Read-Manifest $src
            if ($m2) {
                $all = @(@($m2.Restores) | Where-Object { $_ }) + @($rec)
                if ($m2.PSObject.Properties['Restores']) { $m2.Restores = $all } else { $m2 | Add-Member -NotePropertyName Restores -NotePropertyValue $all }
                Save-Manifest $src $m2
            }
        } catch { Write-Log ('   запись о развёртывании в manifest.json не сохранена: ' + $_.Exception.Message) 'warn' }
        try { Update-Grid } catch { }
    }

    $st = Get-Worst $results
    Write-Log ('=== Развёрнуто: {0} на {1} за {2}{3}' -f $user.Login, $pc.Name, (Format-Span ((Get-Date) - $t0)), $(if ($st -ne 'ok') { '. Есть замечания, см. выше' } else { '' })) $(if ($st -eq 'ok') { 'ok' } else { 'warn' })
    $n = "`r`n"
    $txt = ''
    $done = @{}
    foreach ($i in $results) { if ($i.Status -in @('ok', 'warn')) { $done[[string]$i.Key] = $true } }
    $checks = New-Object System.Collections.Generic.List[string]
    $fl = @($script:Cfg.Folders | Where-Object { $done.ContainsKey($_.Key) } | ForEach-Object { $_.Title })
    if ($fl.Count) { $checks.Add(($fl -join ', ') + ': файлы на месте.') }
    $doneB = @($script:Browsers | Where-Object { $done.ContainsKey($_.Key) })
    foreach ($b in $doneB) {
        $t = '{0}: закладки и вкладки на месте, сохранённые пароли открываются (при просмотре Windows может спросить пароль сотрудника).' -f $b.Title
        if ($b.Note) { $t += ' ' + $b.Note }
        $checks.Add($t)
    }
    if ($done.ContainsKey('CryptoReg') -or $done.ContainsKey('CryptoDir') -or $done.ContainsKey('CertsMy')) { $checks.Add('КриптоПро: Инструменты КриптоПро → Контейнеры: подписи видны, сертификат открывается. Лицензия КриптоПро на новом ПК своя.') }
    if ($checks.Count) {
        $txt += 'Проверить с сотрудником:' + $n
        for ($j = 0; $j -lt $checks.Count; $j++) { $txt += ('{0}. {1}' -f ($j + 1), $checks[$j]) + $n }
    }
    if ($doneB.Count) { $txt += $n + ('Если пароли не открылись: экспорт паролей в CSV на старом ПК и импорт на новом. Если браузер был открыт во время переноса, закрыть и открыть. Копия хранится {0} дней.' -f $script:Cfg.RetentionDays) }
    return [pscustomobject]@{
        Status   = $st
        User     = $user
        Pc       = $pc
        Head     = ('Готово: {0} ({1}) на {2}.' -f $user.Name, $user.Login, $pc.Name)
        LongText = (Get-LongPathText)
        Checks   = $txt
    }
}

# ---------------------------------------------------------------- Перенести сразу

# Снять со старого ПК и сразу развернуть на новом. Оба ПК проверяем до снятия: без профиля сотрудника
# на новом ПК развернуть некуда, и снимать копию тогда незачем
function Invoke-Move([string]$Login, [string]$OldPc, [string]$NewPc, [string[]]$Groups) {
    $t0 = Get-Date
    Write-Log ('=== Перенести сразу: {0} с {1} на {2}' -f $Login, $OldPc, $NewPc) 'head'
    $user = Get-PmUser $Login
    $pcOld = Resolve-Pc $OldPc
    Test-PcAccess $pcOld
    $pcNew = Resolve-Pc $NewPc
    Test-PcAccess $pcNew
    if ($pcOld.Host -eq $pcNew.Host -or $pcOld.Name -ieq $pcNew.Name) {
        throw ('Старый и новый ПК: один и тот же компьютер ({0}). Чтобы вернуть данные на тот же ПК (например, после переустановки Windows), снимите копию кнопкой «Снять с ПК», а потом «Развернуть на ПК»' -f $pcNew.Name)
    }
    try { $profNew = Find-UserProfile $pcNew $user } finally { Restore-RemoteRegistry }
    if (-not $profNew.Unc) { throw ('Сотрудник ещё не входил на {0}: профиля нет. Пусть войдёт в Windows один раз, потом снова «Перенести сразу». Копия ещё не снималась' -f $pcNew.Name) }
    Write-Log ('   новый ПК {0} ({1}): доступ есть, профиль {2}' -f $pcNew.Name, $pcNew.Host, $profNew.Local)

    $cap = Invoke-Capture $Login $OldPc $Groups $pcOld
    try { $res = Invoke-Restore ([pscustomobject]@{ Path = $cap.Path }) $NewPc $Groups $pcNew }
    catch {
        throw ('Копия снята, но развернуть на {0} не удалось: {1}{2}{2}Копия лежит в хранилище: когда причина будет устранена, выберите её в списке и нажмите «Развернуть на ПК».' -f $pcNew.Name, $_.Exception.Message, "`r`n")
    }
    $st = Get-Worst @($cap, $res)
    $span = Format-Span ((Get-Date) - $t0)
    Write-Log ('=== Перенесено: {0} с {1} на {2}, {3}, за {4}' -f $user.Login, $pcOld.Name, $pcNew.Name, (Format-Size $cap.Bytes), $span) $(if ($st -eq 'ok') { 'ok' } else { 'warn' })
    return [pscustomobject]@{
        Status   = $st
        Head     = ('Перенесено: {0} ({1}) с {2} на {3}, {4} за {5}.' -f $user.Name, $user.Login, $pcOld.Name, $pcNew.Name, (Format-Size $cap.Bytes), $span)
        LongText = ($cap.LongText + $res.LongText)
        Checks   = $res.Checks
    }
}

# Итоговое сообщение: заголовок, замечания, не скопированные из-за длинного имени, что проверить, что дальше
function Show-Result($R, [string]$Tail = '') {
    $n = "`r`n"
    $txt = $R.Head + $n + $n
    if ($R.Status -ne 'ok') { $txt += 'Есть замечания: см. журнал в окне.' + $n + $n }
    $txt += $R.LongText
    if ($R.PSObject.Properties['Checks'] -and $R.Checks) { $txt += $R.Checks }
    if ($Tail) { $txt += $Tail }
    [void](Show-Msg $txt.TrimEnd() $(if ($R.Status -eq 'ok') { 'Information' } else { 'Warning' }))
}

# ---------------------------------------------------------------- окна

function New-Label($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W = 420) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $Text; $l.Left = $X; $l.Top = $Y; $l.Width = $W; $l.AutoSize = $false; $l.Height = 18
    $Parent.Controls.Add($l)
    return $l
}

function New-Text($Parent, [int]$X, [int]$Y, [int]$W = 220, [string]$Text = '') {
    $t = New-Object Windows.Forms.TextBox
    $t.Left = $X; $t.Top = $Y; $t.Width = $W; $t.Text = $Text
    $Parent.Controls.Add($t)
    return $t
}

function New-Check($Parent, [string]$Text, [int]$X, [int]$Y, [bool]$Checked = $true) {
    $c = New-Object Windows.Forms.CheckBox
    $c.Text = $Text; $c.Left = $X; $c.Top = $Y; $c.Width = 400; $c.Checked = $Checked
    $Parent.Controls.Add($c)
    return $c
}

function New-Dialog([string]$Title, [int]$W, [int]$H) {
    $f = New-Object Windows.Forms.Form
    $f.Text = $Title; $f.ClientSize = New-Object Drawing.Size($W, $H)
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterParent'; $f.Font = New-Object Drawing.Font('Segoe UI', 9)
    return $f
}

function Add-DialogButtons($F, [string]$OkText, [int]$Y) {
    $ok = New-Object Windows.Forms.Button
    $ok.Text = $OkText; $ok.Width = 120; $ok.Height = 30; $ok.Left = $F.ClientSize.Width - 260; $ok.Top = $Y
    $ok.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Отмена'; $cancel.Width = 120; $cancel.Height = 30; $cancel.Left = $F.ClientSize.Width - 132; $cancel.Top = $Y
    $cancel.DialogResult = 'Cancel'
    $F.Controls.Add($ok); $F.Controls.Add($cancel)
    $F.AcceptButton = $ok; $F.CancelButton = $cancel
    return $ok
}

# Галочки «что переносить»: папки и браузеры из config.psd1, затем подписи (если включены).
# Checks: Key → CheckBox по порядку; Bottom: Y под последней галочкой
function Add-GroupChecks($F, [int]$Y) {
    $checks = [ordered]@{}
    foreach ($fd in $script:Cfg.Folders) { $checks[[string]$fd.Key] = New-Check $F ([string]$fd.Title) 24 $Y; $Y += 22 }
    foreach ($b in $script:Browsers) { $checks[$b.Key] = New-Check $F ('{0}: закладки, пароли, вкладки' -f $b.Title) 24 $Y; $Y += 22 }
    if ($script:Cfg.EnableCryptoPro) { $checks['Crypto'] = New-Check $F 'Подписи КриптоПро и личные сертификаты' 24 $Y; $Y += 22 }
    return [pscustomobject]@{ Checks = $checks; Bottom = $Y }
}

function Get-GroupChecks($Checks) {
    return @($Checks.Keys | Where-Object { $Checks[$_].Checked -and $Checks[$_].Enabled })
}

function Show-CaptureDialog {
    $f = New-Dialog 'Снять с ПК: данные сотрудника в хранилище' 460 330
    [void](New-Label $f 'Логин сотрудника в AD (например, ivanov_ii):' 12 12)
    $tLogin = New-Text $f 12 32
    [void](New-Label $f 'Старый ПК: имя (например, PC-042) или IP:' 12 66)
    $tPc = New-Text $f 12 86
    [void](New-Label $f 'Что снять:' 12 122)
    $gc = Add-GroupChecks $f 142
    $checks = $gc.Checks
    $f.ClientSize = New-Object Drawing.Size(460, ($gc.Bottom + 78))
    $ok = Add-DialogButtons $f 'Снять' ($gc.Bottom + 32)
    $st = @{}
    $ok.Add_Click({
        $err = ''
        if ($tLogin.Text.Trim() -notmatch '^[A-Za-z0-9._-]{1,64}$') { $err = 'Введите логин сотрудника (латиницей, как в AD).' }
        elseif (-not $tPc.Text.Trim()) { $err = 'Введите имя старого ПК.' }
        elseif (-not (Get-GroupChecks $checks).Count) { $err = 'Отметьте, что снять.' }
        if ($err) { [void](Show-Msg $err 'Warning'); $f.DialogResult = 'None'; return }
        $st.Login = $tLogin.Text.Trim(); $st.Pc = $tPc.Text.Trim(); $st.Groups = Get-GroupChecks $checks
    })
    if ($f.ShowDialog($script:MainForm) -ne 'OK') { return }
    $f.Dispose()
    $r = Invoke-Capture $st.Login $st.Pc $st.Groups
    Show-Result $r 'Дальше: сотрудник один раз входит в Windows на новом ПК, потом в этом окне «Развернуть на ПК».'
}

function Show-RestoreDialog {
    $sel = Get-SelectedCopy
    $f = New-Dialog 'Развернуть на ПК: данные сотрудника из копии' 520 380
    [void](New-Label $f 'Логин сотрудника:' 12 12)
    $tLogin = New-Text $f 12 32 220 $(if ($sel) { $sel.Login } else { '' })
    $bFind = New-Object Windows.Forms.Button
    $bFind.Text = 'Найти копии'; $bFind.Left = 240; $bFind.Top = 30; $bFind.Width = 110; $bFind.Height = 26
    $f.Controls.Add($bFind)
    [void](New-Label $f 'Копия (самая свежая сверху):' 12 66)
    $cb = New-Object Windows.Forms.ComboBox
    $cb.Left = 12; $cb.Top = 86; $cb.Width = 490; $cb.DropDownStyle = 'DropDownList'
    $f.Controls.Add($cb)
    [void](New-Label $f 'Новый ПК: имя или IP (сотрудник уже входил на него):' 12 120 490)
    $tPc = New-Text $f 12 140
    [void](New-Label $f 'Что развернуть (серое: этого нет в копии):' 12 176)
    $gc = Add-GroupChecks $f 196
    $checks = $gc.Checks
    $f.ClientSize = New-Object Drawing.Size(520, ($gc.Bottom + 74))
    $ok = Add-DialogButtons $f 'Развернуть' ($gc.Bottom + 28)
    $st = @{ List = @() }

    $fill = {
        $cb.Items.Clear()
        $login = $tLogin.Text.Trim()
        $st.List = @($script:Copies | Where-Object { $_.Login -eq $login })
        foreach ($c in $st.List) { [void]$cb.Items.Add(('{0}  с {1},  {2},  {3}{4}' -f $c.When.ToString('dd.MM.yyyy HH:mm'), $c.Pc, (Format-Size $c.Bytes), $c.Status, $(if ($c.Restored) { ',  уже разворачивали: ' + $c.Restored } else { '' }))) }
        if ($cb.Items.Count) {
            $idx = 0
            if ($sel) { for ($i = 0; $i -lt $st.List.Count; $i++) { if ($st.List[$i].Path -eq $sel.Path) { $idx = $i } } }
            $cb.SelectedIndex = $idx
        }
    }
    $bFind.Add_Click({ & $fill; if (-not $cb.Items.Count) { [void](Show-Msg ('Копий для «{0}» в хранилище нет.' -f $tLogin.Text.Trim()) 'Warning') } })
    $cb.Add_SelectedIndexChanged({
        $c = $st.List[$cb.SelectedIndex]
        $m = $c.Manifest
        foreach ($k in @($checks.Keys)) {
            $has = $false
            if ($m) {
                if ($k -eq 'Crypto') { foreach ($ck in $script:CryptoKeys) { if (Get-CopyHas $m $ck) { $has = $true } } }
                else { $has = Get-CopyHas $m $k }
            }
            $checks[$k].Enabled = $has
            $checks[$k].Checked = $has
        }
    })
    $ok.Add_Click({
        $err = ''
        if ($cb.SelectedIndex -lt 0) { $err = 'Выберите копию: введите логин и нажмите «Найти копии».' }
        elseif (-not $tPc.Text.Trim()) { $err = 'Введите имя нового ПК.' }
        elseif (-not (Get-GroupChecks $checks).Count) { $err = 'Отметьте, что развернуть.' }
        if ($err) { [void](Show-Msg $err 'Warning'); $f.DialogResult = 'None'; return }
        $c = $st.List[$cb.SelectedIndex]
        if ($tPc.Text.Trim() -ieq $c.Pc) {
            if ((Show-Msg ('Копия снята с этого же ПК ({0}). Разворачивать на него же?' -f $c.Pc) 'Question' 'YesNo') -ne 'Yes') { $f.DialogResult = 'None'; return }
        }
        $st.Copy = $c; $st.Pc = $tPc.Text.Trim(); $st.Groups = Get-GroupChecks $checks
    })
    & $fill
    if ($f.ShowDialog($script:MainForm) -ne 'OK') { return }
    $f.Dispose()
    $r = Invoke-Restore $st.Copy $st.Pc $st.Groups
    Show-Result $r
}

function Show-MoveDialog {
    $f = New-Dialog 'Перенести сразу: со старого ПК на новый' 460 360
    [void](New-Label $f 'Логин сотрудника в AD (например, ivanov_ii):' 12 12)
    $tLogin = New-Text $f 12 32
    [void](New-Label $f 'Старый ПК: имя (например, PC-042) или IP:' 12 66)
    $tOld = New-Text $f 12 86
    [void](New-Label $f 'Новый ПК: имя или IP (сотрудник уже входил на него):' 12 120)
    $tNew = New-Text $f 12 140
    [void](New-Label $f 'Что перенести:' 12 176)
    $gc = Add-GroupChecks $f 196
    $checks = $gc.Checks
    $f.ClientSize = New-Object Drawing.Size(460, ($gc.Bottom + 78))
    $ok = Add-DialogButtons $f 'Перенести' ($gc.Bottom + 32)
    $st = @{}
    $ok.Add_Click({
        $err = ''
        if ($tLogin.Text.Trim() -notmatch '^[A-Za-z0-9._-]{1,64}$') { $err = 'Введите логин сотрудника (латиницей, как в AD).' }
        elseif (-not $tOld.Text.Trim()) { $err = 'Введите имя старого ПК.' }
        elseif (-not $tNew.Text.Trim()) { $err = 'Введите имя нового ПК.' }
        elseif ($tOld.Text.Trim() -ieq $tNew.Text.Trim()) { $err = 'Старый и новый ПК совпадают. Чтобы вернуть данные на тот же ПК, используйте «Снять с ПК» и «Развернуть на ПК».' }
        elseif (-not (Get-GroupChecks $checks).Count) { $err = 'Отметьте, что перенести.' }
        if ($err) { [void](Show-Msg $err 'Warning'); $f.DialogResult = 'None'; return }
        $st.Login = $tLogin.Text.Trim(); $st.Old = $tOld.Text.Trim(); $st.New = $tNew.Text.Trim(); $st.Groups = Get-GroupChecks $checks
    })
    if ($f.ShowDialog($script:MainForm) -ne 'OK') { $f.Dispose(); return }
    $f.Dispose()
    $r = Invoke-Move $st.Login $st.Old $st.New $st.Groups
    Show-Result $r
}

function Show-CopyDetails {
    $c = Get-SelectedCopy
    if (-not $c) { throw 'Выберите копию в списке' }
    $m = $c.Manifest
    Write-Log ('=== Копия {0}' -f $c.Path) 'head'
    if (-not $m) { Write-Log '   manifest.json нет или не читается' 'warn'; return }
    Write-Log ('   {0} ({1}), снята с {2} {3}, оператор {4}, итог: {5}, {6}' -f $m.Name, $m.Login, $m.SourcePC, ([datetime]$m.Created).ToString('dd.MM.yyyy HH:mm'), $m.Operator, $c.Status, (Format-Size $m.Bytes))
    foreach ($i in @($m.Items)) { Write-ItemLog $i }
    foreach ($r in @($m.Restores | Where-Object { $_ })) {
        Write-Log ('   развёрнута на {0} {1}, {2}, итог: {3}' -f $r.PC, ([datetime]$r.Date).ToString('dd.MM.yyyy HH:mm'), $r.Operator, $r.Status)
        foreach ($i in @($r.Items)) { Write-ItemLog $i }
    }
}

function Set-Busy([bool]$On) {
    $script:Busy = $On
    foreach ($b in $script:Buttons) { $b.Enabled = -not $On }
    $script:MainForm.Cursor = if ($On) { [Windows.Forms.Cursors]::WaitCursor } else { [Windows.Forms.Cursors]::Default }
}

function Invoke-Guarded([scriptblock]$Action) {
    if ($script:Busy) { return }
    Set-Busy $true
    try { & $Action }
    catch {
        Write-Log ('ОШИБКА: ' + $_.Exception.Message) 'err'
        [void](Show-Msg ($_.Exception.Message + "`r`n`r`nЖурнал: $($script:LogFile)") 'Error')
    }
    finally { Set-Busy $false }
}

function New-Btn([string]$Text, [int]$Width, [scriptblock]$OnClick) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text; $b.Width = $Width; $b.Height = 30
    $b.Add_Click($OnClick)
    $script:Buttons += $b
    $b
}

if ($NoGui) { return }

try {
    $form = New-Object Windows.Forms.Form
    $script:MainForm = $form
    $form.Text = 'Перенос профиля сотрудника на другой ПК'
    $form.ClientSize = New-Object Drawing.Size(1100, 680)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)

    $top = New-Object Windows.Forms.FlowLayoutPanel
    $top.Dock = 'Top'; $top.AutoSize = $true; $top.AutoSizeMode = 'GrowAndShrink'; $top.WrapContents = $true
    $top.Padding = New-Object Windows.Forms.Padding(6, 6, 6, 0)
    $btns = @(
        (New-Btn 'Перенести сразу…' 135 { Invoke-Guarded { Show-MoveDialog } })
        (New-Btn 'Снять с ПК…' 110 { Invoke-Guarded { Show-CaptureDialog } })
        (New-Btn 'Развернуть на ПК…' 140 { Invoke-Guarded { Show-RestoreDialog } })
        (New-Btn 'Подробно' 90 { Invoke-Guarded { Show-CopyDetails } })
        (New-Btn 'Удалить копию' 115 { Invoke-Guarded {
            $c = Get-SelectedCopy
            if (-not $c) { throw 'Выберите копию в списке' }
            if ((Show-Msg ('Удалить копию {0} ({1}) с {2} от {3}, {4}?{5}{5}Вернуть её будет нельзя (разве что из снимков или теневых копий хранилища).' -f $c.Name, $c.Login, $c.Pc, $c.When.ToString('dd.MM.yyyy HH:mm'), (Format-Size $c.Bytes), "`r`n") 'Warning' 'YesNo') -ne 'Yes') { return }
            Remove-Copy $c
            Update-Grid
        } })
        (New-Btn 'Обновить список' 120 { Invoke-Guarded { Update-Grid } })
        (New-Btn 'Инструкция' 95 { Start-Process notepad.exe -ArgumentList ('"{0}"' -f (Join-Path $script:Root 'README.md')) })
        (New-Btn 'Журналы' 85 { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:LogDir) })
    )
    $top.Controls.AddRange([Windows.Forms.Control[]]$btns)

    $info = New-Object Windows.Forms.Label
    $info.Dock = 'Top'; $info.Height = 24; $info.Padding = New-Object Windows.Forms.Padding(8, 4, 8, 0)
    $info.Text = 'Чтение копий…'
    $script:InfoLabel = $info

    $split = New-Object Windows.Forms.SplitContainer
    $split.Dock = 'Fill'; $split.Orientation = 'Horizontal'

    $grid = New-Object Windows.Forms.DataGridView
    $grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $false; $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'; $grid.BackgroundColor = [Drawing.SystemColors]::Window
    foreach ($c in @(@('Login', 'Сотрудник', 80), @('Name', 'ФИО', 150), @('Pc', 'Снято с ПК', 90), @('When', 'Когда', 85), @('Size', 'Размер', 60), @('Status', 'Итог', 80), @('Restored', 'Развёрнуто на', 120))) {
        $i = $grid.Columns.Add($c[0], $c[1])
        $grid.Columns[$i].FillWeight = $c[2]
    }
    $script:Grid = $grid
    $split.Panel1.Controls.Add($grid)

    $log = New-Object Windows.Forms.RichTextBox
    $log.Dock = 'Fill'; $log.ReadOnly = $true; $log.Font = New-Object Drawing.Font('Consolas', 9); $log.BackColor = [Drawing.SystemColors]::Window
    $script:LogBox = $log
    $split.Panel2.Controls.Add($log)

    $form.Controls.Add($split)
    $form.Controls.Add($info)
    $form.Controls.Add($top)

    $form.Add_Shown({
        $split.SplitterDistance = 260
        Write-Log ('Окно «Перенос профиля» ({0}): {1}\{2} на {3}, к ПК и хранилищу под {4}, журнал {5}' -f $script:Version, $env:USERDOMAIN, $env:USERNAME, $env:COMPUTERNAME, $script:NetUser, $script:LogFile)
        $chk = Get-AdminCheck $script:Cfg
        if (-not $chk.AdminPc -or -not $chk.AdminUser) {
            $why = @()
            if (-not $chk.AdminPc) { $why += ('{0} не ПК администратора' -f $chk.Pc) }
            if (-not $chk.AdminUser) { $why += ('{0} не администратор' -f $chk.User) }
            Write-Log ('   окно запущено не на ПК администратора: {0}. Пароль администратора домена введён здесь' -f ($why -join ', ')) 'warn'
        }
        Invoke-Guarded { Update-Grid; Invoke-Cleanup }
    })
    $form.Add_FormClosing({
        param($s, $e)
        if ($script:Busy) {
            if ((Show-Msg 'Идёт перенос. Закрыть окно всё равно? Копирование прервётся на середине, его можно будет повторить.' 'Warning' 'YesNo') -ne 'Yes') { $e.Cancel = $true }
        }
    })
    [void]$form.ShowDialog()
}
catch {
    [System.Windows.Forms.MessageBox]::Show("Окно «Перенос профиля» не запустилось:`r`n$($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)", 'Перенос профиля', 'OK', 'Error') | Out-Null
}
