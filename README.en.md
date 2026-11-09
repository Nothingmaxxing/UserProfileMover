# UserProfileMover

A PowerShell window for system administrators: moves an Active Directory domain user's data from an old PC to a new one without sitting at the user's PC.
Copies are kept in a storage: on a NAS, a file server share or, if there is no NAS, simply in a folder or on a USB drive of the admin PC.
It moves the desktop, documents, downloads, browser profiles with saved passwords (Chrome, Edge, Firefox, Yandex Browser, Chromium-Gost) and, optionally, CryptoPro CSP signatures and personal certificates.

*Русская версия: [README.md](README.md).*

Two steps:

1. **Capture from PC**: a copy of the user's data from the old PC to the storage (`<StoreRoot>\<login>\<date>_<time>_<PC>`).
2. **Restore to PC**: the copy into the user's profile on the new PC.

If the old and the new PC are on at the same time, one button, **Move now**, does both steps.
A copy can be encrypted with a password (7-Zip, AES-256), and after a restore you can print a transfer report for signing.

Nothing is deleted or changed on the old PC. You can capture a copy in advance, for example before reinstalling Windows, and restore it later to the same PC.

## What is transferred

| Checkbox | What exactly | Where in the profile |
|---|---|---|
| Desktop, Documents, Downloads | all files and folders (the folder list is set in `config.psd1`) | `Desktop`, `Documents`, `Downloads` |
| Browsers: Google Chrome, Microsoft Edge, Mozilla Firefox, Yandex Browser, Chromium-Gost (the list is set in `config.psd1`) | the whole profile without caches: bookmarks, passwords, tabs, history, cookies, extensions | `AppData\Local\Google\Chrome\User Data`, `AppData\Local\Microsoft\Edge\User Data`, `AppData\Roaming\Mozilla\Firefox`, `AppData\Local\Yandex\YandexBrowser\User Data`, `AppData\Local\Chromium\User Data` |
| Signatures (optional) | CryptoPro CSP: the "Directory" folder and the "Registry" containers; personal certificates and their Windows keys | `AppData\Local\Crypto Pro`, `HKLM\SOFTWARE\WOW6432Node\Crypto Pro\Settings\Users\<SID>\Keys`, `AppData\Roaming\Microsoft\SystemCertificates\My`, `AppData\Roaming\Microsoft\Crypto` |

The user's DPAPI keys (`AppData\Roaming\Microsoft\Protect\<SID>`) are always transferred together with Chromium-based browsers and signatures.
Passwords and cookies of Chrome, Edge and other Chromium-based browsers are encrypted with these keys. The account is a domain account and the user's SID stays the same, so Windows on the new PC decrypts them: no need to export passwords to CSV. Firefox encrypts passwords with its own key (`key4.db`), which moves together with the profile.

`desktop.ini`, `Thumbs.db`, `~$*` and `*.tmp` are not transferred. What to transfer is set in `config.psd1` with lists of keys: `Folders = @('Desktop', 'Documents', 'Downloads')`, `Browsers = @('Chrome', 'Firefox')`, and `EnableCryptoPro` for signatures. Ready-made folders you only need to add to `Folders`: `Signatures` (Outlook signatures), `OfficeTpl` (Word templates), `Ibases1C` (1C database list), `Pictures`, `Favorites`. Your own folder or browser can be added as a block in the same list (see "Settings" and "Add your own browser"). Each browser and each folder gets its own checkbox in the window.

In the English example config (`config.example.en.psd1`), Chrome, Edge and Firefox are on, while Yandex Browser, Chromium-Gost and CryptoPro (common in Russia) are off.

## Requirements

