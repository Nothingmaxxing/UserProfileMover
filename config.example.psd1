@{
    # Настройки окна «Перенос профиля». Скопируйте этот файл в config.psd1 рядом и поправьте под себя.
    # Секретов здесь нет: учётку администратора окно спрашивает при запуске и никуда не записывает.

    # ---------------------------------------------------------------- обязательно

    # Где хранить копии. Открыть папку должны только администраторы: в копиях лежат ключи DPAPI,
    # пароли браузера и закрытые ключи подписей (см. README, «Подготовка хранилища»). Подойдёт:
    #  - шара на NAS или файловом сервере: '\\nas.example.local\Migrate' (или по IP, если DNS подменяет VPN/прокси);
    #  - папка на ПК администратора: 'D:\Migrate';
    #  - USB-диск в NTFS на ПК администратора: 'E:\Migrate' (лучше с BitLocker To Go).
    StoreRoot      = '\\nas.example.local\Migrate'

    # ---------------------------------------------------------------- домен (можно оставить пустым)

    # DNS-имя домена AD. Пусто: берётся из %USERDNSDOMAIN% того, кто запустил окно
    Domain         = ''
    # IP контроллера домена. Если указан, окно спрашивает у него AD (LDAP) и IP компьютеров (DNS) напрямую,
    # мимо системного DNS. Нужен, когда на ПК администратора DNS подменяет VPN/прокси (fake-ip 198.18.0.0/15).
    # Пусто: AD и DNS через системный резолвер
    DcIp           = ''

    # ---------------------------------------------------------------- лимиты

    RetentionDays  = 30          # копии старше окно предлагает удалить при запуске
    MinNasFreeGB   = 20          # не снимать копию, если в хранилище (StoreRoot) свободно меньше
    TargetSpareGB  = 2           # на новом ПК должно остаться свободно после переноса
    RoboThreads    = 8           # потоков robocopy (/MT)

    # ---------------------------------------------------------------- предупреждение «не ПК администратора»

    # Перед вводом пароля окно проверяет, что его запустили на ПК администратора и под учёткой администратора.
    # Если нет, предупреждает: пароль администратора домена, введённый на ПК сотрудника, могут перехватить.
    # ПК администратора: компьютер в этом OU (по данным групповой политики самого ПК) или в списке AdminPCs.
    # Оба пусты: проверка ПК выключена.
    AdminPcOu      = ''          # например 'OU=Admin PCs,OU=Computers,DC=example,DC=local'
    AdminPCs       = @()         # например @('IT-PC-01', 'IT-PC-02')
    # Учётка администратора: в токене «Администраторы домена» (SID ...-512, проверяется всегда, на любом языке)
    # или одна из этих групп
    AdminGroups    = @()         # например @('IT-Admins')

    # ---------------------------------------------------------------- что переносить

    # Части, которые не нужны: $false убирает галочку из окна
    EnableYandex    = $true      # Яндекс Браузер
    EnableCryptoPro = $true      # подписи КриптоПро и личные сертификаты

    # Папки сотрудника (пути внутри профиля C:\Users\<логин>), у каждой своя галочка в окне.
    # Key: латиница и цифры, без пробелов, не Yandex/Dpapi/Crypto*. Можно добавить свои, например
    # @{ Key = 'Pictures'; Title = 'Изображения'; Path = 'Pictures' } или @{ Key = 'Favorites'; Title = 'Избранное'; Path = 'Favorites' }
    Folders = @(
        @{ Key = 'Desktop';   Title = 'Рабочий стол'; Path = 'Desktop' }
        @{ Key = 'Documents'; Title = 'Документы';    Path = 'Documents' }
        @{ Key = 'Downloads'; Title = 'Загрузки';     Path = 'Downloads' }
    )
    # Эти файлы не переносим ни в каких папках
    FileExcludes = @('desktop.ini', 'Thumbs.db', '~$*', '*.tmp')

    # Яндекс Браузер: профиль целиком (закладки, пароли, вкладки, куки, расширения) без кэшей
    YandexPath = 'AppData\Local\Yandex\YandexBrowser\User Data'
    YandexExcludeDirs = @(
        'Cache', 'Code Cache', 'GPUCache', 'GrShaderCache', 'GraphiteDawnCache', 'ShaderCache',
        'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'CacheStorage', 'ScriptCache',
        'Crashpad', 'Crash Reports', 'BrowserMetrics', 'optimization_guide_model_store',
        'component_crx_cache', 'extensions_crx_cache', 'Safe Browsing', 'SwReporter'
    )
    YandexExcludeFiles = @('lockfile', '*.tmp', '*.pma')
    # Где искать сам браузер на новом ПК (только для предупреждения, если его там нет)
    YandexExe = @(
        'AppData\Local\Yandex\YandexBrowser\Application\browser.exe'
        'C:\Program Files (x86)\Yandex\YandexBrowser\Application\browser.exe'
        'C:\Program Files\Yandex\YandexBrowser\Application\browser.exe'
    )

    # Подписи КриптоПро и личные сертификаты
    CryptoProDir     = 'AppData\Local\Crypto Pro'                           # считыватель «Директория»
    CryptoProRegKeys = @(                                                   # считыватель «Реестр», {SID} = SID сотрудника
        'SOFTWARE\WOW6432Node\Crypto Pro\Settings\Users\{SID}\Keys'
        'SOFTWARE\Crypto Pro\Settings\Users\{SID}\Keys'
    )
    CryptoProPc      = 'C:\Program Files\Crypto Pro\CSP'                    # есть ли КриптоПро на новом ПК
    CertsMyPath      = 'AppData\Roaming\Microsoft\SystemCertificates\My'    # личные сертификаты
    CertsCryptoPath  = 'AppData\Roaming\Microsoft\Crypto'                   # ключи Windows (не ГОСТ) к личным сертификатам

    # Ключи DPAPI сотрудника: без них пароли и куки Яндекса на новом ПК не расшифруются
    DpapiPath        = 'AppData\Roaming\Microsoft\Protect\{SID}'
}
