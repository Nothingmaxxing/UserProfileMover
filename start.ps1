# Запуск окна «Перенос профиля».
# Спрашивает доменную учётку администратора ПК, проверяет пароль в AD и запускает окно так,
# чтобы к ПК и к сетевому хранилищу оно ходило под этой учёткой, а на этом ПК работало под вашей (как runas /netonly).
# Пароль никуда не пишется. Ошибку запуска показывает окном, а не молча.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.DirectoryServices.AccountManagement

# Язык: такие же T и Set-Language в profile-move.ps1 (там описание)
$script:Tr = @{}
$script:Lang = 'ru'
function T([string]$Text) {
    if (-not $script:Tr.Count) { return $Text }
    $k = $Text.TrimStart(' ')
    $v = $script:Tr[$k]
    if ($null -eq $v) { return $Text }
    return $Text.Substring(0, $Text.Length - $k.Length) + $v
}
function Set-Language([string]$Lang, [string]$Root) {
    if (-not $Lang -or $Lang -eq 'auto') {
        $Lang = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'ru' -or (Get-Culture).TwoLetterISOLanguageName -eq 'ru') { 'ru' } else { 'en' }
    }
    $script:Lang = 'ru'
    $script:Tr = @{}
    $f = Join-Path $Root ('lang\{0}.psd1' -f $Lang)
    if ($Lang -ne 'ru' -and $Lang -match '^[a-z]{2}$' -and (Test-Path -LiteralPath $f)) {
        $script:Tr = Import-PowerShellDataFile -LiteralPath $f
        $script:Lang = $Lang
    }
    $ru = ($script:Lang -eq 'ru')
    $script:DateFmt = if ($ru) { 'dd.MM.yyyy HH:mm' } else { 'yyyy-MM-dd HH:mm' }
    $script:DayFmt = if ($ru) { 'dd.MM.yyyy' } else { 'yyyy-MM-dd' }
    $script:ShortFmt = if ($ru) { 'dd.MM HH:mm' } else { 'MM-dd HH:mm' }
}
try { Set-Language 'auto' $PSScriptRoot } catch { Set-Language 'ru' $PSScriptRoot }

function Show-StartError([string]$Text) {
    [void][System.Windows.Forms.MessageBox]::Show($Text, (T 'Перенос профиля'), 'OK', 'Error')
}

# Настройки: defaults.psd1 (всё по умолчанию, при обновлении заменяется), поверх него config.psd1 (своё).
# Folders и Browsers в config.psd1: ключи из defaults.psd1 ('Desktop', 'Chrome') и свои блоки @{ Key = ... }; блок
# с ключом из defaults.psd1 меняет только указанные в нём поля. Нет списка в config.psd1: всё, кроме Enabled = $false.
# Неизвестная настройка в config.psd1 (опечатка) = ошибка. Такие же Merge-Config и Read-Config в profile-move.ps1
function Merge-Config($Defaults, $Own) {
    $legacy = @('YandexPath', 'EnableYandex', 'YandexExcludeDirs', 'YandexExcludeFiles', 'YandexExe')   # config.psd1 до 1.4
    foreach ($k in @($Own.Keys)) {
        if (-not $Defaults.ContainsKey($k) -and $legacy -notcontains $k) { throw ((T 'неизвестная настройка «{0}» (опечатка?). Все настройки с пояснениями: defaults.psd1') -f $k) }
    }
    $cfg = $Defaults.Clone()
    foreach ($k in @($Own.Keys)) { $cfg[$k] = $Own[$k] }
    foreach ($list in @('Folders', 'Browsers')) {
        $cat = @{}
        $order = @()
        foreach ($d in @($Defaults[$list] | Where-Object { $_ })) { $cat[[string]$d.Key] = $d; $order += [string]$d.Key }
        if (-not $Own.ContainsKey($list)) {
            $cfg[$list] = @($order | ForEach-Object { $cat[$_] } | Where-Object { $_.Enabled -ne $false })
            continue
        }
        $items = foreach ($e in @($Own[$list] | Where-Object { $_ })) {
            if ($e -is [string]) {
                if (-not $cat.ContainsKey($e)) { throw ((T '{0}: «{1}» нет в defaults.psd1, есть: {2}') -f $list, $e, ($order -join ', ')) }
                $h = $cat[$e].Clone(); $h.Remove('Enabled'); $h
            } elseif ($e -is [hashtable]) {
                $k = [string]$e.Key
                if ($k -and $cat.ContainsKey($k)) { $h = $cat[$k].Clone(); $h.Remove('Enabled'); foreach ($n in @($e.Keys)) { $h[$n] = $e[$n] }; $h } else { $e }
            } else { throw ((T '{0}: «{1}» должен быть ключом в кавычках или блоком @{{ Key = ... }}') -f $list, $e) }
        }
        # браузеры с Enabled = $false остаются: их Key проверяет Initialize-Browsers
        $cfg[$list] = @($items | Where-Object { $_ -and ($list -eq 'Browsers' -or $_.Enabled -ne $false) })
    }
    $seen = @{}
    foreach ($f in $cfg.Folders) {
        $k = [string]$f.Key
        if ($k -notmatch '^[A-Za-z0-9]+$') { throw ((T 'папка «{0}»: Key должен быть из латинских букв и цифр, а он «{1}»') -f $f.Title, $k) }
        if ($seen.ContainsKey($k)) { throw ((T 'папка «{0}»: Key «{1}» повторяется') -f $f.Title, $k) }
        if (-not $f.Path) { throw ((T 'папка «{0}»: не указан Path') -f $f.Title) }
        $seen[$k] = $true
    }
    if (-not $Own.ContainsKey('Browsers') -and $Own.YandexPath) { $cfg.Remove('Browsers') }   # до 1.4: один Яндекс из YandexPath
    return $cfg
}

