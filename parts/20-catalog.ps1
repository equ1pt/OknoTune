#region Tweak catalog
# Impact: none = nothing is lost; minor = small limitation; breaks = a Windows feature stops working; remove = app removal.
# Auto = $false keeps a green item out of the automatic set (it changes how Windows looks, so it is asked about).
$script:AllItems = New-Object System.Collections.Generic.List[object]
function AsArray($x) { if ($null -eq $x) { , @() } else { , @($x) } }
function RegV($p, $n, $v, $d, $t = 'DWord') { @{ P = $p; N = $n; V = $v; D = $d; T = $t } }   # D = Windows default, $null = value absent
function SvcV($s, $v, $d) { @{ S = $s; V = $v; D = $d } }
function Add-Tweak([hashtable]$h) {
    $script:AllItems.Add([pscustomobject]@{
        Id = $h.Id; Cat = $h.Cat; Title = $h.Title; Short = $h.Short; Desc = $h.Desc; Warn = $h.Warn
        Impact = $(if ($h.Impact) { $h.Impact } else { 'none' }); Auto = $(if ($h.ContainsKey('Auto')) { [bool]$h.Auto } else { $true }); Reboot = [bool]$h.Reboot
        Reg = (AsArray $h.Reg); Svc = (AsArray $h.Svc); Task = (AsArray $h.Task); Feature = (AsArray $h.Feature); Appx = $h.Appx
        Check = $h.Check; On = $h.On; Off = $h.Off; Save = $h.Save; Load = $h.Load; Avail = $h.Avail
        State = 'off'; Card = $null; Toggle = $null; StatusTb = $null
    })
}
$Pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$Adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$MM = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$AP = "$Pol\AppPrivacy"
$Sch = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
$Win11 = { [Environment]::OSVersion.Version.Build -ge 22000 }
$CtxKey = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$Tel = '\Microsoft\Windows\Application Experience\'

# --- Приватность
Add-Tweak @{ Id = 'telemetry'; Cat = 'Приватность'; Title = 'Телеметрия на минимум'; Short = 'Меньше данных уходит в Microsoft'
    Desc = 'Минимальный уровень диагностических данных, отключены службы DiagTrack, WAP Push и сборщик диагностики. Обновления Windows работают как обычно.'
    Reg = (RegV "$Pol\DataCollection" AllowTelemetry 0 $null), (RegV "$Pol\DataCollection" AllowCommercialDataPipeline 0 $null)
    Svc = (SvcV DiagTrack Disabled Automatic), (SvcV dmwappushservice Disabled Manual), (SvcV diagnosticshub.standardcollector.service Disabled Manual) }
