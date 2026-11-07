@{
    # Settings of the User Profile Mover window. Copy this file to config.psd1 next to it and adjust it.
    # No secrets here: the window asks for the admin account at startup and never stores it.

    # ---------------------------------------------------------------- required

    # Where to keep the copies. Only administrators may open this folder: copies contain DPAPI keys,
    # browser passwords and private signature keys (see README.en.md, "Preparing the storage"). Options:
    #  - a share on a NAS or file server: '\\nas.example.local\Migrate' (or by IP if a VPN client overrides DNS);
    #  - a folder on the admin PC: 'D:\Migrate';
    #  - an NTFS USB drive on the admin PC: 'E:\Migrate' (preferably with BitLocker To Go).
    StoreRoot      = '\\nas.example.local\Migrate'

    # ---------------------------------------------------------------- domain (may stay empty)

    # DNS name of the AD domain. Empty: taken from %USERDNSDOMAIN% of whoever started the window
    Domain         = ''
    # Domain controller IP. If set, the window queries it directly for AD (LDAP) and PC addresses (DNS),
    # bypassing the system DNS. Needed when a VPN client on the admin PC overrides DNS (fake-ip 198.18.0.0/15).
    # Empty: AD and DNS through the system resolver
    DcIp           = ''

    # ---------------------------------------------------------------- language

    # 'auto': Russian if the Windows display language or regional format is Russian, otherwise English;
    # 'ru' or 'en' (translation in lang\en.psd1)
    Language       = 'auto'

    # ---------------------------------------------------------------- transfer report

    # After "Restore to PC" and "Move now" the window creates a transfer report (HTML: what was transferred, size, result,
    # signature lines) and offers to open it for printing. Reports are kept in logs\acts next to the window.
    # The "Report" button creates one for the selected copy at any time. $false: no report after a restore
    Act            = $true
    OrgName        = ''          # organization name in the report header, for example 'Contoso Ltd.'

    # ---------------------------------------------------------------- copy encryption (7-Zip)

    # A copy can be encrypted with a password: the storage then gets a 7-Zip archive (AES-256, file names encrypted too),
    # only manifest.json stays readable (full name, login, PC, sizes). Needs 7-Zip 16 or later on the admin PC.
    # The window asks for the password when capturing and restoring and never stores it: lost password = lost copy.
    #   'Off'       no encryption, no checkbox
    #   'Optional'  "Encrypt" checkbox is shown, unchecked by default
    #   'On'        checkbox is checked by default
    #   'Required'  encrypted copies only, the checkbox cannot be cleared
    Encrypt        = 'Optional'
    SevenZip       = ''          # path to 7z.exe; empty: C:\Program Files\7-Zip\7z.exe
    # Temporary folder on this PC: an encrypted copy is assembled in it (and extracted into it when restoring),
    # then the folder is wiped. Needs as much space as the copy. Empty: %TEMP%\profile-move
    StagingDir     = ''

    # ---------------------------------------------------------------- updates

    # Once a day the window asks GitHub (api.github.com) whether a new version is out and shows a link to it.
    # It downloads and sends nothing except the request itself. $false: do not ask (for example, without internet)
    UpdateCheck    = $true
    UpdateRepo     = 'Nothingmaxxing/UserProfileMover'   # for a fork: your repository

    # ---------------------------------------------------------------- limits

    RetentionDays  = 30          # copies older than this are offered for deletion at startup
    MinNasFreeGB   = 20          # do not capture if the storage (StoreRoot) has less free space
    TargetSpareGB  = 2           # free space that must remain on the new PC after the transfer
    RoboThreads    = 8           # robocopy threads (/MT)

    # ---------------------------------------------------------------- "not an admin PC" warning

    # Before asking for the password, the window checks that it runs on an admin PC under an admin account.
    # If not, it warns: a domain admin password typed on a user's PC can be intercepted.
    # Admin PC: a computer in this OU (according to the PC's own Group Policy data) or in the AdminPCs list.
    # Both empty: the PC check is off.
    AdminPcOu      = ''          # for example 'OU=Admin PCs,OU=Computers,DC=example,DC=local'
    AdminPCs       = @()         # for example @('IT-PC-01', 'IT-PC-02')
    # Admin account: Domain Admins in the token (SID ...-512, always checked, in any language)
    # or one of these groups
    AdminGroups    = @()         # for example @('IT-Admins')

    # ---------------------------------------------------------------- what to transfer

    # User folders (paths inside the profile C:\Users\<login>), each with its own checkbox in the window.
    # Key: Latin letters and digits, no spaces, must not match a browser Key, not Dpapi/Crypto*.
    # Files that are newer on the new PC than in the copy are not overwritten
    Folders = @(
        @{ Key = 'Desktop';   Title = 'Desktop';   Path = 'Desktop' }
        @{ Key = 'Documents'; Title = 'Documents'; Path = 'Documents' }
        @{ Key = 'Downloads'; Title = 'Downloads'; Path = 'Downloads' }
        # More options: remove the # at the start of the line
        # @{ Key = 'Pictures';  Title = 'Pictures';  Path = 'Pictures' }
        # @{ Key = 'Favorites'; Title = 'Favorites'; Path = 'Favorites' }
        # @{ Key = 'Signatures'; Title = 'Outlook signatures'; Path = 'AppData\Roaming\Microsoft\Signatures' }
        # @{ Key = 'OfficeTpl'; Title = 'Word templates (Normal.dotm)'; Path = 'AppData\Roaming\Microsoft\Templates' }
    )
    # These files are never transferred, in any folder
    FileExcludes = @('desktop.ini', 'Thumbs.db', '~$*', '*.tmp')

    # Browsers: each has its own checkbox; the whole profile is transferred (bookmarks, passwords, tabs, cookies, extensions) without caches.
    #   Key       Latin letters and digits: the name of the browser folder in the copy
    #   UserData  profile folder inside C:\Users\<login>; several are allowed, the first one found on the old PC is used
    #   Dpapi     passwords and cookies are encrypted with the user's DPAPI (all Chromium-based browsers): the DPAPI keys
    #             are transferred together with the browser. Firefox encrypts passwords itself, so it gets $false
    #   LockFiles files locked while the browser is open (path inside UserData, * allowed). Not set: as for Chromium
    #   ExcludeDirs, ExcludeFiles  what not to copy. Not set: Chromium caches (ChromiumExcludeDirs below)
    #   Exe       where to look for the browser on the new PC: if not found, the window warns
    #   Note      what to tell after the transfer
    # Browser you do not need: Enabled = $false or delete the block. Not on the user's PC: "nothing to transfer" in the log
    Browsers = @(
        @{
            Key = 'Chrome'; Title = 'Google Chrome'
            UserData = @('AppData\Local\Google\Chrome\User Data')
            Exe = @(
                'C:\Program Files\Google\Chrome\Application\chrome.exe'
                'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
                'AppData\Local\Google\Chrome\Application\chrome.exe'
            )
            Note = 'Since version 127, Chrome binds cookie encryption to the PC itself: you will most likely have to sign in to websites again.'
        }
        @{
            Key = 'Edge'; Title = 'Microsoft Edge'
            UserData = @('AppData\Local\Microsoft\Edge\User Data')
            Exe = @(
                'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
                'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
            )
            Note = 'Edge may bind cookie encryption to the PC itself: if website sign-ins are lost, sign in again.'
        }
        @{
            Key = 'Firefox'; Title = 'Mozilla Firefox'; Dpapi = $false
            UserData = @('AppData\Roaming\Mozilla\Firefox')
            LockFiles = @('Profiles\*\parent.lock')
            ExcludeDirs = @('Crash Reports', 'Pending Pings', 'crashes', 'minidumps', 'datareporting', 'saved-telemetry-pings')
            ExcludeFiles = @('parent.lock', '*.tmp')
            Exe = @(
                'C:\Program Files\Mozilla Firefox\firefox.exe'
                'C:\Program Files (x86)\Mozilla Firefox\firefox.exe'
            )
            Note = 'If Firefox is installed in a different folder on the new PC, it may open an empty profile: select the transferred one in about:profiles.'
        }
        @{
            # Yandex Browser (common in Russia). Enabled = $true to transfer it
            Key = 'Yandex'; Title = 'Yandex Browser'; Enabled = $false
            UserData = @('AppData\Local\Yandex\YandexBrowser\User Data')
            Exe = @(
                'AppData\Local\Yandex\YandexBrowser\Application\browser.exe'
                'C:\Program Files (x86)\Yandex\YandexBrowser\Application\browser.exe'
                'C:\Program Files\Yandex\YandexBrowser\Application\browser.exe'
            )
        }
        @{
            # Chromium with GOST encryption (github.com/deemru/Chromium-Gost), installed into the user profile.
            # Enabled = $true to transfer it
            Key = 'ChromiumGost'; Title = 'Chromium-Gost'; Enabled = $false
            UserData = @('AppData\Local\Chromium\User Data')
            Exe = @(
                'AppData\Local\Chromium\Application\chrome.exe'
                'C:\Program Files\Chromium\Application\chrome.exe'
                'C:\Program Files (x86)\Chromium\Application\chrome.exe'
            )
        }
    )
    # For Chromium-based browsers without their own ExcludeDirs, ExcludeFiles, LockFiles
    ChromiumExcludeDirs = @(
        'Cache', 'Code Cache', 'GPUCache', 'GrShaderCache', 'GraphiteDawnCache', 'ShaderCache',
        'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'CacheStorage', 'ScriptCache',
        'Crashpad', 'Crash Reports', 'BrowserMetrics', 'optimization_guide_model_store',
        'component_crx_cache', 'extensions_crx_cache', 'Safe Browsing', 'SwReporter'
    )
    ChromiumExcludeFiles = @('lockfile', '*.tmp', '*.pma')
    ChromiumLockFiles    = @('lockfile', 'Default\Network\Cookies')

    # CryptoPro CSP signatures (Russian GOST crypto provider) and personal certificates.
    # $true adds the "CryptoPro signatures and personal certificates" checkbox to the window
    EnableCryptoPro  = $false

    CryptoProDir     = 'AppData\Local\Crypto Pro'                           # "Directory" reader
    CryptoProRegKeys = @(                                                   # "Registry" reader, {SID} = the user's SID
        'SOFTWARE\WOW6432Node\Crypto Pro\Settings\Users\{SID}\Keys'
        'SOFTWARE\Crypto Pro\Settings\Users\{SID}\Keys'
    )
    CryptoProPc      = 'C:\Program Files\Crypto Pro\CSP'                    # is CryptoPro installed on the new PC
    CertsMyPath      = 'AppData\Roaming\Microsoft\SystemCertificates\My'    # personal certificates
    CertsCryptoPath  = 'AppData\Roaming\Microsoft\Crypto'                   # Windows (non-GOST) keys for personal certificates

    # The user's DPAPI keys: without them, Chromium-based browser passwords and cookies cannot be decrypted on the new PC
    DpapiPath        = 'AppData\Roaming\Microsoft\Protect\{SID}'
}