function Read-Config([string]$Dir) {
    $def = Join-Path $Dir 'defaults.psd1'
    if (-not (Test-Path -LiteralPath $def)) { throw ((T 'Нет файла {0} с настройками по умолчанию: распакуйте ZIP с окном целиком.') -f $def) }
    $own = Join-Path $Dir 'config.psd1'
    if (-not (Test-Path -LiteralPath $own)) {
        throw ((T 'Нет файла настроек {0}.{1}Скопируйте config.example.psd1 в config.psd1 и укажите в нём StoreRoot (см. README.md).') -f $own, "`r`n")
    }
    return (Merge-Config (Import-PowerShellDataFile -LiteralPath $def) (Import-PowerShellDataFile -LiteralPath $own))
}

# Пароль проверяем у DC по IP из config.psd1, если он задан (VPN/прокси может подменять DNS, и DC по имени домена не находится),
# если он не отвечает, то по имени домена. $true/$false = верный/неверный пароль, исключение = нет связи с DC
function Test-AdLogin($Cfg, [string]$Sam, [string]$Pass) {
    $servers = @(@($Cfg.DcIp, $Cfg.Domain) | Where-Object { $_ })
    $last = $null
    foreach ($s in $servers) {
        try { $ctx = New-Object DirectoryServices.AccountManagement.PrincipalContext([DirectoryServices.AccountManagement.ContextType]::Domain, $s) }
        catch { $last = $_.Exception; continue }
        try { return $ctx.ValidateCredentials($Sam, $Pass, [DirectoryServices.AccountManagement.ContextOptions]'Negotiate, Signing, Sealing') }
        catch { $last = $_.Exception }
        finally { $ctx.Dispose() }
    }
    $m = if ($last) { $last.Message } else { '' }
    throw ((T 'Нет связи с контроллером домена ({0}), пароль не проверить: {1}') -f ($servers -join ', '), $m)
}

# ПК администратора или нет: OU компьютера берём из реестра самого ПК (его пишет групповая политика), без сети.
# Учётка Windows: администратор, если в её токене «Администраторы домена» (SID ...-512) или группа из AdminGroups.
# Такая же функция есть в profile-move.ps1
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