- An Active Directory domain. The user signs in to the old and the new PC with the same domain account.
- An admin PC with Windows 10/11 or Windows Server and Windows PowerShell 5.1 (built into Windows). RSAT and the ActiveDirectory module are not needed.
- A domain account that is an administrator on the users' PCs (access to `C$`). The window asks for it at startup. If the copies are on a network share, this account needs access to it too.
- Space for the copies (`StoreRoot`): a share on a NAS or file server or, if there is no NAS, a folder or USB drive on the admin PC. See "Preparing the storage".
- SMB (port 445) from the admin PC to the users' PCs. This is usually enough: Windows queries the remote registry, services and the PC name over SMB named pipes.
- The old and the new PC are on and connected to the network.
- For copy encryption (optional): [7-Zip](https://www.7-zip.org/) 16 or later on the admin PC.

## Quick start

1. Download the ZIP of the latest version from [Releases](https://github.com/Nothingmaxxing/UserProfileMover/releases) (or Code → Download ZIP) and extract it to a folder users cannot write to: for example, an IT share or `C:\Tools\profile-move` on the admin PC.
   Remove the "downloaded from the internet" mark: `Get-ChildItem -Recurse | Unblock-File` in this folder.
2. Copy `config.example.en.psd1` to `config.psd1` and set `StoreRoot` in it: a share, a folder or a USB drive (see "Preparing the storage"). The rest is optional:
   - `Domain` empty: the domain is taken from `%USERDNSDOMAIN%`;
   - `DcIp`: the domain controller IP, if a VPN client on the admin PC overrides DNS (198.18.x.x addresses);
   - `AdminPcOu`, `AdminPCs`, `AdminGroups`: for the "not running on an admin PC" warning;
   - `Folders`, `Browsers`, `EnableCryptoPro`: what to transfer;
   - `OrgName`: the organization name in the transfer report header.

   Everything not set in `config.psd1` is taken from `defaults.psd1` (see "Settings").
3. Run `profile-move.cmd` and enter the domain admin account. The list of copies in the storage opens.

## Settings

Settings live in two files next to the window:

- `config.psd1`: only your own values. Example: `config.example.en.psd1` (with Russian comments: `config.example.psd1`).
- `defaults.psd1`: all settings with their defaults and comments (in Russian). Do not edit it: updates replace it. To change a setting, copy its line to `config.psd1`.

| Setting | Default | What it is |
|---|---|---|
| `StoreRoot` | none, required | where to keep the copies (see "Preparing the storage") |
| `Domain` | the domain of this PC | AD domain DNS name |
| `DcIp` | empty | domain controller IP, if a VPN or proxy overrides DNS |
| `AdminPcOu`, `AdminPCs`, `AdminGroups` | empty | admin PCs and groups for the "not an admin PC" warning |
| `Folders` | `Desktop`, `Documents`, `Downloads` | folders: keys from `defaults.psd1` and your own blocks `@{ Key = ...; Title = ...; Path = ... }` |
| `Browsers` | all five | browsers: `Yandex`, `ChromiumGost`, `Chrome`, `Edge`, `Firefox` and your own blocks |
| `EnableCryptoPro` | `$true` | CryptoPro CSP signatures and personal certificates |
| `Language` | `auto` | window language: `auto`, `ru`, `en` (see "Language") |
| `Act`, `OrgName` | `$true`, empty | transfer report and the organization in its header |
| `Encrypt`, `SevenZip`, `StagingDir` | `Optional`, empty, empty | copy encryption (see "Copy encryption") |
| `UpdateCheck`, `UpdateRepo` | `$true`, this repository | new version check (see "Updates") |
| `RetentionDays` | 30 | copies older than this are offered for deletion at startup |
| `MinNasFreeGB`, `TargetSpareGB` | 20, 2 | GB that must be free in the storage before a capture and on the new PC after a transfer |
| `RoboThreads` | 8 | robocopy threads |
| `FileExcludes`, `ChromiumExclude*`, `CryptoPro*`, `Certs*`, `DpapiPath` | see `defaults.psd1` | what not to copy and where things are in the profile |

A block with a key from `defaults.psd1` changes only the fields it lists, for example `Browsers = @('Chrome', @{ Key = 'Firefox'; Exe = @('D:\Firefox\firefox.exe') })`. To drop a folder or browser, leave its key out of the list (or set `Enabled = $false` in a block).
An unknown setting in `config.psd1` (for example, a typo like `AdminGroup`) stops the start with an error. A full `config.psd1` from versions 1.4 and 1.5 works as before.

## Move a user to another PC

1. The user saves their work and signs out of Windows on the old PC (or at least closes browsers and documents).
2. On your own PC, run `profile-move.cmd` and enter the admin account. You do not need to sit at the user's PC: the window reaches it over the network.
3. **Capture from PC…**: the user's login (as in AD, for example `jsmith`), the old PC name (or its IP), checkboxes, "Capture".
   Usually 1–10 minutes, longer for a big desktop. The window counts the files first, then copies: the percentage is shown in the window title and every 30 s in the log at the bottom. Do not close the window.
4. The user signs in to Windows on the new PC once, so that their profile is created. Do not open browsers there yet.
5. **Restore to PC…**: login, "Find copies", select a copy (newest first), the new PC name (or IP), "Restore".
6. The window shows what to check with the user: files in place, bookmarks and passwords in browsers, containers in CryptoPro.
7. The window offers to open the transfer report: print it and have the user sign it (see "Transfer report").

### Both PCs are on: "Move now"

**Move now…**: login, old PC, new PC (the user has already signed in to it), checkboxes, "Move".
The window first checks both PCs and the user's profile on the new one, then captures a copy and restores it right away. The result is shown in one message at the end; the copy stays in the storage.
If the restore fails (for example, the new PC was turned off), the copy is already captured: restore it later with "Restore to PC…".

If the new PC already has a browser profile, the window does not delete it but renames it next to it to `User Data.old-<date>` (for Firefox, `Firefox.old-<date>`).
Files that are newer on the new PC than in the copy are not overwritten. CryptoPro containers with the same name are left untouched.

### Buttons

- **Move now…**: capture from the old PC and restore to the new one right away.
- **Capture from PC…**: a copy of the user's data to the storage.
- **Restore to PC…**: the copy into the user's profile on the new PC.
- **Details**: what was in the selected copy and where it was restored.
- **Report**: the transfer report for the selected copy (by its last restore).
- **Delete copy**: delete the selected copy.
- **Refresh list**, **Guide** (this file), **Logs**: the `logs` folder next to the script, one file per day and PC. The robocopy logs for each folder are inside the copy itself, in `_logs`.

### Transfer report

After "Restore to PC" and "Move now", the window creates a report and offers to open it in the browser. The report contains:
the user, the old and the new PC, dates, the account that did the work, a "what was transferred" table (files, size, result, note),
the overall result and signature lines for the person who did the transfer and for the user ("Data checked, no claims"). Print it from the browser (Ctrl+P or the "Print" button in the report).

Reports are kept in `logs\acts` next to the window, named `<date>_<time>_<login>_<PC>.html`. The **Report** button rebuilds the report for the selected copy
(if the copy has not been restored yet, you get a backup report). Organization name for the header: `OrgName` in `config.psd1`;
to skip the report after each restore: `Act = $false`.

### Copy encryption

Copies contain browser passwords and private signature keys. If not only administrators can see the storage (a shared NAS, a USB drive you carry around), better encrypt the copy:
in "Capture from PC…" and "Move now…" check **Encrypt the copy with a password** and enter the password twice. The checkbox appears if 7-Zip is installed on the admin PC.

- The storage gets a `data.7z` archive (7-Zip, AES-256, file names inside are encrypted too). Only `manifest.json` stays readable: full name, login, PCs, dates, sizes, results.
- The copy is first assembled in a temporary folder on the admin PC (`StagingDir`, `%TEMP%\profile-move` by default), then encrypted into the storage, and the temporary folder is wiped. The disk of this PC needs as much free space as the copy.
- On "Restore to PC…" the window asks for the password and checks it right away. The copy is extracted to the temporary folder, restored and wiped. "Move now" restores the copy from the temporary folder where it was assembled, without decrypting.
- The password is 8+ characters: Latin letters, digits and symbols (no other alphabets: 7-Zip on different PCs might read them differently). The window never stores it. **Lost password: the copy cannot be opened.**
- 7-Zip gets the password through stdin, so it is not in the process command line.
- Temporary folders left by a window that was closed while working are wiped the next time the window starts.

Policy in `config.psd1`, `Encrypt`: `Off` (no checkbox), `Optional` (checkbox unchecked, the default), `On` (checkbox checked), `Required` (encrypted copies only). Path to 7z.exe if it is not in `C:\Program Files\7-Zip`: `SevenZip`.

You can open a copy manually with any 7-Zip: `data.7z` and the password.

## Preparing the storage

Copies contain the user's DPAPI keys, browser passwords and private signature keys. **Only administrators may open the folder with the copies.**

| Option | When it fits | `StoreRoot` |
|---|---|---|
| A share on a NAS or file server | Copies are visible from any admin PC; a NAS usually has snapshots | `\\nas\Migrate` |
| A folder on the admin PC | No NAS; one administrator does the transfers from one PC | `D:\Migrate` |
| A USB drive on the admin PC | Neither a NAS nor space on the PC | `E:\Migrate` |

In any case the network is only needed to the users' PCs: data goes from the old PC to the storage, then from the storage to the new PC.

### A share on a NAS or file server

The share may be visible: without permissions nobody gets inside anyway. Snapshots (shadow copies) and access auditing on it are a plus.

**Windows file server** (example):

```powershell
$dir = 'D:\Migrate'
$admins = 'EXAMPLE\Domain Admins'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
icacls $dir /inheritance:r /grant:r "${admins}:(OI)(CI)F" 'NT AUTHORITY\SYSTEM:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
New-SmbShare -Name Migrate -Path $dir -FullAccess $admins -FolderEnumerationMode AccessBased
```

**TrueNAS** (SCALE or CORE, NAS joined to the domain):

1. Datasets → Add Dataset: name `Migrate`, Share Type `SMB`.
2. Edit Permissions: owner a domain admin, group Domain Admins; in the ACL keep only `owner@` and this group, both Full Control with inheritance. Remove `everyone@`, `builtin_users` and user groups.
3. Shares → Windows (SMB) Shares → Add: path to the dataset, name `Migrate`, enable Shadow Copies. Add the dataset to a snapshot task.

On a Linux NAS (ZFS, ext4, btrfs), a file or folder name may be at most 255 **bytes** of UTF-8: a Cyrillic letter takes 2 bytes, so that is about 127 letters (CJK characters take 3 bytes). The window does not copy files with longer names and lists them in the result.

### No NAS: a folder or USB drive on the admin PC

The window writes to a local folder under your Windows account without elevation. So grant permissions to your account (or your IT group): "Administrators" and "Domain Admins" do not count without UAC elevation. Run in PowerShell under the account you will start the window with:

```powershell
$dir = 'D:\Migrate'
$me = "$env:USERDOMAIN\$env:USERNAME"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
icacls $dir /inheritance:r /grant:r "${me}:(OI)(CI)F" 'NT AUTHORITY\SYSTEM:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
```

In `config.psd1`: `StoreRoot = 'D:\Migrate'`. There are no snapshots here, so a deleted copy cannot be recovered.

USB drive: format it as NTFS (FAT32 cannot hold files over 4 GB, and exFAT cannot restrict permissions) and turn on BitLocker To Go, since the drive will hold signature keys. The drive letter must match `StoreRoot`: if Windows gives the drive another letter, change it in Disk Management.

## Add your own browser

Chromium-based browsers are built the same way, so a key and a profile folder are usually enough. Example for Brave and Vivaldi (typical paths, not tested in practice): in `config.psd1` the blocks go into `Browsers` together with the keys of the browsers you need from `defaults.psd1`:

```powershell
Browsers = @(
    'Chrome', 'Edge'
    @{ Key = 'Brave';   Title = 'Brave';   UserData = @('AppData\Local\BraveSoftware\Brave-Browser\User Data') }
    @{ Key = 'Vivaldi'; Title = 'Vivaldi'; UserData = @('AppData\Local\Vivaldi\User Data') }
)
```

Caches and the "browser is open" marker are taken from Chromium by default (`ChromiumExcludeDirs`, `ChromiumLockFiles`). For a browser not based on Chromium, set `Dpapi = $false` and your own `LockFiles` and `ExcludeDirs`, as for Firefox in `defaults.psd1`.

## Troubleshooting

| What you see | What to do |
|---|---|
| "Settings file config.psd1 not found" | Copy `config.example.en.psd1` to `config.psd1` and set `StoreRoot` |
| "The default settings file … defaults.psd1 is missing" | Extract the whole ZIP: `defaults.psd1` sits next to the scripts |
| "unknown setting …" | A typo in a setting name in `config.psd1`: compare with `defaults.psd1` |
| "No access to \\\\…\\Migrate" | The server is off, the `StoreRoot` path is wrong, or the account has no permissions on the share |
| "Folder D:\\Migrate does not exist (StoreRoot in config.psd1)" | The folder on the admin PC was not created, or the USB drive is not connected or got another letter |
| "Cannot reach the domain controller" or "Cannot reach AD" | The DC is unavailable. If `DcIp` is set in `config.psd1`, check that the address is right |
| "No IP found for … in DNS" | The PC has not been on for a long time or is not registered in DNS. Enter its IP instead of the name |
| "DNS says … but a different PC answers there" | The DNS record is stale, the address now belongs to another PC. Enter the real IP of the PC you need |
| "does not respond over SMB (port 445)" | The PC is off or its firewall blocks SMB from the admin PC |
| "No access to \\\\PC\\C$" | The account is not an administrator on that PC |
| "Google Chrome is open for the user" (or another browser) | Ask the user to close the browser and click "Retry". "Cancel" transfers everything except this browser |
| "The user has not signed in to … yet" | Have them sign in to Windows on the new PC once, then click "Restore" again |
| No "Encrypt the copy with a password" checkbox | There is no 7-Zip on the admin PC (or `Encrypt = 'Off'`). Install 7-Zip or set the path to 7z.exe in `SevenZip` |
| "Wrong password for the copy" | The password is case and keyboard-layout sensitive. Without the right password an encrypted copy cannot be opened |
| "The temporary folder … has … free" | The admin PC disk lacks space for the encryption temp folder. Free up space or set `StagingDir` to another disk |
| Orange line "N file(s) not copied: …" | The reason and the full path of each file are in the log. "file is open in a program": close it and capture again (a new copy appears) |
| "file name of … bytes, the NAS accepts up to 255" | Shorten the name on the user's PC and capture again, or move the file manually. A long path (over 260 characters) is not a problem by itself, robocopy copies it |
| Browser passwords do not open on the new PC | Export the passwords to CSV on the old PC and import them on the new one |
| Chrome or Edge: website sign-ins are lost | Since version 127, Chrome (and apparently Edge) encrypts cookies with a key bound to the PC itself (App-Bound Encryption). Such cookies cannot be decrypted on another PC: sign in to the websites again |
| Firefox opened with an empty profile | Firefox is installed in another folder on the new PC and created a new profile. Open `about:profiles` and make the transferred profile the default |
| CryptoPro: "Access denied" (0x80090010) | In regedit, grant the user Full Control on `HKLM\SOFTWARE\WOW6432Node\Crypto Pro\Settings\Users\<SID>` |
| "CryptoPro CSP not found" | Install CryptoPro on the new PC and enter the license: the containers are already in place |
| "could not restore the Remote Registry service" | On that PC, in services.msc, give the Remote Registry service its previous startup type back and stop it |
| "Registry" containers skipped, `sc config` error 5 | The window runs in a session without admin rights on the user's PC. Start it from your own PC under your own account |

## Security

- The admin password is never written anywhere. `start.ps1` verifies it with the domain controller and starts the window like `runas /netonly`: on this PC as you, to the users' PCs and the network share as the administrator. Only the login is remembered (`%APPDATA%\profile-move\last-admin.txt`).
- Before asking for the password, the window checks that it runs on an admin PC (OU or list in `config.psd1`) under an admin account. If not, it warns: a domain admin password typed on a user's PC can be intercepted. The default button is "No".
- Keep the window's folder where users cannot write: the window works with a domain admin account.
- Copies older than `RetentionDays` (30 days by default) are offered for deletion at startup.
- A copy can be encrypted with a password (7-Zip, AES-256), see "Copy encryption". The copy password is never written anywhere.
- If the window is closed during a transfer, it stops robocopy and 7-Zip, restores the Remote Registry service on the user's PC and wipes the temporary folder.
- The profile and CryptoPro containers stay on the old PC. If the PC goes to another person, delete the old profile (System Properties → Advanced → User Profiles) and the containers in CryptoPro.

## How it works

- WinForms on Windows PowerShell 5.1, no external modules. AD is read via ADSI (signed LDAP), copying is done with `robocopy` over `\\PC\C$`.
- The window takes the PC's IP from the domain controller's DNS (if `DcIp` is set) or from the system DNS, discarding the fake 198.18.0.0/15 addresses. It verifies that the right PC answers at the address by the name the PC reports itself (`NetWkstaGetInfo`): a stale DNS record will not send a copy to someone else's PC.
- The user's profile is found by SID in the PC's `ProfileList` registry key. For the registry, the window turns on the Remote Registry service for the duration of the work and then restores it.
- `robocopy /E /COPY:DAT /DCOPY:T /XJ /R:1 /W:1 /MT:8`; on restore `/XO` for folders and "newer files only" (`/XC /XN /XO`) for keys and signatures. The new PC's DPAPI `Preferred` key is not touched.
- "Registry" containers are saved in the copy as `CryptoPro-Reg\keys.json` and `keys.reg`. `keys.reg` can be imported manually on the new PC as an administrator if the remote registry is not available.
- Each copy has a `manifest.json`: who, from where, when, what was captured, where and with what result it was restored. For a browser it also records the profile path it was captured from: it is restored to the same path.
- A browser is considered open if its `lockfile` or cookie file is locked (`parent.lock` for Firefox): then the window asks to close it and does not copy half a profile.
- `profile-move.ps1 -NoGui` loads the functions without the window: `. .\profile-move.ps1 -NoGui`.

## Language

The window texts are written in Russian in the scripts; `lang\en.psd1` maps each Russian text (the key) to English. `Language` in `config.psd1`: `auto` (Russian if the Windows display language or regional format is Russian, otherwise English), `ru` or `en`.
Another language: copy `lang\en.psd1` to `lang\<two-letter code>.psd1`, translate the values (keep the `{0}` placeholders and the keys) and set `Language = '<code>'`. A text without a translation is shown in Russian.
`tests\check.ps1` checks that every text of the window has an English translation with the same placeholders.

## Updates

Released versions are in [Releases](https://github.com/Nothingmaxxing/UserProfileMover/releases): a ZIP and its SHA256 file.
Once a day the window asks GitHub in the background for the latest version and, if a new one is out, shows a "Version … is out" link to the right of the buttons and a line in the log.
The window downloads nothing by itself. Without internet the check silently does nothing; to turn it off: `UpdateCheck = $false` in `config.psd1`.

To update: download the ZIP of the new version, unblock it (`Unblock-File`), replace the files in the window folder. Do not touch `config.psd1` and the `logs` folder.
New settings arrive in `defaults.psd1` with their defaults, `config.psd1` does not need changes. For what changed, see "Versions".

To release a version (for those who maintain the repository or a fork): bump `$script:AppVersion` in `profile-move.ps1`, add an entry to "Versions" in README.md and this file, then tag:

```
git tag v1.5
git push origin v1.5
```

GitHub Actions (`.github/workflows/release.yml`) runs the checks in Windows PowerShell 5.1, builds the ZIP and publishes the release. The `tests/check.ps1` checks also run on every pull request; locally: `powershell -File tests\check.ps1`.

## Limitations

- Domain accounts only: browser passwords move because the user's SID is the same on both PCs. Local accounts and accounts recreated in AD will not work.
- Chromium-based browsers with a master password or signed in to their own sync account are transferred as is: after the transfer you may need to sign in to the browser account again.
- Since version 127, Chrome (and apparently Edge) binds cookie encryption to the PC itself, so website sign-ins will most likely be lost after the transfer. Bookmarks and passwords are transferred.
- The CryptoPro license is not transferred: the new PC needs its own.
- Mail, printers, network drives and application settings are not transferred.

## Test before first use (~15 minutes)

One test PC will be both the old and the new one: after "Capture" the test user's profile is deleted, and Windows creates a new one, as on a new PC.

1. Sign in to the test PC as a test domain user without admin rights: put a file on the desktop, in Documents and in Downloads; in the browser save a password on any website, add a bookmark, sign in to a website and stay signed in. Close the browser, sign out of Windows.
2. On your PC, in "Capture from PC…": the test user's login, the test PC, all checkboxes.
3. On the test PC, as an administrator, delete the test user's profile (System Properties → Advanced → User Profiles).
4. Sign in to the test PC as the test user (a new profile is created), do not open the browser.
5. In "Restore to PC…": the same login, "Find copies", the same PC, "Restore". Answer "Yes" to "the same PC?".
6. As the test user, check the files, the bookmark, the saved password (in the browser settings, passwords section) and the website sign-in.

## Versions

- **1.5.1** (2026-11-09): short `config.psd1`. Defaults moved to `defaults.psd1`, `config.psd1` holds only your own values: storage, domain, what to transfer. Folders and browsers are set with lists of keys (`Folders = @('Desktop', 'Signatures')`, `Browsers = @('Chrome', 'Firefox')`), your own are added as blocks to the same list. A typo in a setting name is now an error instead of a silent default. A full `config.psd1` from 1.4 and 1.5 works as before.
- **1.5** (2026-11-08): "Move now" button (capture and restore right away when both PCs are on); HTML transfer report for printing and signing ("Report" button, `Act` and `OrgName` in `config.psd1`); copy encryption with a password (7-Zip, AES-256; `Encrypt`, `SevenZip`, `StagingDir`); new version check on GitHub (`UpdateCheck`) and releases with a ZIP; English interface (`Language`, `lang\en.psd1`, `config.example.en.psd1`, this file). If the window is closed while working, it stops copying, restores the Remote Registry service and marks the copy "with errors".
- **1.4** (2026-11-08): first public version. Organization settings moved to `config.psd1` (example: `config.example.psd1`), the domain defaults to `%USERDNSDOMAIN%`, `DcIp` and the admin PC check are optional, folder and browser checkboxes are built from `config.psd1`, besides Yandex Browser it transfers Chromium-Gost, Chrome, Edge and Firefox (and any browser added to `Browsers`), CryptoPro can be turned off. The copy storage can be a share, a folder or a USB drive on the admin PC.
- **1.3**: transfer percentage, clear reasons for files not copied (names longer than 255 bytes for a NAS), warning when not running on an admin PC.
- **1.2**: works by IP via the domain controller's DNS, checks the PC name at the address.

## License

[MIT](LICENSE)