Add-Tweak @{ Id = 'adid'; Cat = 'Приватность'; Title = 'Рекламный идентификатор'; Short = 'Нет рекламной слежки между приложениями'
    Desc = 'Приложения не смогут связывать вас между собой по рекламному ID.'
    Reg = (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' Enabled 0 1) }
Add-Tweak @{ Id = 'activity'; Cat = 'Приватность'; Title = 'История действий'; Short = 'Windows не ведёт историю ваших действий'
    Desc = 'Windows не собирает и не отправляет историю запущенных приложений и открытых файлов.'
    Reg = (RegV "$Pol\System" EnableActivityFeed 0 $null), (RegV "$Pol\System" PublishUserActivities 0 $null), (RegV "$Pol\System" UploadUserActivities 0 $null) }
Add-Tweak @{ Id = 'wer'; Cat = 'Приватность'; Title = 'Отчёты об ошибках'; Short = 'Сбои программ не отправляются в Microsoft'
    Desc = 'Windows не отправляет в Microsoft отчёты о сбоях программ. Отключены служба и задача отчётов.'
    Reg = (RegV "$Pol\Windows Error Reporting" Disabled 1 $null)
    Svc = (SvcV WerSvc Disabled Manual)
    Task = '\Microsoft\Windows\Windows Error Reporting\QueueReporting' }
Add-Tweak @{ Id = 'ceip'; Cat = 'Приватность'; Title = 'Программа улучшения качества (CEIP)'; Short = 'Без сбора статистики использования'
    Desc = 'Отключает сбор статистики использования и её задачи в планировщике.'
    Reg = (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' CEIPEnable 0 $null)
    Task = '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator', '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip', '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask' }
Add-Tweak @{ Id = 'feedback'; Cat = 'Приватность'; Title = 'Запросы отзывов'; Short = 'Без окон «Оцените Windows»'
    Desc = 'Windows перестанет показывать окна «Оцените Windows» и уведомления с просьбой оставить отзыв.'
    Reg = (RegV 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' NumberOfSIUFInPeriod 0 $null), (RegV "$Pol\DataCollection" DoNotShowFeedbackNotifications 1 $null)
    Task = '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast', '\Microsoft\Windows\Feedback\Siuf\DmClient', '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload' }
Add-Tweak @{ Id = 'teltasks'; Cat = 'Приватность'; Title = 'Задачи сбора данных'; Short = 'Меньше фоновых задач, которые собирают данные'
    Desc = 'Отключает задачи планировщика, которые собирают сведения об устройстве, дисках и совместимости программ.'
    Task = '\Microsoft\Windows\Device Information\Device', '\Microsoft\Windows\Device Information\Device User',
           "${Tel}Microsoft Compatibility Appraiser", "${Tel}Microsoft Compatibility Appraiser Exp", "${Tel}ProgramDataUpdater", "${Tel}PcaPatchDbTask", "${Tel}MareBackup",
           '\Microsoft\Windows\Sustainability\SustainabilityTelemetry', '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector', '\Microsoft\Windows\Autochk\Proxy' }
Add-Tweak @{ Id = 'nvtel'; Cat = 'Приватность'; Title = 'Телеметрия NVIDIA'; Short = 'Драйвер NVIDIA не отправляет статистику'
    Desc = 'Драйвер и панель управления NVIDIA не отправляют статистику использования.'
    Avail = { Test-Path 'HKLM:\SOFTWARE\NVIDIA Corporation' }
    Reg = (RegV 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' OptInOrOutPreference 0 $null),
          (RegV 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' EnableRID44231 0 $null), (RegV 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' EnableRID64640 0 $null),
          (RegV 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' EnableRID66610 0 $null),
          (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\Startup' SendTelemetryData 0 $null) }
Add-Tweak @{ Id = 'office'; Cat = 'Приватность'; Title = 'Телеметрия Microsoft Office'; Short = 'Office не отправляет статистику'
    Desc = 'Отключает телеметрию, журналирование и запросы отзывов в Office 2016–365, а также задачи телеметрии Office.'
    Avail = { Test-Path 'HKCU:\Software\Microsoft\Office\16.0' }
    Reg = (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\ClientTelemetry' DisableTelemetry 1 $null), (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\ClientTelemetry' SendTelemetry 3 $null),
          (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\OSM' EnableLogging 0 $null), (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\OSM' EnableUpload 0 $null),
          (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common' QMEnable 0 $null), (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\Feedback' Enabled 0 $null)
    Task = '\Microsoft\Office\OfficeTelemetryAgentFallBack2016', '\Microsoft\Office\OfficeTelemetryAgentLogOn2016' }
Add-Tweak @{ Id = 'devtel'; Cat = 'Приватность'; Title = 'Телеметрия инструментов разработчика'; Short = 'Visual Studio, .NET и PowerShell не шлют статистику'
    Desc = 'Отключает программу улучшения и окна отзывов Visual Studio, телеметрию .NET CLI и PowerShell 7 (переменные окружения).'
    Avail = { (Test-Path 'HKLM:\SOFTWARE\Microsoft\VisualStudio') -or (Get-Command dotnet, pwsh -ErrorAction SilentlyContinue) }
    Reg = (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\SQM' OptIn 0 $null), (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Feedback' DisableFeedbackDialog 1 $null),
          (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Feedback' DisableScreenshotCapture 1 $null),
          (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' DOTNET_CLI_TELEMETRY_OPTOUT '1' $null 'String'),
          (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' POWERSHELL_TELEMETRY_OPTOUT '1' $null 'String') }
Add-Tweak @{ Id = 'wifisense'; Cat = 'Приватность'; Title = 'Wi-Fi Sense'; Short = 'Без автоподключения к чужим точкам Wi-Fi'
    Desc = 'Windows не подключается автоматически к открытым точкам доступа, о которых сообщили другие пользователи, и не отправляет сведения о них.'
    Reg = (RegV 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' value 0 1), (RegV 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' value 0 1) }
Add-Tweak @{ Id = 'httplang'; Cat = 'Приватность'; Title = 'Список языков для сайтов'; Short = 'Сайты не видят список ваших языков'
    Desc = 'Windows не сообщает сайтам список установленных языков, по которому вас проще отличить от других.'
    Reg = (RegV 'HKCU:\Control Panel\International\User Profile' HttpAcceptLanguageOptOut 1 $null) }
Add-Tweak @{ Id = 'inputpers'; Cat = 'Приватность'; Title = 'Сбор рукописного и клавиатурного ввода'; Impact = 'minor'; Short = 'Windows не учится на том, что вы печатаете'
    Desc = 'Отключает сбор образцов рукописного и клавиатурного ввода и контактов для «персонализации».'
    Warn = 'Подсказки при наборе станут менее точными'
    Reg = (RegV 'HKCU:\Software\Microsoft\InputPersonalization' RestrictImplicitInkCollection 1 0), (RegV 'HKCU:\Software\Microsoft\InputPersonalization' RestrictImplicitTextCollection 1 0),
          (RegV 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' HarvestContacts 0 1), (RegV 'HKCU:\Software\Microsoft\Personalization\Settings' AcceptedPrivacyPolicy 0 $null) }
Add-Tweak @{ Id = 'cloudsearch'; Cat = 'Приватность'; Title = 'Облако и история в поиске'; Impact = 'minor'; Short = 'Поиск не лезет в облако и не хранит историю'
    Desc = 'Поиск Windows не показывает результаты из OneDrive, Outlook и рабочих аккаунтов и не хранит историю запросов на устройстве.'
    Warn = 'В поиске не будет файлов из OneDrive и писем Outlook'
    Reg = (RegV "$Pol\Windows Search" AllowCloudSearch 0 $null), (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' IsDeviceSearchHistoryEnabled 0 1),
          (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' IsMSACloudSearchEnabled 0 1), (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' IsAADCloudSearchEnabled 0 1) }
Add-Tweak @{ Id = 'crossclip'; Cat = 'Приватность'; Title = 'Облачный буфер обмена'; Impact = 'minor'; Short = 'Буфер обмена не уходит в облако'
    Desc = 'Запрещает синхронизацию буфера обмена между устройствами. Журнал буфера (Win+V) на этом ПК работает.'
    Warn = 'Скопированное не будет появляться на других ваших устройствах'
    Reg = (RegV "$Pol\System" AllowCrossDeviceClipboard 0 $null) }
Add-Tweak @{ Id = 'lockscreennotif'; Cat = 'Приватность'; Title = 'Уведомления на экране блокировки'; Impact = 'minor'; Short = 'Чужие не прочитают уведомления на заблокированном ПК'
    Desc = 'Уведомления приложений не показываются на экране блокировки.'
    Warn = 'Уведомления будут видны только после входа'
    Reg = (RegV "$Pol\System" DisableLockScreenAppNotifications 1 $null) }
Add-Tweak @{ Id = 'trackprogs'; Cat = 'Приватность'; Title = 'Отслеживание запуска программ'; Impact = 'minor'; Short = 'Windows не следит, что вы запускаете'
    Desc = 'Windows перестаёт запоминать, какие программы вы запускаете чаще.'
    Warn = 'В Пуске пропадёт список часто используемых приложений'
    Reg = (RegV $Adv Start_TrackProgs 0 1) }
Add-Tweak @{ Id = 'ai'; Cat = 'Приватность'; Title = 'Copilot и Recall'; Impact = 'breaks'; Short = 'Без Copilot и снимков экрана Recall'
    Desc = 'Отключает Copilot, его кнопку и службу ИИ-платформы, запрещает Recall, который периодически делает снимки экрана.'
    Warn = 'Copilot и ИИ-функции Windows перестанут работать'
    Reg = (RegV 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1 $null), (RegV "$Pol\WindowsCopilot" TurnOffWindowsCopilot 1 $null),
          (RegV "$Pol\WindowsAI" DisableAIDataAnalysis 1 $null), (RegV "$Pol\WindowsAI" AllowRecallEnablement 0 $null),
          (RegV 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' DisableAIDataAnalysis 1 $null), (RegV $Adv ShowCopilotButton 0 $null)
    Svc = (SvcV WSAIFabricSvc Disabled Manual) }
Add-Tweak @{ Id = 'experiments'; Cat = 'Приватность'; Title = 'Эксперименты Microsoft'; Impact = 'minor'; Short = 'Microsoft не тестирует функции на вашем ПК'
    Desc = 'Microsoft не будет удалённо включать тестовые функции. Отключены служба Insider и задачи Flighting.'
    Warn = 'Новые функции Windows будут приходить позже'
    Reg = (RegV "$Pol\PreviewBuilds" EnableExperimentation 0 $null), (RegV "$Pol\PreviewBuilds" EnableConfigFlighting 0 $null), (RegV "$Pol\PreviewBuilds" AllowBuildPreview 0 $null)
    Svc = (SvcV wisvc Disabled Manual)
    Task = '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures', '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing', '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting', '\Microsoft\Windows\Flighting\OneSettings\RefreshCache' }
Add-Tweak @{ Id = 'settingsync'; Cat = 'Приватность'; Title = 'Синхронизация настроек'; Impact = 'minor'; Short = 'Настройки не уходят в аккаунт Microsoft'
    Desc = 'Windows не синхронизирует темы, пароли, языки и другие настройки через аккаунт Microsoft.'
    Warn = 'На другом ПК под тем же аккаунтом настройки не подтянутся'
    Reg = (RegV "$Pol\SettingSync" DisableSettingSync 2 $null), (RegV "$Pol\SettingSync" DisableSettingSyncUserOverride 1 $null) }
Add-Tweak @{ Id = 'location'; Cat = 'Приватность'; Title = 'Служба геолокации'; Impact = 'breaks'; Short = 'Приложения не узнают, где вы'
    Desc = 'Отключает службы определения местоположения и автоматического часового пояса.'
    Warn = 'Погода, карты и автоматический часовой пояс не определят местоположение'
    Svc = (SvcV lfsvc Disabled Manual), (SvcV tzautoupdate Disabled Manual) }
Add-Tweak @{ Id = 'speech'; Cat = 'Приватность'; Title = 'Онлайн-распознавание речи'; Impact = 'breaks'; Short = 'Голос не отправляется на серверы Microsoft'
    Desc = 'Отключает облачное распознавание речи.'
    Warn = 'Перестанут работать голосовой ввод (Win+H) и диктовка'
    Reg = (RegV 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' HasAccepted 0 1) }
Add-Tweak @{ Id = 'appprivacy'; Cat = 'Приватность'; Title = 'Доступ приложений к личным данным'; Impact = 'breaks'; Short = 'Приложения не видят контакты, почту и календарь'
    Desc = 'Запрещает приложениям из Store доступ к аккаунту, контактам, календарю, почте, звонкам, сообщениям, задачам, датчикам движения и диагностике.'
    Warn = 'Встроенные Почта, Календарь и Люди не получат доступ к вашим данным'
    Reg = 'AccountInfo', 'Contacts', 'Calendar', 'CallHistory', 'Email', 'Messaging', 'Tasks', 'Motion', 'Radios', 'TrustedDevices', 'SyncWithDevices', 'GetDiagnosticInfo' | ForEach-Object { RegV $AP "LetApps$($_ -replace '^(?!Get|Sync)', 'Access')" 2 $null } }
Add-Tweak @{ Id = 'family'; Cat = 'Приватность'; Title = 'Семейная безопасность'; Impact = 'breaks'; Short = 'Минус две задачи и служба родительского контроля'
    Desc = 'Отключает задачи и службу Microsoft Family, которые проверяют ограничения детского аккаунта.'
    Warn = 'Перестанут работать ограничения детского аккаунта Microsoft'
    Svc = (SvcV WpcMonSvc Disabled Manual)
    Task = '\Microsoft\Windows\Shell\FamilySafetyMonitor', '\Microsoft\Windows\Shell\FamilySafetyRefreshTask' }
Add-Tweak @{ Id = 'edgetel'; Cat = 'Приватность'; Title = 'Телеметрия Edge'; Impact = 'minor'; Auto = $false; Short = 'Edge не отправляет статистику и не навязывает покупки'
    Desc = 'Политики Edge: без телеметрии, отчётов о сайтах, персонализации, помощника покупок, рекомендаций и боковой панели Copilot.'
    Warn = 'В Edge появится надпись «Браузером управляет ваша организация»'
    Reg = 'MetricsReportingEnabled', 'SendSiteInfoToImproveServices', 'PersonalizationReportingEnabled', 'DiagnosticData', 'EdgeShoppingAssistantEnabled', 'ShowRecommendationsEnabled', 'HubsSidebarEnabled' |
          ForEach-Object { RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' $_ 0 $null } }
Add-Tweak @{ Id = 'chrometel'; Cat = 'Приватность'; Title = 'Телеметрия Chrome'; Impact = 'minor'; Auto = $false; Short = 'Chrome не отправляет статистику'
    Desc = 'Политики Chrome: без отчётов об использовании, отчётов Chrome Cleanup и отзывов.'
    Warn = 'В Chrome появится надпись «Браузером управляет ваша организация»'
    Avail = { (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") }
    Reg = (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' MetricsReportingEnabled 0 $null), (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' ChromeCleanupReportingEnabled 0 $null), (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' UserFeedbackAllowed 0 $null) }
Add-Tweak @{ Id = 'firefoxtel'; Cat = 'Приватность'; Title = 'Телеметрия Firefox'; Impact = 'minor'; Auto = $false; Short = 'Firefox не отправляет статистику'
    Desc = 'Политики Firefox: без телеметрии и фонового агента браузера по умолчанию.'
    Warn = 'В настройках Firefox появится надпись «Браузером управляет ваша организация»'
    Avail = { Test-Path "$env:ProgramFiles\Mozilla Firefox\firefox.exe" }
    Reg = (RegV 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' DisableTelemetry 1 $null), (RegV 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' DisableDefaultBrowserAgent 1 $null) }

# --- Реклама
Add-Tweak @{ Id = 'cdm'; Cat = 'Реклама'; Title = 'Автоустановка приложений и советы'; Short = 'Windows не ставит рекламные приложения'
    Desc = 'Windows перестанет сама устанавливать рекламные приложения и показывать «советы» в Пуске и Параметрах.'
    Reg = (RegV $CDM SilentInstalledAppsEnabled 0 1), (RegV $CDM SystemPaneSuggestionsEnabled 0 1), (RegV $CDM SoftLandingEnabled 0 1),
          (RegV $CDM OemPreInstalledAppsEnabled 0 1), (RegV $CDM PreInstalledAppsEnabled 0 1),
          (RegV $CDM 'SubscribedContent-338388Enabled' 0 1), (RegV $CDM 'SubscribedContent-338389Enabled' 0 1), (RegV $CDM 'SubscribedContent-338393Enabled' 0 1),
          (RegV $CDM 'SubscribedContent-353694Enabled' 0 1), (RegV $CDM 'SubscribedContent-353696Enabled' 0 1) }
Add-Tweak @{ Id = 'consumer'; Cat = 'Реклама'; Title = 'Предложения Microsoft (политика)'; Short = 'Запрет рекламного контента на уровне системы'
    Desc = 'Запрещает политикой установку «рекомендуемых» приложений и рекламного контента.'
    Reg = (RegV "$Pol\CloudContent" DisableWindowsConsumerFeatures 1 $null), (RegV "$Pol\CloudContent" DisableSoftLanding 1 $null), (RegV "$Pol\CloudContent" DisableCloudOptimizedContent 1 $null) }
Add-Tweak @{ Id = 'lockads'; Cat = 'Реклама'; Title = 'Реклама на экране блокировки'; Short = 'Без «интересных фактов» и рекламы на экране блокировки'
    Desc = 'Убирает подсказки, факты и рекламу поверх фона экрана блокировки.'
    Reg = (RegV $CDM RotatingLockScreenOverlayEnabled 0 1), (RegV $CDM 'SubscribedContent-338387Enabled' 0 1) }
Add-Tweak @{ Id = 'nags'; Cat = 'Реклама'; Title = 'Навязчивые предложения'; Short = 'Без «Давайте завершим настройку» и рекламных уведомлений'
    Desc = 'Убирает экран «Давайте завершим настройку устройства» после обновлений и уведомления с советами и предложениями.'
    Reg = (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' ScoobeSystemSettingEnabled 0 $null),
          (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested' Enabled 0 $null) }
Add-Tweak @{ Id = 'explorerads'; Cat = 'Реклама'; Title = 'Реклама в Проводнике'; Short = 'Проводник не рекламирует OneDrive и Microsoft 365'
    Desc = 'Убирает уведомления поставщиков синхронизации (рекламу OneDrive и Microsoft 365) в Проводнике.'
    Reg = (RegV $Adv ShowSyncProviderNotifications 0 1) }
Add-Tweak @{ Id = 'bing'; Cat = 'Реклама'; Title = 'Bing в поиске Windows'; Reboot = $true; Short = 'Поиск в Пуске без интернета и рекламы'
    Desc = 'Поиск в меню Пуск ищет только на компьютере, без веб-результатов Bing.'
    Reg = (RegV 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1 $null) }
Add-Tweak @{ Id = 'startrec'; Cat = 'Реклама'; Title = 'Рекомендации в Пуске'; Avail = $Win11; Short = 'Пуск без рекламы приложений'
    Desc = 'Убирает рекламные рекомендации приложений из меню Пуск.'
    Reg = (RegV $Adv Start_IrisRecommendations 0 1) }
Add-Tweak @{ Id = 'widgets'; Cat = 'Реклама'; Title = 'Виджеты и новости'; Impact = 'minor'; Reboot = $true; Avail = $Win11; Short = 'Без ленты новостей на панели задач'
    Desc = 'Убирает панель виджетов с новостями и погодой из панели задач.'
    Warn = 'Пропадёт панель виджетов'
    Reg = (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests 0 $null) }

# --- Игры
Add-Tweak @{ Id = 'gamedvr'; Cat = 'Игры'; Title = 'Фоновая запись Xbox Game Bar'; Impact = 'minor'; Reboot = $true; Short = 'Игры не записываются в фоне: выше FPS'
    Desc = 'Game Bar не записывает игровой процесс в фоне и не тратит на это ресурсы. Сам Game Bar остаётся.'
    Warn = 'Не будет функции «Записать последние 30 секунд»'
    Reg = (RegV 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' AppCaptureEnabled 0 1), (RegV 'HKCU:\System\GameConfigStore' GameDVR_Enabled 0 1) }
Add-Tweak @{ Id = 'mouse'; Cat = 'Игры'; Title = 'Ускорение мыши'; Impact = 'minor'; Short = 'Точное прицеливание без ускорения'
    Desc = 'Отключает «Повышенную точность указателя»: курсор движется ровно на столько, на сколько вы двигаете мышь. Сработает после повторного входа.'
    Warn = 'Курсор поначалу будет ощущаться иначе'
    Reg = (RegV 'HKCU:\Control Panel\Mouse' MouseSpeed '0' '1' 'String'), (RegV 'HKCU:\Control Panel\Mouse' MouseThreshold1 '0' '6' 'String'), (RegV 'HKCU:\Control Panel\Mouse' MouseThreshold2 '0' '10' 'String') }
Add-Tweak @{ Id = 'hags'; Cat = 'Игры'; Title = 'Аппаратное планирование GPU (HAGS)'; Impact = 'minor'; Reboot = $true; Short = 'Ниже задержка, нужно для DLSS Frame Generation'
    Desc = 'Видеокарта сама управляет своей памятью: ниже задержка ввода. Обязательно для DLSS Frame Generation.'
    Warn = 'На старых видеокартах и драйверах возможны подтормаживания'
    Reg = (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode 2 1) }
Add-Tweak @{ Id = 'mmcss'; Cat = 'Игры'; Title = 'Приоритет игр и мультимедиа'; Impact = 'minor'; Short = 'Игры получают больше процессора и видеокарты'
    Desc = 'Повышает приоритет игр в планировщике мультимедиа (CPU, GPU, диск), снимает ограничение скорости сети во время игр и музыки.'
    Warn = 'Фоновые задачи получат чуть меньше ресурсов во время игры'
    Reg = (RegV $MM NetworkThrottlingIndex 4294967295 10), (RegV $MM SystemResponsiveness 10 20),
          (RegV "$MM\Tasks\Games" Priority 6 2), (RegV "$MM\Tasks\Games" 'Scheduling Category' 'High' 'Medium' 'String'), (RegV "$MM\Tasks\Games" 'SFIO Priority' 'High' 'Normal' 'String') }
Add-Tweak @{ Id = 'powerplan'; Cat = 'Игры'; Title = 'Максимальная производительность'; Impact = 'minor'; Short = 'Процессор не сбрасывает частоты: меньше подтормаживаний'
    Desc = 'Включает план питания «Максимальная производительность» (если его нет, создаёт). Отмена возвращает прежний план.'
    Warn = 'Выше энергопотребление и нагрев'
    Check = { "$(powercfg /getactivescheme)" -match $FastPlanRx }
    Save = { ([regex]$GuidRx).Match("$(powercfg /getactivescheme)").Value }
    Load = { param($g) powercfg /setactive $g | Out-Null }
    On = {
        $line = powercfg /list | Select-String $FastPlanRx | Select-Object -First 1
        if (-not $line) { $line = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 }
        $g = ([regex]$GuidRx).Match("$line").Value
        if (-not $g) { throw 'не удалось найти или создать план питания' }
        powercfg /setactive $g | Out-Null
    }
    Off = { powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null } }
Add-Tweak @{ Id = 'powerthrottle'; Cat = 'Игры'; Title = 'Ограничение фоновых программ (Power Throttling)'; Impact = 'minor'; Reboot = $true; Short = 'Windows не притормаживает программы в фоне'
    Desc = 'Программы в фоне (стримы, сборка, рендер) не переводятся в энергосберегающий режим. Имеет смысл на настольном ПК.'
    Warn = 'Выше энергопотребление'
    Reg = (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' PowerThrottlingOff 1 $null) }
Add-Tweak @{ Id = 'usbsuspend'; Cat = 'Игры'; Title = 'Отключение USB для экономии энергии'; Impact = 'minor'; Short = 'Мышь, гарнитура и геймпад не «засыпают»'
    Desc = 'Запрещает Windows выключать USB-порты для экономии энергии (в текущем плане питания, при питании от сети). Лечит пропадание USB-устройств.'
    Warn = 'Чуть выше энергопотребление'
    Check = { "$(powercfg /q SCHEME_CURRENT $UsbSub $UsbSet)" -match '(Current AC Power Setting Index|от сети):\s*0x0+\b' }
    On = { powercfg /setacvalueindex SCHEME_CURRENT $UsbSub $UsbSet 0 | Out-Null; powercfg /setactive SCHEME_CURRENT | Out-Null }
    Off = { powercfg /setacvalueindex SCHEME_CURRENT $UsbSub $UsbSet 1 | Out-Null; powercfg /setactive SCHEME_CURRENT | Out-Null } }
Add-Tweak @{ Id = 'xboxsvc'; Cat = 'Игры'; Title = 'Службы Xbox Live'; Impact = 'breaks'; Short = 'Минус три службы Xbox в фоне'
    Desc = 'Отключает службы входа в Xbox Live, сохранений и сети Xbox.'
    Warn = 'Игры из Xbox, Game Pass и Microsoft Store перестанут запускаться и сохраняться в облако'
    Svc = (SvcV XblAuthManager Disabled Manual), (SvcV XblGameSave Disabled Manual), (SvcV XboxNetApiSvc Disabled Manual) }

# --- Система
Add-Tweak @{ Id = 'hiber'; Cat = 'Система'; Title = 'Быстрый запуск и гибернация'; Impact = 'minor'; Reboot = $true; Short = 'Полное выключение и несколько ГБ места на диске'
    Desc = 'Выключение становится полным, это лечит часть странных глюков после «сна». Удаляет файл гибернации.'
    Warn = 'Пропадёт режим гибернации, включение станет на 1–2 секунды дольше'
    Reg = (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' HiberbootEnabled 0 1)
    Check = { (Get-RegRaw 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled').Value -eq '0' }
    On = { powercfg /h off | Out-Null }; Off = { powercfg /h on | Out-Null } }
Add-Tweak @{ Id = 'sysmain'; Cat = 'Система'; Title = 'SysMain (SuperFetch)'; Impact = 'minor'; Short = 'Меньше фоновой нагрузки на диск и память'
    Desc = 'Служба предзагрузки программ в память. На SSD почти бесполезна.'
    Warn = 'На HDD программы будут запускаться медленнее'
    Svc = (SvcV SysMain Disabled Automatic) }
Add-Tweak @{ Id = 'startupdelay'; Cat = 'Система'; Title = 'Задержка автозагрузки'; Short = 'Программы из автозагрузки стартуют сразу'
    Desc = 'Windows больше не придерживает запуск программ из автозагрузки на несколько секунд после входа.'
    Reg = (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' StartupDelayInMSec 0 $null), (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' WaitForIdleState 0 $null) }
Add-Tweak @{ Id = 'lastaccess'; Cat = 'Система'; Title = 'Метка последнего доступа NTFS'; Short = 'Меньше лишних записей на диск'
    Desc = 'NTFS перестанет записывать время последнего открытия каждого файла.'
    Check = { (fsutil behavior query disablelastaccess) -match '=\s*[13]\b' }
    On = { fsutil behavior set disablelastaccess 1 | Out-Null }; Off = { fsutil behavior set disablelastaccess 2 | Out-Null } }
Add-Tweak @{ Id = 'memcomp'; Cat = 'Система'; Title = 'Сжатие памяти'; Impact = 'minor'; Reboot = $true; Short = 'Процессор не тратится на сжатие ОЗУ'
    Desc = 'При большом объёме памяти сжатие почти не нужно и только отнимает немного процессорного времени. Показывается при 24 ГБ ОЗУ и больше.'
    Warn = 'При нехватке памяти чаще будет использоваться файл подкачки'
    Avail = { (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory -ge 24GB }
    Check = { -not (Get-MMAgent).MemoryCompression }
    On = { Disable-MMAgent -MemoryCompression }; Off = { Enable-MMAgent -MemoryCompression } }
Add-Tweak @{ Id = 'reserved'; Cat = 'Система'; Title = 'Зарезервированное хранилище'; Impact = 'minor'; Short = 'Освобождает около 7 ГБ на системном диске'
    Desc = 'Windows держит около 7 ГБ под установку обновлений. Отключение возвращает это место.'
    Warn = 'Крупное обновление может не установиться, если диск почти заполнен'
    Avail = { try { [void](Get-WindowsReservedStorageState -ErrorAction Stop); $true } catch { $false } }
    Check = { (Get-WindowsReservedStorageState).ReservedStorageState -eq 'Disabled' }
    On = { Set-WindowsReservedStorageState -State Disabled | Out-Null }; Off = { Set-WindowsReservedStorageState -State Enabled | Out-Null } }
Add-Tweak @{ Id = 'bgapps'; Cat = 'Система'; Title = 'Фоновые приложения из Store'; Impact = 'minor'; Short = 'Приложения из Store не работают в фоне'
    Desc = 'Приложения из Microsoft Store не работают в фоне, когда закрыты.'
    Warn = 'Уведомления от приложений из Store могут приходить с задержкой'
    Reg = (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' GlobalUserDisabled 1 $null) }
Add-Tweak @{ Id = 'edgebg'; Cat = 'Система'; Title = 'Edge в фоне'; Short = 'Edge не висит в памяти'
    Desc = 'Edge не запускается вместе с Windows и не остаётся работать после закрытия окна.'
    Reg = (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' StartupBoostEnabled 0 $null), (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' BackgroundModeEnabled 0 $null) }

# --- Обновления
Add-Tweak @{ Id = 'dosvc'; Cat = 'Обновления'; Title = 'Раздача обновлений другим ПК'; Short = 'Интернет не тратится на раздачу обновлений'
    Desc = 'Windows скачивает обновления только у Microsoft и не раздаёт их другим компьютерам.'
    Reg = (RegV "$Pol\DeliveryOptimization" DODownloadMode 0 $null) }
Add-Tweak @{ Id = 'noautoreboot'; Cat = 'Обновления'; Title = 'Без перезагрузки, пока вы работаете'; Short = 'Windows не перезагрузится сама при открытых программах'
    Desc = 'Если вы вошли в систему, Windows не перезагрузит компьютер для установки обновлений сама, а дождётся вас.'
    Reg = (RegV "$Pol\WindowsUpdate\AU" NoAutoRebootWithLoggedOnUsers 1 $null) }
Add-Tweak @{ Id = 'wudrivers'; Cat = 'Обновления'; Title = 'Драйверы через Windows Update'; Impact = 'minor'; Short = 'Windows не подменит ваш драйвер видеокарты старым'
    Desc = 'Windows Update перестанет устанавливать драйверы. Полезно, если вы ставите драйверы с сайта NVIDIA, AMD или Intel.'
    Warn = 'Драйверы придётся обновлять самостоятельно'
    Reg = (RegV "$Pol\WindowsUpdate" ExcludeWUDriversInQualityUpdate 1 $null) }
Add-Tweak @{ Id = 'edgeupdate'; Cat = 'Обновления'; Title = 'Обновления Edge'; Impact = 'breaks'; Auto = $false; Short = 'Минус две службы обновления Edge'
    Desc = 'Отключает службы обновления Edge. Не советуем: через них обновляется и WebView2, на котором работают многие программы.'
    Warn = 'Edge и WebView2 перестанут получать обновления безопасности'
    Svc = (SvcV edgeupdate Disabled Automatic), (SvcV edgeupdatem Disabled Manual) }

# --- Службы
Add-Tweak @{ Id = 'orgsvc'; Cat = 'Службы'; Title = 'Службы для организаций'; Short = 'Минус 8 служб, которые дома не нужны'
    Desc = 'Удалённый реестр, маршрутизация, SNMP, режим киоска, общий ПК, автономные файлы, iSCSI и общий доступ к портам Net.Tcp.'
    Svc = (SvcV RemoteRegistry Disabled Manual), (SvcV RemoteAccess Disabled Manual), (SvcV SNMPTRAP Disabled Manual), (SvcV AssignedAccessManagerSvc Disabled Manual),
          (SvcV shpamsvc Disabled Manual), (SvcV CscService Disabled Manual), (SvcV MSiSCSI Disabled Manual), (SvcV NetTcpPortSharing Disabled Manual) }
Add-Tweak @{ Id = 'nfcpay'; Cat = 'Службы'; Title = 'Платежи NFC и кошелёк'; Short = 'Минус две службы платежей'
    Desc = 'Службы платежей через NFC и кошелька Windows. На ПК почти не используются.'
    Svc = (SvcV SEMgrSvc Disabled Manual), (SvcV WalletService Disabled Manual) }
Add-Tweak @{ Id = 'mixedreality'; Cat = 'Службы'; Title = 'Смешанная реальность'; Short = 'Минус службы VR-шлемов Windows Mixed Reality'
    Desc = 'Службы Windows Mixed Reality и эмуляции восприятия. Шлемы SteamVR и Quest от них не зависят.'
    Svc = (SvcV MixedRealityOpenXRSvc Disabled Manual), (SvcV spectrum Disabled Manual), (SvcV perceptionsimulation Disabled Manual) }
Add-Tweak @{ Id = 'trkwks'; Cat = 'Службы'; Title = 'Отслеживание изменившихся связей'; Short = 'Минус ненужная служба'
    Desc = 'Служба чинит ярлыки на файлы, перемещённые по сети. Дома почти не нужна.'
    Svc = (SvcV TrkWks Disabled Automatic) }
Add-Tweak @{ Id = 'stisvc'; Cat = 'Службы'; Title = 'Загрузка изображений (WIA)'; Short = 'Служба сканеров запускается только по требованию'
    Desc = 'Переводит службу сканеров и камер в ручной запуск: она стартует, только когда нужна.'
    Svc = (SvcV stisvc Manual Automatic) }
Add-Tweak @{ Id = 'maps'; Cat = 'Службы'; Title = 'Диспетчер скачанных карт'; Short = 'Минус служба и задачи офлайн-карт'
    Desc = 'Нужна только встроенному приложению «Карты».'
    Svc = (SvcV MapsBroker Disabled Automatic)
    Task = '\Microsoft\Windows\Maps\MapsUpdateTask', '\Microsoft\Windows\Maps\MapsToastTask' }
Add-Tweak @{ Id = 'retaildemo'; Cat = 'Службы'; Title = 'Демо-режим и факс'; Short = 'Минус витринный режим магазинов и факс'
    Desc = 'Служба витринного режима для магазинов электроники и служба факса.'
    Svc = (SvcV RetailDemo Disabled Manual), (SvcV Fax Disabled Manual) }
Add-Tweak @{ Id = 'spooler'; Cat = 'Службы'; Title = 'Диспетчер печати'; Impact = 'breaks'; Short = 'Минус две службы печати'
    Desc = 'Отключайте, только если не печатаете вообще.'
    Warn = 'Перестанет работать печать, в том числе «Печать в PDF»'
    Svc = (SvcV Spooler Disabled Automatic), (SvcV PrintNotify Disabled Manual) }
Add-Tweak @{ Id = 'ssdp'; Cat = 'Службы'; Title = 'Обнаружение UPnP и медиатека'; Impact = 'breaks'; Short = 'Минус сетевое обнаружение устройств'
    Desc = 'Службы поиска UPnP-устройств в сети, узла UPnP и раздачи медиатеки Windows Media Player.'
    Warn = 'Перестанут находиться DLNA-телевизоры и медиасерверы'
    Svc = (SvcV SSDPSRV Disabled Manual), (SvcV upnphost Disabled Manual), (SvcV WMPNetworkSvc Disabled Manual) }
Add-Tweak @{ Id = 'pca'; Cat = 'Службы'; Title = 'Помощник совместимости программ'; Impact = 'minor'; Short = 'Без подсказок совместимости'
    Desc = 'Служба следит за старыми программами и предлагает исправления совместимости.'
    Warn = 'Старые программы не получат автоматических исправлений совместимости'
    Svc = (SvcV PcaSvc Disabled Manual) }
Add-Tweak @{ Id = 'diag'; Cat = 'Службы'; Title = 'Служба политики диагностики'; Impact = 'breaks'; Short = 'Минус три диагностические службы'
    Desc = 'Службы, на которых работают встроенные средства устранения неполадок.'
    Warn = 'Перестанет работать «Устранение неполадок» Windows'
    Svc = (SvcV DPS Disabled Automatic), (SvcV WdiServiceHost Disabled Manual), (SvcV WdiSystemHost Disabled Manual) }
Add-Tweak @{ Id = 'phonesvc'; Cat = 'Службы'; Title = 'Телефония и SMS'; Impact = 'breaks'; Short = 'Минус службы звонков и SMS через ПК'
    Desc = 'Службы, через которые «Связь с телефоном» передаёт звонки и SMS.'
    Warn = 'Звонки и SMS через «Связь с телефоном» работать не будут'
    Svc = (SvcV PhoneSvc Disabled Manual), (SvcV SmsRouter Disabled Manual) }
Add-Tweak @{ Id = 'bluetooth'; Cat = 'Службы'; Title = 'Bluetooth'; Impact = 'breaks'; Short = 'Минус три службы Bluetooth'
    Desc = 'Службы поддержки Bluetooth, гарнитур и аудио по Bluetooth.'
    Warn = 'Bluetooth-наушники, мыши и геймпады перестанут подключаться'
    Svc = (SvcV bthserv Disabled Manual), (SvcV BTAGService Disabled Manual), (SvcV BthAvctpSvc Disabled Manual) }
Add-Tweak @{ Id = 'camsvc'; Cat = 'Службы'; Title = 'Сервер кадров камеры'; Impact = 'breaks'; Short = 'Минус службы веб-камеры'
    Desc = 'Службы Windows Camera Frame Server, через которые приложения получают доступ к камере.'
    Warn = 'Веб-камера может перестать работать в части приложений'
    Svc = (SvcV FrameServer Disabled Manual), (SvcV FrameServerMonitor Disabled Manual) }
Add-Tweak @{ Id = 'hello'; Cat = 'Службы'; Title = 'Биометрия (Windows Hello)'; Impact = 'breaks'; Short = 'Минус служба биометрии'
    Desc = 'Служба распознавания лица и отпечатков пальцев.'
    Warn = 'Вход по лицу и отпечатку перестанет работать'
    Svc = (SvcV WbioSrvc Disabled Manual) }
Add-Tweak @{ Id = 'sensors'; Cat = 'Службы'; Title = 'Датчики'; Impact = 'minor'; Short = 'Минус три службы датчиков'
    Desc = 'Службы датчиков освещённости, ориентации и движения. На настольном ПК не нужны.'
    Warn = 'На ноутбуке и планшете перестанут работать автояркость и поворот экрана'
    Svc = (SvcV SensorService Disabled Manual), (SvcV SensrSvc Disabled Manual), (SvcV SensorDataService Disabled Manual) }
Add-Tweak @{ Id = 'smartcard'; Cat = 'Службы'; Title = 'Смарт-карты'; Impact = 'breaks'; Auto = $false; Short = 'Минус три службы смарт-карт'
    Desc = 'Службы смарт-карт и USB-токенов.'
    Warn = 'Перестанут работать токены электронной подписи (Рутокен, eToken, JaCarta) и смарт-карты'
    Svc = (SvcV SCardSvr Disabled Manual), (SvcV ScDeviceEnum Disabled Manual), (SvcV SCPolicySvc Disabled Manual) }
Add-Tweak @{ Id = 'wsearch'; Cat = 'Службы'; Title = 'Индексирование поиска'; Impact = 'breaks'; Short = 'Минус постоянная фоновая индексация диска'
    Desc = 'Служба Windows Search, которая индексирует файлы для быстрого поиска.'
    Warn = 'Поиск файлов в Пуске и Проводнике станет медленным, без поиска по содержимому'
    Svc = (SvcV WSearch Disabled Automatic) }

# --- Безопасность
Add-Tweak @{ Id = 'autorun'; Cat = 'Безопасность'; Title = 'Автозапуск с флешек и дисков'; Short = 'Вирус с флешки не запустится сам'
    Desc = 'Отключает автозапуск для всех типов дисков. Флешки открываются как обычно, просто ничего не запускается само.'
    Reg = (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' NoDriveTypeAutoRun 255 $null), (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' NoAutorun 1 $null) }
Add-Tweak @{ Id = 'ssl'; Cat = 'Безопасность'; Title = 'SSL 2.0 и 3.0'; Reboot = $true; Short = 'Запрет устаревших протоколов шифрования'
    Desc = 'Явно отключает SSL 2.0 и 3.0 для всех программ, которые используют шифрование Windows.'
    Reg = foreach ($v in 'SSL 2.0', 'SSL 3.0') { foreach ($s in 'Client', 'Server') { (RegV "$Sch\$v\$s" Enabled 0 $null), (RegV "$Sch\$v\$s" DisabledByDefault 1 $null) } } }
Add-Tweak @{ Id = 'anon'; Cat = 'Безопасность'; Title = 'Анонимный доступ к ПК по сети'; Impact = 'minor'; Reboot = $true; Short = 'Без анонимного перечисления общих папок'
    Desc = 'Запрещает анонимным пользователям сети получать список общих папок и учётных записей.'
    Warn = 'Очень старые устройства могут не увидеть общие папки этого ПК'
    Reg = (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' RestrictAnonymous 1 0) }
Add-Tweak @{ Id = 'llmnr'; Cat = 'Безопасность'; Title = 'Протокол LLMNR'; Impact = 'minor'; Short = 'Закрывает популярный способ перехвата паролей в сети'
    Desc = 'Отключает многоадресное разрешение имён LLMNR, которым пользуются для атак в общих сетях (кафе, общежития).'
    Warn = 'В редких домашних сетях компьютеры могут перестать находить друг друга по имени'
    Reg = (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' EnableMulticast 0 $null) }
Add-Tweak @{ Id = 'remoteassist'; Cat = 'Безопасность'; Title = 'Удалённый помощник'; Impact = 'minor'; Short = 'К ПК нельзя подключиться через Удалённого помощника'
    Desc = 'Отключает приглашения «Удалённого помощника» Windows, которым пользуются телефонные мошенники.'
    Warn = 'Старый «Удалённый помощник» работать не будет (Quick Assist и AnyDesk работают)'
    Reg = (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' fAllowToGetHelp 0 1) }
Add-Tweak @{ Id = 'smb1'; Cat = 'Безопасность'; Title = 'SMB 1.0'; Impact = 'minor'; Reboot = $true; Short = 'Закрывает старую сетевую уязвимость'
    Desc = 'Устаревший и небезопасный сетевой протокол, через который распространялся WannaCry.'
    Warn = 'Очень старые сетевые хранилища (NAS) могут перестать открываться'
    Feature = 'SMB1Protocol' }
Add-Tweak @{ Id = 'psv2'; Cat = 'Безопасность'; Title = 'PowerShell 2.0'; Reboot = $true; Short = 'Убирает устаревший PowerShell'
    Desc = 'Старую версию PowerShell используют для обхода защиты. Современным программам она не нужна.'
    Feature = 'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2' }

# --- Удобство
Add-Tweak @{ Id = 'fileext'; Cat = 'Удобство'; Title = 'Показывать расширения файлов'; Auto = $false; Short = 'Видно, что «фото.jpg.exe» — это программа'
    Desc = 'Проводник показывает расширения файлов. Это ещё и защита: вирус не замаскируется под документ.'
    Reg = (RegV $Adv HideFileExt 0 1) }
Add-Tweak @{ Id = 'launchto'; Cat = 'Удобство'; Title = 'Проводник открывает «Этот компьютер»'; Auto = $false; Short = 'Сразу видно диски, а не «Главную»'
    Desc = 'Проводник открывается на «Этот компьютер» со списком дисков вместо «Главной».'
    Reg = (RegV $Adv LaunchTo 1 $null) }
Add-Tweak @{ Id = 'endtask'; Cat = 'Удобство'; Title = '«Завершить задачу» в панели задач'; Auto = $false; Short = 'Зависшую программу можно закрыть правым кликом'
    Desc = 'Добавляет пункт «Завершить задачу» в меню правого клика по значку на панели задач.'
    Avail = { [Environment]::OSVersion.Version.Build -ge 22631 }
    Reg = (RegV "$Adv\TaskbarDeveloperSettings" TaskbarEndTask 1 $null) }
Add-Tweak @{ Id = 'sticky'; Cat = 'Удобство'; Title = 'Залипание клавиш по 5×Shift'; Auto = $false; Short = 'Игра не свернётся из-за окна залипания клавиш'
    Desc = 'Отключает сочетания, которые включают залипание, фильтрацию и озвучку клавиш (5×Shift, удержание Shift, удержание NumLock).'
    Reg = (RegV 'HKCU:\Control Panel\Accessibility\StickyKeys' Flags '506' '510' 'String'), (RegV 'HKCU:\Control Panel\Accessibility\Keyboard Response' Flags '122' '126' 'String'),
          (RegV 'HKCU:\Control Panel\Accessibility\ToggleKeys' Flags '58' '62' 'String') }
Add-Tweak @{ Id = 'taskview'; Cat = 'Удобство'; Title = 'Кнопка «Представление задач»'; Auto = $false; Short = 'Чище панель задач'
    Desc = 'Убирает кнопку «Представление задач» с панели задач. Сама функция работает по Win+Tab.'
    Reg = (RegV $Adv ShowTaskViewButton 0 1) }
Add-Tweak @{ Id = 'ctxmenu'; Cat = 'Удобство'; Title = 'Классическое контекстное меню'; Auto = $false; Reboot = $true; Avail = $Win11; Short = 'Полное меню по правому клику сразу'
    Desc = 'Правый клик сразу показывает полное меню, как в Windows 10, без пункта «Показать дополнительные параметры».'
    Check = { $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$CtxKey\InprocServer32"); if ($k) { $k.Close(); $true } else { $false } }
    On = { $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$CtxKey\InprocServer32"); $k.SetValue('', ''); $k.Close() }
    Off = { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($CtxKey, $false) } }
Add-Tweak @{ Id = 'menudelay'; Cat = 'Удобство'; Title = 'Быстрое открытие меню'; Short = 'Подменю открываются быстрее'
    Desc = 'Задержка перед открытием подменю уменьшается с 400 до 100 мс.'
    Reg = (RegV 'HKCU:\Control Panel\Desktop' MenuShowDelay '100' '400' 'String') }
Add-Tweak @{ Id = 'animations'; Cat = 'Удобство'; Title = 'Анимации и прозрачность'; Auto = $false; Short = 'Окна открываются мгновенно'
    Desc = 'Отключает анимацию сворачивания окон, панели задач, предпросмотр рабочего стола (Aero Peek) и прозрачность.'
    Reg = (RegV 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate '0' '1' 'String'), (RegV $Adv TaskbarAnimations 0 1), (RegV 'HKCU:\Software\Microsoft\Windows\DWM' EnableAeroPeek 0 1),
          (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0 1) }

# --- Компоненты
Add-Tweak @{ Id = 'workfolders'; Cat = 'Компоненты'; Title = 'Рабочие папки'; Reboot = $true; Short = 'Минус ненужный компонент и служба'
    Desc = 'Клиент корпоративной синхронизации файлов. Дома не нужен.'
    Feature = 'WorkFolders-Client'; Svc = (SvcV WorkFoldersSvc Disabled Manual) }
Add-Tweak @{ Id = 'recallfeat'; Cat = 'Компоненты'; Title = 'Recall'; Impact = 'breaks'; Reboot = $true; Short = 'Удаляет компонент Recall'
    Desc = 'Компонент Windows Recall, который делает снимки экрана.'
    Warn = 'Recall нельзя будет включить, пока компонент не вернут'
    Feature = 'Recall' }
Add-Tweak @{ Id = 'xps'; Cat = 'Компоненты'; Title = 'Службы XPS'; Impact = 'minor'; Reboot = $true; Short = 'Минус ненужный компонент печати'
    Desc = 'Печать в формат XPS. Почти никто им не пользуется.'
    Warn = 'Не будет печати в формат XPS'
    Feature = 'Printing-XPSServices-Features' }

# --- Приложения (показываются только установленные)
$Apps = [ordered]@{
    'Microsoft.BingNews' = 'Новости'; 'Microsoft.BingWeather' = 'Погода'; 'Microsoft.BingSearch' = 'Bing Search'
    'Clipchamp.Clipchamp' = 'Clipchamp'; 'Microsoft.GetHelp' = 'Техническая поддержка'; 'Microsoft.Getstarted' = 'Советы'
    'Microsoft.MicrosoftSolitaireCollection' = 'Solitaire Collection'; 'Microsoft.People' = 'Люди'; 'Microsoft.PowerAutomateDesktop' = 'Power Automate'
    'Microsoft.Todos' = 'Microsoft To Do'; 'Microsoft.WindowsFeedbackHub' = 'Центр отзывов'; 'Microsoft.WindowsMaps' = 'Карты'
    'Microsoft.YourPhone' = 'Связь с телефоном'; 'MicrosoftWindows.CrossDevice' = 'Cross Device (для «Связи с телефоном»)'
    'Microsoft.ZuneMusic' = 'Медиаплеер'; 'Microsoft.ZuneVideo' = 'Кино и ТВ'; 'Microsoft.OutlookForWindows' = 'Outlook (новый)'
    'Microsoft.MicrosoftOfficeHub' = 'Microsoft 365 (Office)'; 'Microsoft.Copilot' = 'Copilot'; 'MSTeams' = 'Microsoft Teams'
    'Microsoft.549981C3F5F10' = 'Cortana'; 'Microsoft.Windows.DevHome' = 'Dev Home'; 'MicrosoftCorporationII.QuickAssist' = 'Быстрая помощь'
    'Microsoft.WindowsSoundRecorder' = 'Звукозапись'; 'Microsoft.WindowsAlarms' = 'Часы'; 'Microsoft.MicrosoftStickyNotes' = 'Записки'
    'Microsoft.MixedReality.Portal' = 'Портал смешанной реальности'; 'Microsoft.Microsoft3DViewer' = '3D Viewer'; 'Microsoft.SkypeApp' = 'Skype'
}
foreach ($k in $Apps.Keys) {
    Add-Tweak @{ Id = "app:$k"; Cat = 'Приложения'; Title = $Apps[$k]; Impact = 'remove'; Appx = $k; Short = 'Удалить для текущего пользователя'
        Desc = "Пакет $k. Удаляется только для вашей учётной записи. Вернуть можно через Microsoft Store." }
}
#endregion