try {
    $cfg = Read-Config $PSScriptRoot
    Set-Language ([string]$cfg.Language) $PSScriptRoot
    if (-not $cfg.StoreRoot -or $cfg.StoreRoot -like '*example*') { throw (T 'В config.psd1 не указан StoreRoot: папка для копий.') }
    if (-not $cfg.Domain) { $cfg.Domain = $env:USERDNSDOMAIN }
    if (-not $cfg.Domain) { throw (T 'ПК не в домене AD, или в config.psd1 не указан Domain.') }
    $main = Join-Path $PSScriptRoot 'profile-move.ps1'
    if (-not (Test-Path -LiteralPath $main)) { throw ((T 'Нет файла {0}') -f $main) }

    # Не ПК администратора или сеанс сотрудника: предупредить до того, как вводить пароль
    $chk = Get-AdminCheck $cfg
    if (-not $chk.AdminPc -or -not $chk.AdminUser) {
        $n = "`r`n"
        $where = if ($cfg.AdminPcOu) { (T 'не в OU «{0}»') -f (($cfg.AdminPcOu -split ',')[0] -replace '^OU=', '') } else { (T 'не в списке AdminPCs') }
        $t = (T 'Окно запущено не на ПК администратора.') + $n + $n
        $t += if ($chk.AdminPc) { (T 'ПК {0}: ПК администратора.') -f $chk.Pc } else { (T 'ПК {0}: {1}, это не ПК администратора.') -f $chk.Pc, $where }
        $t += $n
        $t += if ($chk.AdminUser) { (T 'Windows: {0}, администратор.') -f $chk.User } else { (T 'Windows: {0}, не администратор (сеанс сотрудника?).') -f $chk.User }
        $t += $n + $n + (T 'Пароль администратора домена, введённый на чужом ПК или в сеансе сотрудника, могут перехватить программы этого ПК. ')
        $t += (T 'Сидеть за ПК сотрудника не нужно: окно ходит к его ПК по сети. Лучше закрыть и запустить окно со своего ПК.') + $n + $n
        $t += (T 'Всё равно продолжить и ввести пароль здесь?')
        if ([System.Windows.Forms.MessageBox]::Show($t, (T 'Перенос профиля'), 'YesNo', 'Warning', 'Button2') -ne 'Yes') { return }
    }

    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PmNetOnly {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute; public int dwFlags;
        public short wShowWindow; public short cbReserved2; public IntPtr lpReserved2;
        public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessWithLogonW(string user, string domain, string password, uint logonFlags,
        string appName, StringBuilder cmdLine, uint creationFlags, IntPtr env, string curDir,
        ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    const uint LOGON_NETCREDENTIALS_ONLY = 2;
    const uint CREATE_UNICODE_ENVIRONMENT = 0x400;
    const uint CREATE_NO_WINDOW = 0x08000000;

    // Запустить процесс: локально под текущим пользователем, в сети под user/domain/password
    public static int Start(string user, string domain, string password, string cmdLine, string curDir) {
        // Окружение текущего пользователя, отсортированное, как требует Windows
        var vars = new List<string>();
        foreach (DictionaryEntry e in Environment.GetEnvironmentVariables()) vars.Add(e.Key + "=" + e.Value);
        vars.Sort(StringComparer.OrdinalIgnoreCase);
        var block = new StringBuilder();
        foreach (var v in vars) block.Append(v).Append('\0');
        block.Append('\0');
        IntPtr env = Marshal.StringToHGlobalUni(block.ToString());
        try {
            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION pi;
            if (!CreateProcessWithLogonW(user, domain, password, LOGON_NETCREDENTIALS_ONLY, null,
                    new StringBuilder(cmdLine), CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW, env, curDir, ref si, out pi))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
            return pi.dwProcessId;
        } finally { Marshal.FreeHGlobal(env); }
    }
}
'@

    # Последний логин администратора (только имя, без пароля) подставляем в окно входа
    $lastFile = Join-Path $env:APPDATA 'profile-move\last-admin.txt'
    $lastUser = ''
    try { if (Test-Path -LiteralPath $lastFile) { $lastUser = ([IO.File]::ReadAllText($lastFile)).Trim() } } catch { }
    if (-not $lastUser) { $lastUser = $env:USERDOMAIN + '\' }

    while ($true) {
        $c = Get-Credential -UserName $lastUser -Message ((T 'Перенос профиля: доменная учётка администратора ПК (доступ к C$ на ПК{0})') -f $(if ($cfg.StoreRoot -like '\\*') { (T ' и к ') + $cfg.StoreRoot } else { '' }))
        if (-not $c) { return }
        $name = $c.UserName.Trim().TrimStart('\')
        $pass = $c.GetNetworkCredential().Password
        if ($name -match '^(?<d>[^\\]+)\\(?<u>.+)$') { $dom = $Matches['d']; $usr = $Matches['u']; $sam = $usr }
        elseif ($name -match '@') { $dom = $null; $usr = $name; $sam = ($name -split '@')[0] }
        else { $dom = $env:USERDOMAIN; $usr = $name; $sam = $name }
        if (-not $usr -or -not $pass) { Show-StartError (T 'Нужны логин и пароль.'); continue }

        if (Test-AdLogin $cfg $sam $pass) { break }
        Show-StartError (T 'Неверный логин или пароль. Попробуйте ещё раз.')
        $lastUser = $name
    }

    try {
        New-Item -ItemType Directory -Path (Split-Path $lastFile) -Force | Out-Null
        [IO.File]::WriteAllText($lastFile, $name)
    } catch { }

    $netUser = if ($dom) { "$dom\$usr" } else { $usr }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $cmd = '"{0}" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{1}" -NetUser "{2}"' -f $ps, $main, $netUser
    [void][PmNetOnly]::Start($usr, $dom, $pass, $cmd, $PSScriptRoot)
}
catch {
    Show-StartError ((T 'Окно «Перенос профиля» не запустилось:{0}{1}{0}{2}') -f "`r`n", $_.Exception.Message, $_.InvocationInfo.PositionMessage)
}
