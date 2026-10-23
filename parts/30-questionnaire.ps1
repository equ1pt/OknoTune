#region Questionnaire
# OnWhen: the answer that turns Items on. Revert: the other answer turns them back to Windows defaults.
# Sets: answering "yes" also flips these other questions. Detect: answer found from hardware.
$script:Detected = @{}
$Bloat = 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Clipchamp.Clipchamp', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
         'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub',
         'Microsoft.WindowsMaps', 'Microsoft.ZuneVideo', 'Microsoft.OutlookForWindows', 'Microsoft.MicrosoftOfficeHub', 'MSTeams', 'Microsoft.549981C3F5F10',
         'Microsoft.Windows.DevHome', 'Microsoft.MixedReality.Portal', 'Microsoft.Microsoft3DViewer', 'Microsoft.SkypeApp' | ForEach-Object { "app:$_" }
$script:Questions = @(
    @{ Section = 'Главное'; Id = 'privacy'; Text = 'Нужна максимальная приватность, даже ценой мелких функций?'; Default = 'no'; OnWhen = 'yes'; Revert = $false
       Hint = 'Отключим облачный поиск, сбор ввода, облачный буфер, телеметрию браузеров и сразу ответим «нет» на вопросы про ИИ, геолокацию, синхронизацию и фоновые приложения.'
       Items = 'inputpers', 'cloudsearch', 'crossclip', 'lockscreennotif', 'trackprogs', 'edgetel', 'chrometel', 'firefoxtel'
       Sets = @{ ai = 'no'; location = 'no'; insider = 'no'; bg = 'no'; sync = 'no'; msapps = 'no' } }
    @{ Section = 'Главное'; Id = 'games'; Text = 'Играете на этом компьютере?'; Default = 'no'; OnWhen = 'yes'; Revert = $false
       Hint = 'Включим аппаратное планирование GPU и приоритет игр, отключим фоновую запись, ускорение мыши и залипание клавиш по 5×Shift.'
       Items = 'gamedvr', 'hags', 'mmcss', 'mouse', 'sticky' }
    @{ Section = 'Главное'; Id = 'xbox'; Text = 'Играете в игры из Xbox, Game Pass или Microsoft Store?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим службы Xbox Live.'
       Items = 'xboxsvc' }

    @{ Section = 'О компьютере'; Id = 'laptop'; Text = 'Это ноутбук?'; Default = 'no'; OnWhen = 'no'; Revert = $true; Detect = 'laptop'
       Hint = 'На настольном ПК включим максимальную производительность, полное выключение, отключим засыпание USB, фоновые ограничения и датчики.'
       Items = 'powerplan', 'hiber', 'powerthrottle', 'usbsuspend', 'sensors' }
    @{ Section = 'О компьютере'; Id = 'ssd'; Text = 'Windows установлена на SSD?'; Default = 'yes'; OnWhen = 'yes'; Revert = $true; Detect = 'ssd'
       Hint = 'На SSD предзагрузка программ (SysMain) почти бесполезна и только нагружает систему.'
       Items = 'sysmain' }
    @{ Section = 'О компьютере'; Id = 'bt'; Text = 'Подключаете Bluetooth-устройства?'; Default = 'yes'; OnWhen = 'no'; Revert = $true; Detect = 'bt'
       Hint = 'Наушники, мышь, геймпад. Если нет, отключим службы Bluetooth.'
       Items = 'bluetooth' }
    @{ Section = 'О компьютере'; Id = 'cam'; Text = 'Пользуетесь веб-камерой?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим службы доступа к камере.'
       Items = 'camsvc' }
    @{ Section = 'О компьютере'; Id = 'bio'; Text = 'Входите в Windows по лицу или отпечатку?'; Default = 'yes'; OnWhen = 'no'; Revert = $true; Detect = 'bio'
       Hint = 'Если нет, отключим службу биометрии Windows Hello.'
       Items = 'hello' }
    @{ Section = 'О компьютере'; Id = 'printer'; Text = 'Печатаете на принтере или в PDF?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим службы печати и компонент XPS.'
       Items = 'spooler', 'xps' }
    @{ Section = 'О компьютере'; Id = 'drivers'; Text = 'Ставите драйверы видеокарты сами, с сайта NVIDIA, AMD или Intel?'; Default = 'no'; OnWhen = 'yes'; Revert = $true
       Hint = 'Если да, запретим Windows Update подменять их своими, часто более старыми.'
       Items = 'wudrivers' }

    @{ Section = 'Как вы пользуетесь Windows'; Id = 'search'; Text = 'Ищете файлы через поиск в Пуске или Проводнике?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим постоянную фоновую индексацию диска.'
       Items = 'wsearch' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'phone'; Text = 'Связываете телефон с ПК через «Связь с телефоном»?'; Default = 'yes'; OnWhen = 'no'; Revert = $false
       Hint = 'Если нет, удалим «Связь с телефоном» и отключим службы звонков и SMS.'
       Items = 'app:Microsoft.YourPhone', 'app:MicrosoftWindows.CrossDevice', 'phonesvc' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'tv'; Text = 'Транслируете видео с ПК на телевизор по сети (DLNA)?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим сетевое обнаружение UPnP и раздачу медиатеки.'
       Items = 'ssdp' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'voice'; Text = 'Пользуетесь голосовым вводом (Win+H) или диктовкой?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим отправку голоса на серверы Microsoft.'
       Items = 'speech' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'mailapps'; Text = 'Пользуетесь встроенными Почтой, Календарём или Контактами?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, запретим приложениям доступ к контактам, почте, календарю и звонкам.'
       Items = 'appprivacy' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'sync'; Text = 'Синхронизируете настройки Windows между ПК через аккаунт Microsoft?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим синхронизацию тем, паролей и настроек.'
       Items = 'settingsync' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'family'; Text = 'На ПК есть детский аккаунт Microsoft Family?'; Default = 'no'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим задачи и службу родительского контроля.'
       Items = 'family' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'oldapps'; Text = 'Запускаете старые программы (времён Windows 7 и раньше)?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим помощника совместимости программ.'
       Items = 'pca' }
    @{ Section = 'Как вы пользуетесь Windows'; Id = 'troubleshoot'; Text = 'Пользуетесь «Устранением неполадок» Windows?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим три диагностические службы.'
       Items = 'diag' }

    @{ Section = 'Функции Windows'; Id = 'ai'; Text = 'Пользуетесь Copilot и ИИ-функциями Windows?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим Copilot и Recall и удалим приложение Copilot.'
       Items = 'ai', 'recallfeat', 'app:Microsoft.Copilot' }
    @{ Section = 'Функции Windows'; Id = 'widgets'; Text = 'Нужны виджеты с новостями на панели задач?'; Default = 'no'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, уберём панель виджетов.'
       Items = 'widgets' }
    @{ Section = 'Функции Windows'; Id = 'msapps'; Text = 'Нужны встроенные приложения Microsoft?'; Default = 'yes'; OnWhen = 'no'; Revert = $false
       Hint = 'Новости, Погода, Советы, Solitaire, Clipchamp, To Do, Карты, новый Outlook, Teams и т. п. Если нет, удалим их (вернуть можно из Store).'
       Items = $Bloat }
    @{ Section = 'Функции Windows'; Id = 'bg'; Text = 'Нужны уведомления от приложений из Microsoft Store?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Например, WhatsApp или Telegram из Store. Если нет, запретим приложениям Store работать в фоне.'
       Items = 'bgapps' }
    @{ Section = 'Функции Windows'; Id = 'location'; Text = 'Нужны погода и часовой пояс по местоположению?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, отключим службы геолокации.'
       Items = 'location' }
    @{ Section = 'Функции Windows'; Id = 'insider'; Text = 'Хотите получать новые функции Windows раньше других?'; Default = 'yes'; OnWhen = 'no'; Revert = $true
       Hint = 'Если нет, запретим Microsoft включать на ПК экспериментальные функции.'
       Items = 'experiments' }

    @{ Section = 'Внешний вид и удобство'; Id = 'ui'; Text = 'Подправить мелочи в Проводнике и панели задач?'; Default = 'no'; OnWhen = 'yes'; Revert = $false
       Hint = 'Покажем расширения файлов, Проводник будет открывать «Этот компьютер», появится «Завершить задачу», уберём кнопку «Представление задач».'
       Items = 'fileext', 'launchto', 'endtask', 'taskview', 'sticky' }
    @{ Section = 'Внешний вид и удобство'; Id = 'ctx'; Text = 'Вернуть полное контекстное меню, как в Windows 10?'; Default = 'no'; OnWhen = 'yes'; Revert = $false
       Hint = 'Правый клик сразу покажет все пункты, без «Показать дополнительные параметры».'
       Items = 'ctxmenu' }
    @{ Section = 'Внешний вид и удобство'; Id = 'anim'; Text = 'Отключить анимации и прозрачность ради более быстрого отклика?'; Default = 'no'; OnWhen = 'yes'; Revert = $false
       Hint = 'Окна будут открываться и сворачиваться мгновенно, но интерфейс станет проще на вид.'
       Items = 'animations' }

    @{ Section = 'Безопасность'; Id = 'hardening'; Text = 'Закрыть старые сетевые уязвимости?'; Default = 'yes'; OnWhen = 'yes'; Revert = $false
       Hint = 'Отключим SMB 1.0, анонимный доступ, LLMNR и Удалённого помощника. Может перестать открываться очень старый сетевой диск (NAS).'
       Items = 'smb1', 'anon', 'llmnr', 'remoteassist' }
)
$script:QById = @{}; foreach ($q in $script:Questions) { $script:QById[$q.Id] = $q }
$script:Touched = @{}

