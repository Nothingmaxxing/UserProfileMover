@{
    # User Profile Mover settings: copy this file to config.psd1 next to it and fill in your values.
    # Anything not set here is taken from defaults.psd1 (all settings with their defaults, described in README.en.md,
    # "Settings"). To change any of them, copy its line here. Do not edit defaults.psd1: updates replace it.

    # Where to keep the copies (required). Only administrators should be able to open this folder: copies contain
    # browser passwords and signature keys. A share '\\nas.example.local\Migrate', or a folder or USB drive on the admin PC 'D:\Migrate'
    StoreRoot   = '\\nas.example.local\Migrate'

    # AD domain. Empty: the domain of this PC
    Domain      = ''
    # Domain controller IP, if a VPN or proxy on the admin PC overrides DNS. Empty: regular DNS
    DcIp        = ''

    # Warn if the window is started on a PC that is not an admin PC. All empty: the PC is not checked
    AdminPcOu   = ''      # OU with admin PCs, for example 'OU=Admin PCs,OU=Computers,DC=example,DC=local'
    AdminPCs    = @()     # or their names, for example @('IT-PC-01', 'IT-PC-02')
    AdminGroups = @()     # admin groups besides Domain Admins, for example @('IT-Admins')

    # What to transfer: remove what you do not need. More folders: 'Pictures', 'Favorites', 'Signatures' (Outlook),
    # 'OfficeTpl' (Word templates), 'Ibases1C' (1C database list). More browsers: 'Yandex', 'ChromiumGost'.
    # Your own folder or browser: see README.en.md
    Folders     = @('Desktop', 'Documents', 'Downloads')
    Browsers    = @('Chrome', 'Edge', 'Firefox')
    EnableCryptoPro = $false  # CryptoPro CSP signatures and personal certificates

    # Organization name in the transfer report header, for example 'Contoso Ltd.'
    OrgName     = ''
}
