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

    # ---------------------------------------------------------------- акт переноса

    # После «Развернуть на ПК» и «Перенести сразу» окно составляет акт переноса (HTML: что перенесено, объём, итог,
    # строки для подписи) и предлагает открыть его для печати. Акты лежат в logs\acts рядом с окном.
    # Кнопка «Акт» составит акт для выбранной копии в любой момент. $false: не составлять после развёртывания
    Act            = $true
    OrgName        = ''          # название организации в шапке акта, например 'ООО «Ромашка»'

    # ---------------------------------------------------------------- шифрование копий (7-Zip)

    # Копию можно зашифровать паролем: в хранилище уходит архив 7-Zip (AES-256, имена файлов тоже зашифрованы),
    # открытым остаётся только manifest.json (ФИО, логин, ПК, размеры). Нужен 7-Zip 16 или новее на ПК администратора.
    # Пароль окно спрашивает при снятии и при развёртывании и нигде не хранит: забыли пароль = копию не открыть.
    #   'Off'       без шифрования, галочки нет
    #   'Optional'  галочка «Зашифровать» есть, по умолчанию снята
    #   'On'        галочка по умолчанию стоит
    #   'Required'  только с шифрованием, галочку не снять
    Encrypt        = 'Optional'
    SevenZip       = ''          # путь к 7z.exe; пусто: C:\Program Files\7-Zip\7z.exe
    # Временная папка на этом ПК: зашифрованная копия собирается в ней (и распаковывается в неё при развёртывании),
    # потом папка стирается. Места нужно с копию. Пусто: %TEMP%\profile-move
    StagingDir     = ''

    # ---------------------------------------------------------------- обновления

    # Раз в день окно спрашивает GitHub (api.github.com), не вышла ли новая версия, и показывает ссылку на неё.
    # Ничего не скачивает и не отправляет, кроме самого запроса. $false: не спрашивать (например, без интернета)
    UpdateCheck    = $true
    UpdateRepo     = 'Nothingmaxxing/UserProfileMover'   # для форка: свой репозиторий

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

    # Папки сотрудника (пути внутри профиля C:\Users\<логин>), у каждой своя галочка в окне.
    # Key: латиница и цифры, без пробелов, не совпадает с Key браузеров, не Dpapi/Crypto*.
    # Файлы, которые на новом ПК новее, чем в копии, не перезаписываются
    Folders = @(
        @{ Key = 'Desktop';   Title = 'Рабочий стол'; Path = 'Desktop' }
        @{ Key = 'Documents'; Title = 'Документы';    Path = 'Documents' }
        @{ Key = 'Downloads'; Title = 'Загрузки';     Path = 'Downloads' }
        # Ещё варианты: уберите # в начале строки
        # @{ Key = 'Pictures';  Title = 'Изображения'; Path = 'Pictures' }
        # @{ Key = 'Favorites'; Title = 'Избранное';   Path = 'Favorites' }
        # @{ Key = 'Signatures'; Title = 'Подписи писем Outlook'; Path = 'AppData\Roaming\Microsoft\Signatures' }
        # @{ Key = 'OfficeTpl'; Title = 'Шаблоны Word (Normal.dotm)'; Path = 'AppData\Roaming\Microsoft\Templates' }
        # @{ Key = 'Ibases1C';  Title = 'Список баз 1С'; Path = 'AppData\Roaming\1C\1CEStart' }   # 1С на новом ПК до переноса не запускать
    )
    # Эти файлы не переносим ни в каких папках
    FileExcludes = @('desktop.ini', 'Thumbs.db', '~$*', '*.tmp')

    # Браузеры: у каждого своя галочка, профиль переносится целиком (закладки, пароли, вкладки, куки, расширения) без кэшей.
    #   Key       латиница и цифры: так называется папка браузера в копии
    #   UserData  папка профиля внутри C:\Users\<логин>; можно несколько, берётся первая найденная на старом ПК
    #   Dpapi     пароли и куки зашифрованы DPAPI сотрудника (все браузеры на Chromium): вместе с браузером
    #             переносятся ключи DPAPI. Firefox шифрует пароли сам, ему $false
    #   LockFiles файлы, занятые, пока браузер открыт (путь внутри UserData, можно с *). Нет: как у Chromium
    #   ExcludeDirs, ExcludeFiles  что не копировать. Нет: кэши Chromium (ChromiumExcludeDirs ниже)
    #   Exe       где искать браузер на новом ПК: если не найден, окно предупредит
    #   Note      что сказать после переноса
    # Ненужный браузер: Enabled = $false или удалить блок. Нет на ПК сотрудника: в журнале «нечего переносить»
    Browsers = @(
        @{
            Key = 'Yandex'; Title = 'Яндекс Браузер'
            UserData = @('AppData\Local\Yandex\YandexBrowser\User Data')
            Exe = @(
                'AppData\Local\Yandex\YandexBrowser\Application\browser.exe'
                'C:\Program Files (x86)\Yandex\YandexBrowser\Application\browser.exe'
                'C:\Program Files\Yandex\YandexBrowser\Application\browser.exe'
            )
        }
        @{
            # Chromium с ГОСТ-шифрованием (github.com/deemru/Chromium-Gost): ставится в профиль пользователя
            Key = 'ChromiumGost'; Title = 'Chromium-Gost'
            UserData = @('AppData\Local\Chromium\User Data')
            Exe = @(
                'AppData\Local\Chromium\Application\chrome.exe'
                'C:\Program Files\Chromium\Application\chrome.exe'
                'C:\Program Files (x86)\Chromium\Application\chrome.exe'
            )
        }
        @{
            Key = 'Chrome'; Title = 'Google Chrome'
            UserData = @('AppData\Local\Google\Chrome\User Data')
            Exe = @(
                'C:\Program Files\Google\Chrome\Application\chrome.exe'
                'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
                'AppData\Local\Google\Chrome\Application\chrome.exe'
            )
            Note = 'Chrome с версии 127 привязывает шифрование куки к самому ПК: на сайты, скорее всего, придётся войти заново.'
        }
        @{
            Key = 'Edge'; Title = 'Microsoft Edge'
            UserData = @('AppData\Local\Microsoft\Edge\User Data')
            Exe = @(
                'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
                'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
            )
            Note = 'Edge может привязывать шифрование куки к самому ПК: если входы на сайты слетели, войти заново.'
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
            Note = 'Если Firefox на новом ПК стоит в другой папке, он может открыть пустой профиль: перенесённый выбрать в about:profiles.'
        }
    )
    # Для браузеров на Chromium без своих ExcludeDirs, ExcludeFiles, LockFiles
    ChromiumExcludeDirs = @(
        'Cache', 'Code Cache', 'GPUCache', 'GrShaderCache', 'GraphiteDawnCache', 'ShaderCache',
        'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'CacheStorage', 'ScriptCache',
        'Crashpad', 'Crash Reports', 'BrowserMetrics', 'optimization_guide_model_store',
        'component_crx_cache', 'extensions_crx_cache', 'Safe Browsing', 'SwReporter'
    )
    ChromiumExcludeFiles = @('lockfile', '*.tmp', '*.pma')
    ChromiumLockFiles    = @('lockfile', 'Default\Network\Cookies')

    # Подписи КриптоПро и личные сертификаты. $false убирает галочку из окна
    EnableCryptoPro  = $true

    CryptoProDir     = 'AppData\Local\Crypto Pro'                           # считыватель «Директория»
    CryptoProRegKeys = @(                                                   # считыватель «Реестр», {SID} = SID сотрудника
        'SOFTWARE\WOW6432Node\Crypto Pro\Settings\Users\{SID}\Keys'
        'SOFTWARE\Crypto Pro\Settings\Users\{SID}\Keys'
    )
    CryptoProPc      = 'C:\Program Files\Crypto Pro\CSP'                    # есть ли КриптоПро на новом ПК
    CertsMyPath      = 'AppData\Roaming\Microsoft\SystemCertificates\My'    # личные сертификаты
    CertsCryptoPath  = 'AppData\Roaming\Microsoft\Crypto'                   # ключи Windows (не ГОСТ) к личным сертификатам

    # Ключи DPAPI сотрудника: без них пароли и куки браузеров на Chromium на новом ПК не расшифруются
    DpapiPath        = 'AppData\Roaming\Microsoft\Protect\{SID}'
}