function Find-Hardware {
    $script:Detected = @{}
    $script:Detected.laptop = $(if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { 'yes' } else { 'no' })
    try {
        $dn = (Get-Partition -DriveLetter $env:SystemDrive[0] -ErrorAction Stop).DiskNumber
        $pd = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$dn" } | Select-Object -First 1
        if ($pd) { $script:Detected.ssd = $(if ($pd.MediaType -eq 'SSD' -or $pd.BusType -eq 'NVMe') { 'yes' } else { 'no' }) }
    } catch {}
    # no such hardware => "no"; present => keep the regular default
    foreach ($pair in @(@('bt', 'Bluetooth'), @('bio', 'Biometric'))) {   # webcams are often unplugged, so no detection for them
        $found = Get-PnpDevice -PresentOnly -Class $pair[1..($pair.Count - 1)] -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
        if (-not $found) { $script:Detected[$pair[0]] = 'no' }
    }
}
function Get-Answers {
    $a = @{}
    foreach ($q in $script:Questions) {
        $a[$q.Id] = $q.Default
        # a question that can revert things must not undo what the user already did on this PC (even partly)
        if ($q.Revert) {
            $present = @($q.Items | Where-Object { $script:ItemsById.ContainsKey($_) } | ForEach-Object { $script:ItemsById[$_] })
            if (@($present | Where-Object { $_.State -ne 'off' }).Count) { $a[$q.Id] = $q.OnWhen }
        }
        if ($q.Detect -and $script:Detected[$q.Detect]) { $a[$q.Id] = $script:Detected[$q.Detect] }
    }
    $a
}
function Test-Question($q) { foreach ($id in $q.Items) { if ($script:ItemsById.ContainsKey($id)) { return $true } }; $false }
function Get-PlanWant($answers) {
    $want = @{}
    foreach ($it in $script:Items) { if ($it.Impact -eq 'none' -and $it.Auto) { $want[$it.Id] = $true } }
    foreach ($q in $script:Questions) {
        $match = $answers[$q.Id] -eq $q.OnWhen
        foreach ($id in $q.Items) {
            if ($id -like 'app:*' -and -not $script:Touched[$q.Id]) { continue }   # apps are removed only on an explicit click
            if ($match) { $want[$id] = $true }
            elseif ($q.Revert -and -not $want[$id]) { $want[$id] = $false }   # another question may already want it on
        }
    }
    $want
}
function Get-PlanCount($answers) {
    $want = Get-PlanWant $answers; $n = 0
    foreach ($it in $script:Items) {
        if (-not $want.ContainsKey($it.Id) -or ($it.Appx -and -not $want[$it.Id])) { continue }
        if ($want[$it.Id] -ne ($it.State -eq 'on')) { $n++ }
    }
    $n
}
#endregion
