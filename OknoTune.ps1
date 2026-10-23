<#
  OknoTune — настройка Windows с откатом.
  Запуск: OknoTune.cmd (или powershell -ExecutionPolicy Bypass -File OknoTune.ps1)
  -Selftest                проверить состояние без окна и без изменений
  -Snapshot a.png [-View]  отрисовать экран в PNG и выйти (home|wizard|review|list|history|clean|startup|drivers|apps|fixes|welcome), без изменений
#>
param([switch]$Selftest, [string]$Snapshot, [string]$View = 'home')

$ErrorActionPreference = 'Continue'
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin -and -not $Selftest -and -not $Snapshot) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    exit
}

$script:DataDir = Join-Path $env:LOCALAPPDATA 'OknoTune'
New-Item -ItemType Directory -Force $script:DataDir | Out-Null
$script:LogFile = Join-Path $script:DataDir 'log.txt'
$script:RebootFile = Join-Path $script:DataDir 'reboot-pending.txt'

#region Registry / services / tasks helpers
function Open-Key([string]$p, [bool]$create) {
    $hive, $sub = $p -split ':\\', 2
    $root = if ($hive -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    if ($create) { $root.CreateSubKey($sub) } else { $root.OpenSubKey($sub, $true) }
}
function Get-RegRaw([string]$p, [string]$n) {
    $hive, $sub = $p -split ':\\', 2
    $root = if ($hive -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $k = $root.OpenSubKey($sub)
    if (-not $k) { return $null }
    try {
        $v = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
        if ($null -eq $v) { return $null }
        [pscustomobject]@{ Value = (Format-RegVal $v); Kind = "$($k.GetValueKind($n))" }
    } finally { $k.Close() }
}
function Format-RegVal($v) {
    if ($v -is [byte[]]) { return ([BitConverter]::ToString($v) -replace '-', '') }
    if ($v -is [int] -and $v -lt 0) { return [string]([long]$v + 4294967296) }
    "$v"
}
function Set-Reg([string]$p, [string]$n, $v, [string]$kind) {
    $k = Open-Key $p $true
    try {
        switch ($kind) {
            'String'       { $k.SetValue($n, [string]$v, 'String') }
            'ExpandString' { $k.SetValue($n, [string]$v, 'ExpandString') }
            'QWord'        { $k.SetValue($n, [long]$v, 'QWord') }
            'Binary'       { if ($v -is [byte[]]) { $b = $v } else { $b = New-Object byte[] ("$v".Length / 2); for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte("$v".Substring(2 * $i, 2), 16) } }; $k.SetValue($n, $b, 'Binary') }
            default        { $k.SetValue($n, [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]"$v"), 0), 'DWord') }
        }
    } finally { $k.Close() }
}
function Remove-Reg([string]$p, [string]$n) {
    $k = Open-Key $p $false
    if ($k) { $k.DeleteValue($n, $false); $k.Close() }
}
function Get-SvcStart([string]$s) {
    $x = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($x) { "$($x.StartType)" }
}
function Set-SvcStart([string]$s, [string]$mode) {
    if ($mode -eq 'Disabled') { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    try { Set-Service -Name $s -StartupType $mode -ErrorAction Stop }
    catch {
        # some services refuse Set-Service; the Start value works for them
        $n = @{ Automatic = 2; Manual = 3; Disabled = 4 }[$mode]
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\$s" 'Start' $n 'DWord'
    }
}
function Set-TaskEnabled([string]$full, [bool]$enabled) {
    $i = $full.LastIndexOf('\')
    $tp = $full.Substring(0, $i + 1); $tn = $full.Substring($i + 1)
    if ($enabled) { Enable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
}
$GuidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$FastPlanRx = 'Ultimate Performance|High performance|Максимальная производительность|Высокая производительность'
$UsbSub = '2a737441-1930-4402-8d77-b2bebba308a3'; $UsbSet = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
#endregion

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

#region State
$script:Tasks = @{}; $script:Features = @{}; $script:SvcNames = @{}; $script:AppxNames = @{}; $script:ItemsById = @{}
function Update-TaskCache {
    $script:Tasks = @{}
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object { $script:Tasks["$($_.TaskPath)$($_.TaskName)"] = "$($_.State)" }
}
function Update-SlowCaches {
    # медленная половина (DISM и Appx, секунды); при запуске UI собирается фоном
    $script:Features = @{}
    try { Get-WindowsOptionalFeature -Online -ErrorAction Stop | ForEach-Object { $script:Features[$_.FeatureName] = "$($_.State)" } } catch {}
    $script:AppxNames = @{}; Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $script:AppxNames[$_.Name] = 1 }
}
function Update-Caches([switch]$FastOnly) {
    Update-TaskCache
    $script:SvcNames = @{}; Get-Service -ErrorAction SilentlyContinue | ForEach-Object { $script:SvcNames[$_.Name] = 1 }
    if (-not $FastOnly) { Update-SlowCaches }
}
# Фоновое сканирование: два медленных командлета работают в отдельном runspace, пока открывается окно.
$script:SlowScan = $null
function Start-SlowScan {
    $t = [hashtable]::Synchronized(@{ Done = $false; Error = $null; Features = $null; Appx = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = [runspacefactory]::CreateRunspace()
    $ps.Runspace.Open()
    [void]$ps.AddScript({
        param($t)
        try {
            $f = @{}
            Import-Module Dism -ErrorAction Stop
            Get-WindowsOptionalFeature -Online -ErrorAction Stop | ForEach-Object { $f[$_.FeatureName] = "$($_.State)" }
            $t.Features = $f
            $a = @{}
            Import-Module Appx -ErrorAction Stop
            Get-AppxPackage -ErrorAction Stop | ForEach-Object { $a[$_.Name] = 1 }
            $t.Appx = $a
        } catch { $t.Error = "$_" }
        finally { $t.Done = $true }
    }).AddArgument($t)
    $script:SlowScan = @{ Table = $t; Ps = $ps; Merged = $false }
    [void]$ps.BeginInvoke()
}
function Stop-SlowScan {
    # по таймауту: останавливаем runspace, Wait-SlowScan тогда пересчитает синхронно
    $s = $script:SlowScan
    if (-not $s -or $s.Merged) { return }
    try { $s.Ps.Stop() } catch {}
    $s.Table.Error = 'timeout'
}
function Wait-SlowScan {
    # в потоке UI после Done (или таймаута): берём результат, при ошибке — синхронный пересчёт
    $s = $script:SlowScan
    if (-not $s) { return }
    if ($s.Table.Error -or $null -eq $s.Table.Features -or $null -eq $s.Table.Appx) { Update-SlowCaches }
    else { $script:Features = $s.Table.Features; $script:AppxNames = $s.Table.Appx }
    $s.Merged = $true
    try { $s.Ps.Runspace.Close(); $s.Ps.Dispose() } catch {}
}
function Select-Available {
    foreach ($it in $script:AllItems) {
        if ($it.Avail -and -not (& $it.Avail)) { continue }
        if ($it.Appx -and -not $script:AppxNames.ContainsKey($it.Appx)) { continue }
        $it.Svc = @($it.Svc | Where-Object { $script:SvcNames.ContainsKey($_.S) })
        $it.Task = @($it.Task | Where-Object { $script:Tasks.ContainsKey($_) })
        $it.Feature = @($it.Feature | Where-Object { $script:Features.ContainsKey($_) })
        if (($it.Reg.Count + $it.Svc.Count + $it.Task.Count + $it.Feature.Count) -eq 0 -and -not $it.Appx -and -not $it.Check) { continue }
        $it
    }
}
function Get-TweakState($it) {
    $parts = New-Object System.Collections.Generic.List[bool]
    foreach ($r in $it.Reg) { $c = Get-RegRaw $r.P $r.N; $parts.Add([bool]($c -and $c.Value -eq "$($r.V)")) }
    foreach ($s in $it.Svc) { $parts.Add((Get-SvcStart $s.S) -eq $s.V) }
    foreach ($t in $it.Task) { $parts.Add($script:Tasks[$t] -eq 'Disabled') }
    foreach ($f in $it.Feature) { $parts.Add($script:Features[$f] -notmatch '^Enable') }
    if ($it.Appx) { $parts.Add(-not $script:AppxNames.ContainsKey($it.Appx)) }
    if ($it.Check) { $parts.Add([bool](& $it.Check)) }
    $on = @($parts | Where-Object { $_ }).Count
    if ($on -eq $parts.Count) { 'on' } elseif ($on) { 'partial' } else { 'off' }
}
function Update-States { foreach ($it in $script:Items) { $it.State = Get-TweakState $it } }
function Initialize-Items {
    if ($script:SlowScan) { Wait-SlowScan; Update-Caches -FastOnly }
    else { Update-Caches }
    $script:Items = @(Select-Available)
    $script:ItemsById = @{}; foreach ($it in $script:Items) { $script:ItemsById[$it.Id] = $it }
    Update-States
    Find-Hardware
}

function Set-TweakExtra($it, [bool]$enable) {
    foreach ($f in $it.Feature) {
        if ($enable) { Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null }
        else { Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null }
    }
    if ($enable -and $it.On) { & $it.On } elseif (-not $enable -and $it.Off) { & $it.Off }
}
function Set-TweakState($it, [bool]$enable) {
    foreach ($r in $it.Reg) {
        if ($enable) { Set-Reg $r.P $r.N $r.V $r.T }
        elseif ($null -eq $r.D) { Remove-Reg $r.P $r.N }
        else { Set-Reg $r.P $r.N $r.D $r.T }
    }
    foreach ($s in $it.Svc) { Set-SvcStart $s.S $(if ($enable) { $s.V } else { $s.D }) }
    foreach ($t in $it.Task) { Set-TaskEnabled $t (-not $enable) }
    if ($it.Appx -and $enable) { Get-AppxPackage -Name $it.Appx | Remove-AppxPackage -ErrorAction Stop }
    Set-TweakExtra $it $enable
}
function Get-Snapshot($it, [bool]$enable) {
    [pscustomobject]@{
        Id = $it.Id; Title = $it.Title; Enable = $enable; State = $it.State
        Extra = $(if ($it.Save) { & $it.Save })
        Reg = @($it.Reg | ForEach-Object { $c = Get-RegRaw $_.P $_.N; [pscustomobject]@{ P = $_.P; N = $_.N; Exists = [bool]$c; Value = $(if ($c) { $c.Value }); Kind = $(if ($c) { $c.Kind }) } })
        Svc = @($it.Svc | ForEach-Object { [pscustomobject]@{ S = $_.S; Start = (Get-SvcStart $_.S) } })
        Task = @($it.Task | ForEach-Object { [pscustomobject]@{ T = $_; Disabled = ($script:Tasks[$_] -eq 'Disabled') } })
        Appx = $(if ($it.Appx -and $enable) { @(Get-AppxPackage -Name $it.Appx -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) } else { @() })
    }
}
function Restore-Entry($e) {
    foreach ($r in $e.Reg) { if ($r.Exists) { Set-Reg $r.P $r.N $r.Value $r.Kind } else { Remove-Reg $r.P $r.N } }
    foreach ($s in $e.Svc) { if ($s.Start -in 'Automatic', 'Manual', 'Disabled') { Set-SvcStart $s.S $s.Start } }
    foreach ($t in $e.Task) { Set-TaskEnabled $t.T (-not $t.Disabled) }
    foreach ($d in @($e.Dns)) { if ($d) { Set-AdapterDns $d.Idx @($d.Servers) } }
    foreach ($f in @($e.File)) {
        if (-not $f) { continue }
        if ($f.WasOff) {
            if ((Test-Path -LiteralPath $f.Path) -and -not (Test-Path -LiteralPath $f.Off)) { Move-Item -LiteralPath $f.Path -Destination $f.Off -Force -ErrorAction SilentlyContinue }
        } elseif ((Test-Path -LiteralPath $f.Off) -and -not (Test-Path -LiteralPath $f.Path)) { Move-Item -LiteralPath $f.Off -Destination $f.Path -Force -ErrorAction SilentlyContinue }
    }
    $it = $script:ItemsById[$e.Id]
    if (-not $it) { return }
    if ($it.Load -and $e.Extra) { & $it.Load $e.Extra }
    elseif (($it.Feature.Count -or $it.On) -and (Get-TweakState $it) -ne $e.State) { Set-TweakExtra $it ($e.State -eq 'on') }
}
#endregion

#region Startup (автозагрузка)
# Отключение обратимо: значение реестра переезжает в подраздел OknoTuneDisabled, файл из папки
# автозагрузки переименовывается в <имя>.OknoTuneOff. Метка «отключено в Диспетчере задач»
# (StartupApproved, REG_BINARY) тоже попадает в снимок, поэтому откат возвращает всё точно.
$SuOffExt = '.OknoTuneOff'
$script:RunKeys = @(
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';            Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';  Label = 'реестр · текущий пользователь' }
    @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';            Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';  Label = 'реестр · все пользователи' }
    @{ P = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Label = 'реестр · 32-бит · все пользователи' }
)
$script:StartupFolders = @(
    @{ P = [Environment]::GetFolderPath('Startup');      Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Label = 'папка · текущий пользователь' }
    @{ P = [Environment]::GetFolderPath('CommonStartup'); Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Label = 'папка · все пользователи' }
)
function Get-ApprovedMap([string]$p) {
    # значение StartupApproved: первый байт нечётный (3, 7…) = отключено пользователем/Диспетчером задач
    $m = @{}
    $hive, $sub = $p -split ':\\', 2
    $root = if ($hive -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $k = $root.OpenSubKey($sub)
    if (-not $k) { return $m }
    try {
        foreach ($n in $k.GetValueNames()) {
            $v = $k.GetValue($n)
            if ($v -is [byte[]] -and $v.Count -ge 1) { $m[$n] = (($v[0] -band 1) -eq 1) }
        }
    } finally { $k.Close() }
    $m
}
function Get-StartupItems {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($rk in $script:RunKeys) {
        $approved = Get-ApprovedMap $rk.Approved
        $k = Open-Key $rk.P $false
        if ($k) {
            try {
                foreach ($n in $k.GetValueNames()) {
                    $raw = Get-RegRaw $rk.P $n
                    if (-not $raw) { continue }
                    $tmOff = [bool]$approved[$n]
                    $list.Add([pscustomobject]@{ Kind = 'reg'; Path = $rk.P; Name = $n; Command = $raw.Value; Label = $rk.Label
                        Approved = $rk.Approved; OknoTuneOff = $false; TmOff = $tmOff; On = -not $tmOff })
                }
            } finally { $k.Close() }
        }
        $bk = "$($rk.P)\OknoTuneDisabled"
        $k = Open-Key $bk $false
        if ($k) {
            try {
                foreach ($n in $k.GetValueNames()) {
                    $raw = Get-RegRaw $bk $n
                    if (-not $raw) { continue }
                    $list.Add([pscustomobject]@{ Kind = 'reg'; Path = $rk.P; Name = $n; Command = $raw.Value; Label = $rk.Label
                        Approved = $rk.Approved; OknoTuneOff = $true; TmOff = $false; On = $false })
                }
            } finally { $k.Close() }
        }
    }
    foreach ($sf in $script:StartupFolders) {
        if (-not $sf.P -or -not (Test-Path -LiteralPath $sf.P)) { continue }
        $approved = Get-ApprovedMap $sf.Approved
        foreach ($f in Get-ChildItem -LiteralPath $sf.P -File -Force -ErrorAction SilentlyContinue) {
            if ($f.Name -ieq 'desktop.ini' -or ($f.Attributes -band [IO.FileAttributes]::System)) { continue }   # служебные файлы папки
            if ($f.Name -like "*$SuOffExt") {
                $base = $f.Name.Substring(0, $f.Name.Length - $SuOffExt.Length)
                $list.Add([pscustomobject]@{ Kind = 'file'; Path = (Join-Path $sf.P $base); Name = $base; Command = $f.FullName; Label = $sf.Label
                    Approved = $sf.Approved; OknoTuneOff = $true; TmOff = $false; On = $false })
            } else {
                $tmOff = [bool]$approved[$f.Name]
                $list.Add([pscustomobject]@{ Kind = 'file'; Path = $f.FullName; Name = $f.Name; Command = $f.FullName; Label = $sf.Label
                    Approved = $sf.Approved; OknoTuneOff = $false; TmOff = $tmOff; On = -not $tmOff })
            }
        }
    }
    $list
}
function Set-StartupState($it, [bool]$on) {
    if ($it.Kind -eq 'reg') {
        $bk = "$($it.Path)\OknoTuneDisabled"
        if ($on) {
            $raw = Get-RegRaw $bk $it.Name
            if ($raw) { Set-Reg $it.Path $it.Name $raw.Value $raw.Kind; Remove-Reg $bk $it.Name }
            elseif (-not (Get-RegRaw $it.Path $it.Name)) { throw 'запись автозагрузки не найдена' }
        } else {
            $raw = Get-RegRaw $it.Path $it.Name
            if (-not $raw) { throw 'запись автозагрузки не найдена' }
            Set-Reg $bk $it.Name $raw.Value $raw.Kind
            Remove-Reg $it.Path $it.Name
        }
    } else {
        $off = "$($it.Path)$SuOffExt"
        if ($on) {
            if (Test-Path -LiteralPath $off) { Move-Item -LiteralPath $off -Destination $it.Path -Force }
            elseif (-not (Test-Path -LiteralPath $it.Path)) { throw 'файл автозагрузки не найден' }
        } else {
            if (-not (Test-Path -LiteralPath $it.Path)) { throw 'файл автозагрузки не найден' }
            Move-Item -LiteralPath $it.Path -Destination $off -Force
        }
    }
    # снять метку «отключено в Диспетчере задач», иначе включённая запись может не запуститься
    Remove-Reg $it.Approved $it.Name
}
function Get-StartupSnap($it, [bool]$on) {
    $reg = New-Object System.Collections.Generic.List[object]
    foreach ($pair in @(@($it.Path, $it.Name), @("$($it.Path)\OknoTuneDisabled", $it.Name), @($it.Approved, $it.Name))) {
        if ($it.Kind -eq 'file' -and $pair[0] -ne $it.Approved) { continue }
        $c = Get-RegRaw $pair[0] $pair[1]
        $reg.Add([pscustomobject]@{ P = $pair[0]; N = $pair[1]; Exists = [bool]$c; Value = $(if ($c) { $c.Value }); Kind = $(if ($c) { $c.Kind }) })
    }
    $file = @()
    if ($it.Kind -eq 'file') {
        $off = "$($it.Path)$SuOffExt"
        $file = @([pscustomobject]@{ Path = $it.Path; Off = $off; WasOff = (Test-Path -LiteralPath $off) })
    }
    # NB: @($reg) внутрь литерала hashtable писать нельзя — PS 5.1 падает с ArgumentException
    [pscustomobject]@{ Id = "startup:$($it.Kind):$($it.Path)|$($it.Name)"; Title = $it.Name; Enable = $on; State = $(if ($it.On) { 'on' } else { 'off' })
        Reg = $reg.ToArray(); Svc = @(); Task = @(); Appx = @(); File = $file }
}
#endregion

#region Cleanup catalog
# Only paths under these roots are ever deleted; reparse points (junctions/symlinks) are never followed.
$script:CleanRoots = @($env:windir, $env:LOCALAPPDATA, $env:ProgramData) | ForEach-Object { $_.TrimEnd('\') }
function Test-SafePath([string]$p) {
    $full = [IO.Path]::GetFullPath($p)
    foreach ($r in $script:CleanRoots) { if ($full.StartsWith("$r\", [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    $false
}
function Get-FilesSafe([string]$dir) {
    foreach ($e in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
        if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($e.PSIsContainer) { Get-FilesSafe $e.FullName } else { $e }
    }
}
function Get-CleanFiles($c) {
    $cut = (Get-Date).AddHours(-[int]$c.MinAge)
    foreach ($p in @(& $c.Paths)) {
        if (-not $p -or -not (Test-SafePath $p) -or -not (Test-Path -LiteralPath $p)) { continue }
        $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $i -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        if ($i.PSIsContainer) { Get-FilesSafe $p | Where-Object { $_.LastWriteTime -lt $cut } } elseif ($i.LastWriteTime -lt $cut) { $i }
    }
}
function Get-CleanSize($c) {
    if ($c.Size) { return (& $c.Size) }
    [long](@(Get-CleanFiles $c) | Measure-Object Length -Sum).Sum
}
function Format-Size($b) {
    if ($null -eq $b) { return '—' }
    if ($b -ge 1GB) { '{0:N1} ГБ' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} МБ' -f ($b / 1MB) } elseif ($b -gt 0) { '{0:N0} КБ' -f [Math]::Max(1, $b / 1KB) } else { '0' }
}
function Get-FreeBytes { [long](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace }
function Invoke-Clean($c) {
    if ($c.Before) { & $c.Before }
    if ($c.Clean) { & $c.Clean; return }
    $files = @(Get-CleanFiles $c)
    foreach ($f in $files) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    # remove folders left empty, but never the listed folders themselves
    foreach ($p in @(& $c.Paths)) {
        if (-not $p -or -not (Test-SafePath $p) -or -not (Test-Path -LiteralPath $p -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $p -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
}
$Lad = $env:LOCALAPPDATA
$script:CleanItems = @(
    @{ Id = 'usertemp'; Title = 'Временные файлы пользователя'; Impact = 'none'; Default = $true; MinAge = 24
       Desc = 'Папка TEMP вашей учётной записи. Файлы моложе суток не трогаем: их может использовать работающий установщик.'
       Paths = { $env:TEMP } }
    @{ Id = 'wintemp'; Title = 'Временные файлы Windows'; Impact = 'none'; Default = $true; MinAge = 24
       Desc = 'Системная папка Windows\Temp. Файлы моложе суток не трогаем.'
       Paths = { "$env:windir\Temp" } }
    @{ Id = 'wucache'; Title = 'Загрузки Windows Update'; Impact = 'none'; Default = $true
       Desc = 'Пакеты уже скачанных обновлений. Если какое-то ещё не установлено, Windows скачает его заново.'
       Paths = { "$env:windir\SoftwareDistribution\Download" }
       Before = { Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue } }
    @{ Id = 'docache'; Title = 'Кэш оптимизации доставки'; Impact = 'none'; Default = $true
       Desc = 'Копии обновлений, которые Windows хранит, чтобы раздавать другим ПК.'
       Paths = { "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" }
       Clean = { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue } }
    @{ Id = 'wer'; Title = 'Отчёты об ошибках'; Impact = 'none'; Default = $true
       Desc = 'Отчёты о сбоях программ, которые Windows собирала для отправки в Microsoft.'
       Paths = { "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$Lad\Microsoft\Windows\WER" } }
    @{ Id = 'thumbs'; Title = 'Кэш миниатюр'; Impact = 'none'; Default = $true
       Desc = 'Превью картинок и видео в Проводнике. Пересоздастся сам при просмотре папок (занятые файлы пропускаются).'
       Paths = { Get-ChildItem "$Lad\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } } }
    @{ Id = 'logs'; Title = 'Журналы установки Windows'; Impact = 'none'; Default = $true; MinAge = 24
       Desc = 'Журналы CBS и DISM от прошлых установок обновлений.'
       Paths = { "$env:windir\Logs\CBS", "$env:windir\Logs\DISM" } }
    @{ Id = 'dumps'; Title = 'Дампы памяти после сбоев'; Impact = 'minor'; Default = $true
       Desc = 'Файлы для разбора синих экранов и вылетов программ.'
       Warn = 'Не получится разобрать причину уже случившихся сбоев'
       Paths = { "$env:windir\Minidump", "$env:windir\MEMORY.DMP", "$Lad\CrashDumps" } }
    @{ Id = 'shaders'; Title = 'Кэш шейдеров видеокарты'; Impact = 'minor'; Default = $false
       Desc = 'Скомпилированные шейдеры игр DirectX, NVIDIA и AMD. Помогает при графических глюках после обновления драйвера.'
       Warn = 'Первые запуски игр будут подтормаживать, пока кэш не соберётся заново'
       Paths = { "$Lad\D3DSCache", "$Lad\NVIDIA\DXCache", "$Lad\NVIDIA\GLCache", "$Lad\AMD\DxCache", "$Lad\AMD\GLCache" } }
    @{ Id = 'browsers'; Title = 'Кэш браузеров'; Impact = 'minor'; Default = $false
       Desc = 'Кэш Chrome, Edge, Яндекс Браузера, Brave и Firefox. Пароли, история, вкладки и вход на сайты остаются.'
       Warn = 'Закройте браузеры перед очисткой. Сайты в первый раз будут открываться медленнее'
       Paths = {
           foreach ($b in 'Google\Chrome', 'Microsoft\Edge', 'Yandex\YandexBrowser', 'BraveSoftware\Brave-Browser') {
               Get-ChildItem "$Lad\$b\User Data" -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\Cache", "$($_.FullName)\Code Cache", "$($_.FullName)\GPUCache" }
           }
           Get-ChildItem "$Lad\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\cache2" }
       } }
    @{ Id = 'recycle'; Title = 'Корзина'; Impact = 'breaks'; Default = $false
       Desc = 'Все файлы в корзине на всех дисках.'
       Warn = 'Удалённые файлы нельзя будет восстановить'
       Paths = { }
       Size = { $sum = [long]0; foreach ($i in (New-Object -ComObject Shell.Application).NameSpace(10).Items()) { $sum += [long]$i.ExtendedProperty('Size') }; $sum }
       Clean = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } }
    @{ Id = 'winsxs'; Title = 'Старые версии компонентов Windows'; Impact = 'minor'; Default = $false
       Desc = 'Удаляет заменённые обновлениями версии системных файлов (DISM /StartComponentCleanup). Займёт 5–15 минут, размер станет известен после очистки.'
       Warn = 'Уже установленные обновления нельзя будет удалить'
       Paths = { }; Size = { $null }
       Clean = {
           $p = Start-Process dism.exe -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' -WindowStyle Hidden -PassThru
           while (-not $p.HasExited) { if (Get-Command Pump -ErrorAction SilentlyContinue) { Pump }; Start-Sleep -Milliseconds 300 }
       } }
)
#endregion

#region Driver info
function Get-AgeMonths($d) { if ($d) { [int][Math]::Floor(((Get-Date) - $d).TotalDays / 30.4) } }
function Format-Age($d) {
    $m = Get-AgeMonths $d
    if ($null -eq $m) { return '' }
    if ($m -lt 1) { 'меньше месяца назад' } elseif ($m -lt 12) { "$m мес. назад" } else { "$([Math]::Floor($m / 12)) г. назад" }
}
function Get-SearchUrl([string]$q) { 'https://www.google.com/search?q=' + [Uri]::EscapeDataString($q) }
# driver.ru finds drivers only by "BUS\VEN_xxxx&DEV_xxxx" (or HDAUDIO\FUNC_xx&VEN&DEV, USB\VID&PID) without SUBSYS/REV
function Get-HwId($ids) {
    foreach ($i in @($ids)) {
        $m = [regex]::Match("$i", '^[^\\]+\\(?:FUNC_\w+&)?(?:VEN|VID)_\w{4}&(?:DEV|PID)_\w{4}')
        if ($m.Success) { return $m.Value.ToUpper() }
    }
}
function Get-FindButtons([string]$hw, [string]$name) {
    $google = @('Поиск в Google', (Get-SearchUrl $(if ($hw) { "$hw driver" } else { "$name driver" })))
    if ($hw) { @(@('Найти на driver.ru', ('https://driver.ru/Search/' + [Uri]::EscapeDataString($hw))), $google) } else { @(, $google) }
}
$VendorSites = @(
    @{ Rx = 'ASUS'; Name = 'ASUS'; Url = 'https://www.asus.com/ru/support/download-center/'; Site = 'asus.com' }
    @{ Rx = 'Micro-Star|^MSI'; Name = 'MSI'; Url = 'https://www.msi.com/support/download'; Site = 'msi.com' }
    @{ Rx = 'Gigabyte'; Name = 'Gigabyte'; Url = 'https://www.gigabyte.com/ru/Support'; Site = 'gigabyte.com' }
    @{ Rx = 'ASRock'; Name = 'ASRock'; Url = 'https://www.asrock.com/support/index.asp'; Site = 'asrock.com' }
    @{ Rx = 'Lenovo'; Name = 'Lenovo'; Url = 'https://pcsupport.lenovo.com/'; Site = 'lenovo.com' }
    @{ Rx = 'HP|Hewlett'; Name = 'HP'; Url = 'https://support.hp.com/ru-ru/drivers'; Site = 'hp.com' }
    @{ Rx = 'Dell'; Name = 'Dell'; Url = 'https://www.dell.com/support/home/ru-ru'; Site = 'dell.com' }
    @{ Rx = 'Acer'; Name = 'Acer'; Url = 'https://www.acer.com/ru-ru/support'; Site = 'acer.com' }
    @{ Rx = 'Huawei'; Name = 'Huawei'; Url = 'https://consumer.huawei.com/ru/support/'; Site = 'huawei.com' }
    @{ Rx = 'Samsung'; Name = 'Samsung'; Url = 'https://www.samsung.com/ru/support/'; Site = 'samsung.com' }
)
$GpuSites = @{
    NVIDIA = @(@('Скачать драйвер NVIDIA', 'https://www.nvidia.com/ru-ru/geforce/drivers/'), @('NVIDIA App', 'https://www.nvidia.com/ru-ru/software/nvidia-app/'))
    AMD    = @(, @('Скачать драйвер AMD', 'https://www.amd.com/ru/support/download/drivers.html'))
    Intel  = @(, @('Intel Driver & Support Assistant', 'https://www.intel.com/content/www/us/en/support/detect.html'))
}
# Returns a list of cards: @{ Kind; Title; Details; Date; Fresh (months); Bad; Buttons = @(@(text, url)) }
# $sync (необязательно) — прогресс для фонового запуска: Value 0..100, Text
function Get-DriverInfo($sync) {
    function Step([int]$v, [string]$t) { if ($sync) { $sync.Value = $v; $sync.Text = $t } }
    $cards = New-Object System.Collections.Generic.List[object]
    Step 5 'Видеокарта…'
    foreach ($g in Get-CimInstance Win32_VideoController) {
        $vendor = switch -Regex ($g.PNPDeviceID) { 'VEN_10DE' { 'NVIDIA' } 'VEN_1002' { 'AMD' } 'VEN_8086' { 'Intel' } default { $null } }
        if (-not $vendor -and $g.Name -notmatch 'Basic Display|Базовый видеоадаптер') { continue }   # skip virtual adapters
        $basic = $g.Name -match 'Basic Display|Базовый видеоадаптер'
        $btns = $(if ($vendor) { $GpuSites[$vendor] } else { Get-FindButtons (Get-HwId $g.PNPDeviceID) $g.Name })
        $cards.Add(@{ Kind = 'Видеокарта'; Title = $g.Name; Date = $g.DriverDate; Fresh = 4; Bad = $basic; Buttons = $btns
            Details = $(if ($basic) { 'Драйвер видеокарты не установлен: работает стандартный драйвер Windows.' } else { "Драйвер $($g.DriverVersion)" }) })
    }
    Step 20 'Материнская плата и BIOS…'
    $cs = Get-CimInstance Win32_ComputerSystem; $bb = Get-CimInstance Win32_BaseBoard; $bios = Get-CimInstance Win32_BIOS
    $generic = 'System manufacturer|To Be Filled|Default string|O\.E\.M|^$'
    $isLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($isLaptop -and $cs.Manufacturer -notmatch $generic) { $mf = $cs.Manufacturer; $model = $cs.Model; $kind = 'Ноутбук' }
    else { $mf = $bb.Manufacturer; $model = $bb.Product; $kind = 'Материнская плата' }
    $v = $VendorSites | Where-Object { $mf -match $_.Rx } | Select-Object -First 1
    $btns = @(, @("Драйверы для $model", (Get-SearchUrl $(if ($v) { "site:$($v.Site) $model support drivers" } else { "$mf $model drivers" }))))
    if ($v) { $btns += , @("Сайт поддержки $($v.Name)", $v.Url) }
    $cards.Add(@{ Kind = $kind; Title = "$mf $model".Trim(); Date = $bios.ReleaseDate; Fresh = 24; Buttons = $btns
        Details = "BIOS $($bios.SMBIOSBIOSVersion). Звук, сеть, USB и BIOS берите на странице этой модели." })
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    if ($cpu -match 'AMD') { $cards.Add(@{ Kind = 'Чипсет'; Title = "Чипсет AMD ($($cpu.Trim()))"; Details = 'Драйвер чипсета AMD улучшает работу планировщика Ryzen и энергосбережения.'; Buttons = @(, @('Скачать драйвер чипсета AMD', 'https://www.amd.com/ru/support/download/drivers.html')) }) }
    elseif ($cpu -match 'Intel') { $cards.Add(@{ Kind = 'Чипсет'; Title = "Чипсет Intel ($($cpu.Trim()))"; Details = 'Intel Driver & Support Assistant сам найдёт драйверы чипсета и других устройств Intel.'; Buttons = @(, @('Intel Driver & Support Assistant', 'https://www.intel.com/content/www/us/en/support/detect.html')) }) }
    Step 40 'Сеть и звук…'
    $skip = 'Microsoft|VMware|VirtualBox|Hyper-V|Virtual|TAP-|Wintun|-tun|Tunnel|WireGuard|OpenVPN|Npcap|WAN Miniport|SoftEther|NVIDIA High Definition|AMD High Definition|Steam|VB-Audio|Bluetooth|Remote|Loopback'
    Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET' OR DeviceClass='MEDIA'" -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceName -and $_.DriverProviderName -notmatch 'Microsoft' -and "$($_.DeviceName) $($_.DriverProviderName)" -notmatch $skip } |
        Sort-Object DeviceName -Unique | Select-Object -First 6 | ForEach-Object {
            $hw = Get-HwId @($_.HardWareID, $_.DeviceID)
            $cards.Add(@{ Kind = $(if ($_.DeviceClass -eq 'NET') { 'Сеть' } else { 'Звук' }); Title = $_.DeviceName; Date = $_.DriverDate; Fresh = 24
                Details = "$($_.DriverProviderName), драйвер $($_.DriverVersion)$(if ($hw) { ". ID: $hw" })"; Buttons = (Get-FindButtons $hw $_.DeviceName) })
        }
    # code 22 = disabled on purpose, not broken
    Step 75 'Устройства с ошибками…'
    $bad =@(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 22' -ErrorAction SilentlyContinue)
    foreach ($d in $bad) {
        $hw = Get-HwId @($d.HardwareID + $d.DeviceID)
        $why = $(if ($d.ConfigManagerErrorCode -eq 28) { 'Драйвер не установлен.' } else { "Ошибка устройства (код $($d.ConfigManagerErrorCode))." })
        $cards.Add(@{ Kind = 'Устройство с ошибкой'; Title = $(if ($d.Name) { $d.Name } else { $d.DeviceID }); Bad = $true
            Details = "$why $(if ($hw) { "ID: $hw" })"; Buttons = (Get-FindButtons $hw $d.Name) })
    }
    if (-not $bad.Count) { $cards.Add(@{ Kind = 'Проверка устройств'; Title = 'Все устройства работают'; Details = 'В Диспетчере устройств нет устройств без драйвера или с ошибкой.'; Buttons = @() }) }
    $cards
}
#endregion

if ($Selftest) {
    "== cleanup"
    foreach ($c in $script:CleanItems) { '{0,-10} {1,10}' -f $c.Id, (Format-Size (Get-CleanSize $c)) }
    "== startup"
    foreach ($s in Get-StartupItems) {
        $cmd = "$($s.Command)"; if ($cmd.Length -gt 50) { $cmd = $cmd.Substring(0, 50) + '…' }
        '{0,-4} {1,-32} {2,-38} {3}' -f $(if ($s.On) { 'on' } else { 'off' }), $s.Name, $s.Label, $cmd
    }
    "== drivers"
    foreach ($d in Get-DriverInfo) {
        $urls = @($d.Buttons | ForEach-Object { $_[1] }) -join ' '
        '{0,-22} {1,-45} {2,-11} {3}' -f $d.Kind, $d.Title, $(if ($d.Date) { $d.Date.ToString('yyyy-MM-dd') } else { '-' }), $urls
    }
    Initialize-Items
    $script:Items | ForEach-Object { '{0,-40} {1,-13} {2,-7} {3}' -f $_.Id, $_.Cat, $_.Impact, $_.State }
    "items: $($script:Items.Count) of $($script:AllItems.Count)"
    "detected: " + (($script:Detected.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
    "questions shown: " + (($script:Questions | Where-Object { Test-Question $_ } | ForEach-Object { $_.Id }) -join ', ')
    $ans = Get-Answers
    "answers: " + (($script:Questions | Where-Object { Test-Question $_ } | ForEach-Object { "$($_.Id)=$($ans[$_.Id])" }) -join ' ')
    "plan with default answers: $(Get-PlanCount $ans) changes"
    exit
}

#region UI
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace WT -Name Native -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
'@
if (-not $Snapshot) { [void][WT.Native]::ShowWindow([WT.Native]::GetConsoleWindow(), 0) }

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OknoTune" Width="1180" Height="800" MinWidth="1040" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#0F1115" Foreground="#E6E8EB"
        FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
 <Window.Resources>
  <Style x:Key="Toggle" TargetType="CheckBox">
   <Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="CheckBox">
     <Grid Width="44" Height="24" Background="Transparent">
      <Border x:Name="Track" CornerRadius="12" Background="#252B35" BorderBrush="#3A414D" BorderThickness="1"/>
      <Ellipse x:Name="Thumb" Width="14" Height="14" Fill="#AEB4BF" HorizontalAlignment="Left" Margin="5,0,0,0"/>
     </Grid>
     <ControlTemplate.Triggers>
      <Trigger Property="IsChecked" Value="True">
       <Setter TargetName="Track" Property="Background" Value="#4F8CFF"/>
       <Setter TargetName="Track" Property="BorderBrush" Value="#4F8CFF"/>
       <Setter TargetName="Thumb" Property="Fill" Value="White"/>
       <Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/>
       <Setter TargetName="Thumb" Property="Margin" Value="0,0,5,0"/>
      </Trigger>
      <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.35"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Btn" TargetType="Button">
   <Setter Property="Foreground" Value="#E6E8EB"/><Setter Property="Background" Value="#1C2129"/><Setter Property="BorderBrush" Value="#2E3540"/>
   <Setter Property="Padding" Value="14,8"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="13"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="Button">
     <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
      <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
     </Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#4F8CFF"/></Trigger>
      <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.4"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
   <Setter Property="Background" Value="#4F8CFF"/><Setter Property="BorderBrush" Value="#4F8CFF"/>
   <Setter Property="Foreground" Value="White"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="20,8"/>
  </Style>
  <Style x:Key="Warn" TargetType="Button" BasedOn="{StaticResource Btn}">
   <Setter Property="Background" Value="#2E2610"/><Setter Property="BorderBrush" Value="#6B5418"/><Setter Property="Foreground" Value="#F2CC60"/>
  </Style>
  <Style x:Key="Link" TargetType="Button">
   <Setter Property="Foreground" Value="#7FA8FF"/><Setter Property="FontSize" Value="12"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="Button"><Border Background="Transparent" Padding="2"><ContentPresenter/></Border></ControlTemplate>
   </Setter.Value></Setter>
  </Style>
  <Style x:Key="Chip" TargetType="ToggleButton">
   <Setter Property="Foreground" Value="#AEB4BF"/><Setter Property="FontSize" Value="12"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ToggleButton">
     <Border x:Name="B" CornerRadius="14" Padding="12,5" Background="#161A20" BorderBrush="#2A303A" BorderThickness="1"><ContentPresenter/></Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#3D4553"/></Trigger>
      <Trigger Property="IsChecked" Value="True">
       <Setter TargetName="B" Property="Background" Value="#1E2A44"/><Setter TargetName="B" Property="BorderBrush" Value="#4F8CFF"/><Setter Property="Foreground" Value="#CFE0FF"/>
      </Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Seg" TargetType="RadioButton">
   <Setter Property="Foreground" Value="#AEB4BF"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="RadioButton">
     <Border x:Name="B" CornerRadius="7" Padding="18,6" Background="Transparent"><ContentPresenter/></Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#1F2530"/></Trigger>
      <Trigger Property="IsChecked" Value="True"><Setter TargetName="B" Property="Background" Value="#4F8CFF"/><Setter Property="Foreground" Value="White"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Nav" TargetType="ListBoxItem">
   <Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ListBoxItem">
     <Border x:Name="B" CornerRadius="8" Padding="12,6" Margin="0,1" Background="Transparent">
      <ContentPresenter/>
     </Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#1A1F27"/></Trigger>
      <Trigger Property="IsSelected" Value="True"><Setter TargetName="B" Property="Background" Value="#222A36"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ScrollBar">
   <Setter Property="Width" Value="8"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ScrollBar">
     <Track x:Name="PART_Track" IsDirectionReversed="True">
      <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="#2E3540"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
     </Track>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Search" TargetType="TextBox">
   <Setter Property="Foreground" Value="#E6E8EB"/><Setter Property="CaretBrush" Value="#E6E8EB"/><Setter Property="FontSize" Value="13"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="TextBox">
     <Border x:Name="B" Background="#161A20" BorderBrush="#2A303A" BorderThickness="1" CornerRadius="8" Padding="32,7,10,7">
      <ScrollViewer x:Name="PART_ContentHost"/>
     </Border>
     <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#4F8CFF"/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>

 <Grid Background="#0F1115">
  <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

  <!-- Sidebar -->
  <Border Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,0,1,0">
   <DockPanel Margin="16,24,16,18">
    <StackPanel DockPanel.Dock="Top" Margin="8,0,0,16">
     <StackPanel Orientation="Horizontal">
      <Border Width="32" Height="32" CornerRadius="9" Background="#4F8CFF">
       <TextBlock Text="&#xE945;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="White" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock Text="OknoTune" FontSize="21" FontWeight="SemiBold" Margin="12,0,0,0" VerticalAlignment="Center"/>
     </StackPanel>
     <TextBlock Text="Настройка Windows с откатом" Foreground="#8B93A1" FontSize="12" Margin="0,10,0,0"/>
    </StackPanel>
    <StackPanel DockPanel.Dock="Bottom" Margin="8,10,0,0">
     <TextBlock x:Name="SysInfo" Foreground="#5F6774" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,10"/>
     <Button x:Name="BtnLog" Content="Папка журнала" Style="{StaticResource Btn}" HorizontalAlignment="Left" FontSize="12" Padding="12,6"/>
    </StackPanel>
    <ListBox x:Name="Nav" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Nav}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Auto"/>
   </DockPanel>
  </Border>

  <Grid Grid.Column="1">
   <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

   <!-- Home -->
   <ScrollViewer x:Name="HomeView" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
    <StackPanel Margin="40,34,40,28" MaxWidth="980" HorizontalAlignment="Left">
     <TextBlock Text="Настроим Windows" FontSize="28" FontWeight="SemiBold"/>
     <TextBlock Text="Ответьте на несколько вопросов «да/нет», проверьте, что изменится, и примените. Любое изменение можно откатить." Foreground="#8B93A1" FontSize="14" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Border Background="#171B22" BorderBrush="#232831" BorderThickness="1" CornerRadius="14" Padding="24,20" Margin="0,22,0,0">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel>
        <StackPanel Orientation="Horizontal">
         <TextBlock x:Name="HomeCount" FontSize="32" FontWeight="SemiBold"/>
         <TextBlock Text="настроек уже применено" Foreground="#8B93A1" FontSize="14" Margin="12,0,0,6" VerticalAlignment="Bottom"/>
        </StackPanel>
        <ProgressBar x:Name="HomeBar" Height="6" Margin="0,12,24,0" Foreground="#4ADE80" Background="#232A35" BorderThickness="0"/>
       </StackPanel>
       <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="12,0,0,0">
        <TextBlock x:Name="HomeApps" Foreground="#AEB4BF" FontSize="13"/>
        <TextBlock x:Name="HomeSnaps" Foreground="#AEB4BF" FontSize="13" Margin="0,6,0,0"/>
       </StackPanel>
      </Grid>
     </Border>
     <Border x:Name="RebootBanner" Visibility="Collapsed" Background="#2A2311" BorderBrush="#6B5418" BorderThickness="1" CornerRadius="12" Padding="20,14" Margin="0,12,0,0">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <TextBlock Text="Часть изменений заработает только после перезагрузки." Foreground="#F2CC60" FontSize="13" VerticalAlignment="Center"/>
       <Button x:Name="BtnReboot2" Grid.Column="1" Content="Перезагрузить" Style="{StaticResource Warn}"/>
      </Grid>
     </Border>
     <Border Background="#16213A" BorderBrush="#2B4A86" BorderThickness="1" CornerRadius="16" Padding="28,24" Margin="0,16,0,0">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
       <Border Width="52" Height="52" CornerRadius="14" Background="#4F8CFF" VerticalAlignment="Top">
        <TextBlock Text="&#xE945;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="White" FontSize="24" HorizontalAlignment="Center" VerticalAlignment="Center"/>
       </Border>
       <StackPanel Grid.Column="1" Margin="20,0,0,0">
        <TextBlock Text="Быстрая настройка" FontSize="20" FontWeight="SemiBold"/>
        <TextBlock Text="Несколько вопросов «да/нет» о том, как вы пользуетесь компьютером. Железо определим сами. OknoTune подберёт настройки и перед применением покажет, что изменится." Foreground="#AEB8CC" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,0"/>
        <TextBlock x:Name="HomePlan" Foreground="#9DB4FF" FontSize="13" Margin="0,12,0,0"/>
        <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
         <Button x:Name="BtnStart" Content="Начать" Style="{StaticResource Primary}" Padding="28,10" FontSize="14"/>
         <Button x:Name="BtnManual" Content="Все настройки вручную" Style="{StaticResource Btn}" Margin="10,0,0,0" Padding="18,10"/>
        </StackPanel>
       </StackPanel>
      </Grid>
     </Border>
     <TextBlock Text="Что значат цвета" FontSize="15" FontWeight="SemiBold" Margin="0,24,0,10"/>
     <UniformGrid Columns="2">
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#3FB950"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Ничего не теряете" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Включается автоматически" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#D29922"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Мелкие ограничения" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Что-то станет чуть иначе, написано на карточке" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#F85149"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Отключается функция" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Перестанет работать то, что указано" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#A371F7"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Удаление приложения" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Вернуть можно из Microsoft Store" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
     </UniformGrid>
    </StackPanel>
   </ScrollViewer>

   <!-- Wizard -->
   <Grid x:Name="WizardView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,10">
     <TextBlock Text="Быстрая настройка" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Ответы уже подставлены: железо определено автоматически, остальное по тому, что сейчас настроено на этом ПК. Поменяйте то, что не так. Зелёные настройки (без потерь) включатся в любом случае." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="WizList" MaxWidth="900" HorizontalAlignment="Left"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="WizCount" FontSize="13" Foreground="#AEB4BF" VerticalAlignment="Center"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="WizBack" Content="Назад" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="WizNext" Content="Дальше: что изменится" Style="{StaticResource Primary}"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <!-- List -->
   <Grid x:Name="ListView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="32,26,32,12">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
       <TextBlock x:Name="Heading" Text="Все настройки" FontSize="26" FontWeight="SemiBold"/>
       <TextBlock x:Name="SubHeading" Foreground="#8B93A1" FontSize="13" Margin="0,4,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
       <Button x:Name="BtnSafe" Content="Отметить зелёные" Style="{StaticResource Btn}" Margin="0,0,10,0"/>
       <Grid Width="220">
        <TextBox x:Name="Search" Style="{StaticResource Search}"/>
        <TextBlock Text="&#xE721;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="#6B7380" FontSize="13" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <TextBlock x:Name="SearchHint" Text="Поиск" Foreground="#6B7380" FontSize="13" Margin="33,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
       </Grid>
      </StackPanel>
     </Grid>
     <Grid Margin="0,14,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal">
       <ToggleButton x:Name="ChipPending" Content="Не применено" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
       <ToggleButton x:Name="ChipSafe" Content="Без потерь" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
       <ToggleButton x:Name="ChipReboot" Content="С перезагрузкой" Style="{StaticResource Chip}"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
       <Ellipse Width="8" Height="8" Fill="#3FB950"/><TextBlock Text="без потерь" Foreground="#8B93A1" FontSize="12" Margin="6,0,12,0"/>
       <Ellipse Width="8" Height="8" Fill="#D29922"/><TextBlock Text="мелочи" Foreground="#8B93A1" FontSize="12" Margin="6,0,12,0"/>
       <Ellipse Width="8" Height="8" Fill="#F85149"/><TextBlock Text="отключает функцию" Foreground="#8B93A1" FontSize="12" Margin="6,0,12,0"/>
       <Ellipse Width="8" Height="8" Fill="#A371F7"/><TextBlock Text="удаление" Foreground="#8B93A1" FontSize="12" Margin="6,0,0,0"/>
      </StackPanel>
     </Grid>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="32,0,24,12">
     <StackPanel x:Name="List"/>
    </ScrollViewer>
   </Grid>

   <!-- History -->
   <Grid x:Name="HistoryView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,16">
     <TextBlock Text="История изменений" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock x:Name="HistSub" Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Button x:Name="BtnHistClear" Content="Очистить историю" Style="{StaticResource Btn}" FontSize="12" Padding="12,6" Margin="0,14,0,0" HorizontalAlignment="Left"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,16">
     <StackPanel x:Name="HistList" MaxWidth="900" HorizontalAlignment="Left"/>
    </ScrollViewer>
   </Grid>

   <!-- Cleanup -->
   <Grid x:Name="CleanView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,14">
     <TextBlock Text="Очистка диска" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Удаляет временные и ненужные файлы. Документы, фото, загрузки и настройки программ не трогаются." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Border Background="#171B22" BorderBrush="#232831" BorderThickness="1" CornerRadius="14" Padding="24,16" Margin="0,16,0,0" MaxWidth="900" HorizontalAlignment="Stretch">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel>
        <TextBlock x:Name="CleanTotal" FontSize="28" FontWeight="SemiBold"/>
        <TextBlock Text="можно освободить с выбранными пунктами" Foreground="#8B93A1" FontSize="13"/>
       </StackPanel>
       <TextBlock x:Name="CleanDisk" Grid.Column="1" Foreground="#AEB4BF" FontSize="13" VerticalAlignment="Center"/>
      </Grid>
     </Border>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="CleanList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
       <TextBlock x:Name="CleanStatus" FontSize="13" Foreground="#AEB4BF" TextTrimming="CharacterEllipsis"/>
       <ProgressBar x:Name="CleanBar" Height="3" Margin="0,6,0,0" Visibility="Collapsed" Foreground="#4F8CFF" Background="#232A35" BorderThickness="0" Maximum="100"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="BtnCleanMgr" Content="Очистка диска Windows" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnRescan" Content="Пересчитать" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnClean" Content="Очистить" Style="{StaticResource Primary}"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <!-- Drivers -->
   <Grid x:Name="DriversView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,14">
     <TextBlock Text="Драйверы" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="OknoTune ничего не скачивает сам: он определяет железо, показывает возраст драйверов и открывает нужную страницу производителя в браузере." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="DrvList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="DrvStatus" FontSize="13" Foreground="#AEB4BF" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="BtnWuDrivers" Content="Драйверы в Windows Update" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnDevMgr" Content="Диспетчер устройств" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnDrvRescan" Content="Проверить заново" Style="{StaticResource Btn}"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <!-- Apps -->
   <Grid x:Name="AppsView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,4">
     <TextBlock Text="Полезные программы" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Проверенные бесплатные программы. «Установить» скачивает обычный установщик с сайта разработчика через winget (не версию из Microsoft Store) и запускает его в отдельном окне. «Сайт» открывает страницу программы." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,16">
     <StackPanel x:Name="AppsList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
   </Grid>

   <!-- Fixes -->
   <Grid x:Name="FixView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,4">
     <TextBlock Text="Исправления" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Что-то перестало работать после настройки? Исправление включит нужные службы Windows и сбросит то, что обычно ломается. Отключённое OknoTune или другой программой — неважно." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,16">
     <StackPanel x:Name="FixList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
   </Grid>

   <!-- Startup -->
   <Grid x:Name="StartupView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,14">
     <TextBlock Text="Автозагрузка" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Программы, которые Windows запускает при входе в систему. Отключение обратимо: OknoTune хранит отключённую запись и возвращает её одним нажатием." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Border Background="#171B22" BorderBrush="#232831" BorderThickness="1" CornerRadius="14" Padding="24,14" Margin="0,16,0,0" MaxWidth="900" HorizontalAlignment="Stretch">
      <TextBlock x:Name="SuSummary" FontSize="13" Foreground="#AEB4BF" TextWrapping="Wrap"/>
     </Border>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="SuList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="SuStatus" FontSize="13" Foreground="#AEB4BF" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="BtnSuRescan" Content="Проверить заново" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnSuApply" Content="Применить" Style="{StaticResource Primary}" IsEnabled="False"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <TextBlock x:Name="Loading" Text="Проверяю систему…" Foreground="#8B93A1" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
   <StackPanel x:Name="Busy" Width="340" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False">
    <TextBlock x:Name="BusyText" Foreground="#8B93A1" FontSize="14" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center"/>
    <ProgressBar x:Name="BusyBar" Height="4" Margin="0,12,0,0" Foreground="#4F8CFF" Background="#232A35" BorderThickness="0" Maximum="100"/>
   </StackPanel>

   <!-- Footer (list view) -->
   <Border x:Name="Footer" Grid.Row="1" Visibility="Collapsed" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="32,14">
    <Grid>
     <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBlock x:Name="Status" FontSize="13" Foreground="#AEB4BF" TextTrimming="CharacterEllipsis" VerticalAlignment="Center" Margin="0,0,16,0"/>
     <StackPanel Grid.Column="1" Orientation="Horizontal">
      <Button x:Name="BtnReboot" Content="Перезагрузить" Style="{StaticResource Warn}" Margin="0,0,8,0" Visibility="Collapsed"/>
      <Button x:Name="BtnProfSave" Content="Сохранить профиль" Style="{StaticResource Btn}" Margin="0,0,8,0" ToolTip="Сохранить выбранные настройки в файл, чтобы применить их на другом ПК"/>
      <Button x:Name="BtnProfLoad" Content="Загрузить профиль" Style="{StaticResource Btn}" Margin="0,0,8,0" ToolTip="Отметить настройки из файла профиля. Применяются они только после проверки"/>
      <Button x:Name="BtnReset" Content="Сбросить выбор" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
      <Button x:Name="BtnApply" Content="Проверить и применить" Style="{StaticResource Primary}" IsEnabled="False"/>
     </StackPanel>
    </Grid>
   </Border>
  </Grid>

  <!-- Overlay dialog -->
  <Grid x:Name="Overlay" Grid.ColumnSpan="2" Background="#B3080A0E" Visibility="Collapsed">
   <Border Width="660" MaxHeight="680" Background="#151920" BorderBrush="#2A303A" BorderThickness="1" CornerRadius="14" VerticalAlignment="Center" HorizontalAlignment="Center">
    <Grid Margin="28,24">
     <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
     <StackPanel>
      <TextBlock x:Name="OvTitle" FontSize="22" FontWeight="SemiBold"/>
      <TextBlock x:Name="OvSub" Foreground="#8B93A1" FontSize="13" Margin="0,4,0,0" TextWrapping="Wrap"/>
     </StackPanel>
     <ScrollViewer Grid.Row="1" Margin="0,16,0,0" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="OvBody" Margin="0,0,10,0"/></ScrollViewer>
     <ProgressBar x:Name="OvProgress" Grid.Row="2" Height="4" Margin="0,14,0,0" Visibility="Collapsed" Foreground="#4F8CFF" Background="#232A35" BorderThickness="0" Maximum="100"/>
     <Grid Grid.Row="3" Margin="0,20,0,0">
      <StackPanel x:Name="OvLeft" Orientation="Horizontal" VerticalAlignment="Center"/>
      <StackPanel x:Name="OvButtons" Orientation="Horizontal" HorizontalAlignment="Right"/>
     </Grid>
    </Grid>
   </Border>
  </Grid>
 </Grid>
</Window>
'@

$CardXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Margin="0,0,0,10" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="5"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Border Name="Stripe" CornerRadius="9,0,0,9"/>
  <StackPanel Grid.Column="1" Margin="16,13,0,13">
   <WrapPanel>
    <TextBlock Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB" Margin="0,0,10,0" VerticalAlignment="Center"/>
    <Border Name="Boot" CornerRadius="9" Padding="8,1" Background="#1F2638" VerticalAlignment="Center" Visibility="Collapsed"><TextBlock Text="перезагрузка" FontSize="11" Foreground="#9DB4FF"/></Border>
   </WrapPanel>
   <TextBlock Name="Sh" TextWrapping="Wrap" Foreground="#AEB4BF" FontSize="13" Margin="0,4,0,0"/>
   <TextBlock Name="W" TextWrapping="Wrap" FontSize="13" Margin="0,4,0,0" Visibility="Collapsed"/>
   <TextBlock Name="D" TextWrapping="Wrap" Foreground="#8B93A1" FontSize="13" Margin="0,8,0,0" Visibility="Collapsed"/>
   <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
    <TextBlock Name="S" FontSize="12" VerticalAlignment="Center"/>
    <Button Name="More" Content="Подробнее ▾" Margin="14,0,0,0" VerticalAlignment="Center"/>
   </StackPanel>
  </StackPanel>
  <CheckBox Name="C" Grid.Column="2" VerticalAlignment="Center" Margin="20,0,18,0"/>
 </Grid>
</Border>
'@
$HeaderXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="2,18,4,10">
 <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
 <TextBlock Name="L" FontSize="11" FontWeight="SemiBold" Foreground="#6B7380" VerticalAlignment="Center"/>
 <Button Name="All" Grid.Column="1" Content="Отметить всё в разделе"/>
</Grid>
'@
$NavXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
 <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
 <TextBlock Name="G" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="15" Foreground="#AEB4BF" VerticalAlignment="Center"/>
 <TextBlock Name="L" Grid.Column="1" FontSize="14" Foreground="#E6E8EB" Margin="12,0,0,0" VerticalAlignment="Center"/>
 <Border Name="Badge" Grid.Column="2" CornerRadius="9" Background="#4F8CFF" Padding="7,1" Visibility="Collapsed" VerticalAlignment="Center">
  <TextBlock Name="BadgeT" FontSize="11" Foreground="White" FontWeight="SemiBold"/>
 </Border>
</Grid>
'@
$QuestionXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Padding="20,14" Margin="0,0,0,8" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel>
   <TextBlock Name="Q" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB" TextWrapping="Wrap"/>
   <TextBlock Name="H" FontSize="13" Foreground="#8B93A1" TextWrapping="Wrap" Margin="0,4,0,0"/>
   <TextBlock Name="A" Text="определено автоматически" FontSize="11" Foreground="#7FA8FF" Margin="0,6,0,0" Visibility="Collapsed"/>
  </StackPanel>
  <Border Grid.Column="1" CornerRadius="9" Background="#12151B" BorderBrush="#2A303A" BorderThickness="1" Padding="3" VerticalAlignment="Center" Margin="24,0,0,0">
   <StackPanel Orientation="Horizontal">
    <RadioButton Name="Y" Content="Да"/>
    <RadioButton Name="N" Content="Нет"/>
   </StackPanel>
  </Border>
 </Grid>
</Border>
'@
$HistXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Padding="20,15" Margin="0,0,0,10" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel>
   <TextBlock Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB"/>
   <TextBlock Name="S" FontSize="12" Foreground="#8B93A1" Margin="0,4,0,0"/>
   <TextBlock Name="L" FontSize="13" Foreground="#AEB4BF" TextWrapping="Wrap" Margin="0,8,0,0"/>
  </StackPanel>
  <Button Name="B" Grid.Column="1" Content="Откатить" VerticalAlignment="Center" Margin="24,0,0,0"/>
 </Grid>
</Border>
'@

$script:Win = [Windows.Markup.XamlReader]::Parse($Xaml)
foreach ($n in 'Nav', 'SysInfo', 'BtnLog', 'HomeView', 'HomeCount', 'HomeBar', 'HomeApps', 'HomeSnaps', 'HomePlan', 'RebootBanner', 'BtnReboot2', 'BtnStart', 'BtnManual',
               'WizardView', 'WizList', 'WizCount', 'WizBack', 'WizNext', 'ListView', 'Heading', 'SubHeading', 'BtnSafe', 'Search', 'SearchHint',
               'ChipPending', 'ChipSafe', 'ChipReboot', 'List', 'HistoryView', 'HistSub', 'HistList', 'BtnHistClear', 'Loading', 'Footer', 'Status', 'BtnReboot', 'BtnReset', 'BtnApply',
               'Overlay', 'OvTitle', 'OvSub', 'OvBody', 'OvProgress', 'OvLeft', 'OvButtons',
               'CleanView', 'CleanTotal', 'CleanDisk', 'CleanList', 'CleanStatus', 'BtnCleanMgr', 'BtnRescan', 'BtnClean',
               'StartupView', 'SuSummary', 'SuList', 'SuStatus', 'BtnSuRescan', 'BtnSuApply',
               'DriversView', 'DrvList', 'DrvStatus', 'BtnWuDrivers', 'BtnDevMgr', 'BtnDrvRescan', 'AppsView', 'AppsList', 'FixView', 'FixList', 'BtnProfSave', 'BtnProfLoad', 'Busy', 'BusyText', 'BusyBar', 'CleanBar') {
    Set-Variable -Scope Script -Name $n -Value $script:Win.FindName($n)
}
$script:Styles = @{}
foreach ($s in 'Toggle', 'Btn', 'Primary', 'Warn', 'Link', 'Seg') { $script:Styles[$s] = $script:Win.FindResource($s) }
$bc = New-Object Windows.Media.BrushConverter
function Brush([string]$hex) { $bc.ConvertFromString($hex) }
function New-Xaml([string]$x) { [Windows.Markup.XamlReader]::Parse($x) }

$Cats = [ordered]@{ 'Приватность' = 0xE72E; 'Реклама' = 0xE789; 'Игры' = 0xE7FC; 'Система' = 0xE713; 'Обновления' = 0xE777; 'Службы' = 0xE90F
                    'Безопасность' = 0xEA18; 'Удобство' = 0xE771; 'Компоненты' = 0xE7B8; 'Приложения' = 0xE719 }
$ImpactColor = @{ none = '#3FB950'; minor = '#D29922'; breaks = '#F85149'; remove = '#A371F7' }
$ImpactText = @{ none = 'Ничего не теряете'; minor = 'Мелкие ограничения'; breaks = 'Отключается функция Windows'; remove = 'Удаление приложения' }
$WarnColor = @{ minor = '#E3B341'; breaks = '#FF7B72'; remove = '#C4A5FF' }
$script:CurCat = 'Все'; $script:CurView = 'home'; $script:Answers = @{}; $script:NavBusy = $false
$script:Headers = @{}; $script:NavItems = @{}; $script:QRadios = @{}
$script:Ru = [Globalization.CultureInfo]'ru-RU'

function Pump { $script:Win.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::Background) }

#region Background work (окно не зависает, пока идёт скан)
# $work выполняется в отдельном runspace: туда копируются функции $fns и переменные $vars.
# $work получает $sync: Value (0..100), Text, Partial (промежуточные результаты); его вывод попадает в $sync.Result.
# $tick вызывается в потоке UI каждые 150 мс, $done — один раз в конце (ошибка — в $sync.Error).
$script:BgJobs = @{}
function Start-Bg([string]$key, [string[]]$fns, [hashtable]$vars, [scriptblock]$work, [scriptblock]$tick, [scriptblock]$done) {
    if ($script:BgJobs[$key]) { return }   # уже идёт
    $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($f in $fns) { $iss.Commands.Add((New-Object Management.Automation.Runspaces.SessionStateFunctionEntry $f, (Get-Item "function:$f").Definition)) }
    foreach ($k in $vars.Keys) { $iss.Variables.Add((New-Object Management.Automation.Runspaces.SessionStateVariableEntry $k, $vars[$k], '')) }
    $sync = [hashtable]::Synchronized(@{ Done = $false; Error = $null; Result = $null; Value = 0; Text = ''; Partial = [hashtable]::Synchronized(@{}) })
    $ps = [powershell]::Create($iss)
    # скрипт-блоки нельзя выполнять в чужом runspace — передаём текст и собираем заново
    [void]$ps.AddScript({
        param($code, $sync)
        try { $sync.Result = @(& ([scriptblock]::Create($code)) $sync) } catch { $sync.Error = "$_" } finally { $sync.Done = $true }
    }).AddArgument($work.ToString()).AddArgument($sync)
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150); $timer.Tag = $key
    $timer.Add_Tick({ Step-Bg $this.Tag })
    $script:BgJobs[$key] = @{ Ps = $ps; Sync = $sync; Tick = $tick; Done = $done; Timer = $timer; Async = $ps.BeginInvoke() }
    $timer.Start()
}
function Step-Bg([string]$key) {
    $j = $script:BgJobs[$key]
    if (-not $j) { return }
    if ($j.Tick) { & $j.Tick $j.Sync }
    if (-not $j.Sync.Done) { return }
    $j.Timer.Stop(); $script:BgJobs.Remove($key)
    try { $j.Ps.Runspace.Close(); $j.Ps.Dispose() } catch {}
    & $j.Done $j.Sync
}
function Wait-Bg {
    # для -Snapshot: дождаться всех фоновых задач, не полагаясь на таймер
    while ($script:BgJobs.Count) { foreach ($k in @($script:BgJobs.Keys)) { Step-Bg $k }; Start-Sleep -Milliseconds 50 }
}
# Надпись с полосой по центру вкладки, пока идёт её скан; видна только на своей вкладке.
$script:BusyState = @{}
function Set-Busy([string]$view, [string]$text, [double]$value) { $script:BusyState[$view] = @{ Text = $text; Value = $value }; Update-Busy }
function Clear-Busy([string]$view) { $script:BusyState.Remove($view); Update-Busy }
function Update-Busy {
    $b = $script:BusyState[$script:CurView]
    $script:Busy.Visibility = $(if ($b) { 'Visible' } else { 'Collapsed' })
    if ($b) { $script:BusyText.Text = $b.Text; $script:BusyBar.Value = $b.Value }
}
#endregion
function Write-Log([string]$m) {
    Add-Content -Path $script:LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m) -Encoding UTF8
    $script:Status.Text = $m
    if ($script:Overlay.Visibility -eq 'Visible' -and $script:OvProgress.Visibility -eq 'Visible') { $script:OvSub.Text = $m }
}
function Test-Pending($it) { $it.Toggle -and $it.Toggle.IsEnabled -and ([bool]$it.Toggle.IsChecked -ne ($it.State -eq 'on')) }
function Get-Verb($it, [switch]$Done) {
    # «применить», а не «включить»: многие твики как раз отключают функцию Windows
    if ($it.Appx) { $(if ($Done) { 'удалено' } else { 'удалить' }) }
    elseif ($it.Toggle.IsChecked) { $(if ($Done) { 'применено' } else { 'применить' }) }
    else { $(if ($Done) { 'возвращено как в Windows' } else { 'вернуть как в Windows' }) }
}

#region Reboot flag (cleared by an actual reboot)
function Get-BootTicks { "$((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.Ticks)" }
function Set-RebootPending { Set-Content -Path $script:RebootFile -Value (Get-BootTicks); $script:RebootPending = $true; Update-RebootUi }
function Update-RebootUi {
    $v = $(if ($script:RebootPending) { 'Visible' } else { 'Collapsed' })
    $script:RebootBanner.Visibility = $v; $script:BtnReboot.Visibility = $v
}
function Invoke-Reboot {
    if ([Windows.MessageBox]::Show($script:Win, "Перезагрузить компьютер сейчас?`nСохраните открытые файлы.", 'OknoTune', 'YesNo', 'Question') -eq 'Yes') {
        try { Restart-Computer -ErrorAction Stop } catch { [void][Windows.MessageBox]::Show($script:Win, "Не удалось перезагрузить: $($_.Exception.Message)", 'OknoTune') }
    }
}
#endregion

#region Overlay dialog
function Show-Overlay([string]$title, [string]$sub) {
    $script:OvTitle.Text = $title; $script:OvSub.Text = $sub
    $script:OvBody.Children.Clear(); $script:OvLeft.Children.Clear(); $script:OvButtons.Children.Clear()
    $script:OvProgress.Visibility = 'Collapsed'; $script:OvProgress.Value = 0
    $script:Overlay.Visibility = 'Visible'
}
function Hide-Overlay { $script:Overlay.Visibility = 'Collapsed'; Show-View $script:CurView }
function Add-OvText([string]$text, [string]$color = '#C9CED6', [double]$size = 13, [string]$margin = '0,0,0,6', [switch]$Bold) {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $text; $tb.Foreground = Brush $color; $tb.FontSize = $size; $tb.TextWrapping = 'Wrap'; $tb.Margin = $margin
    if ($Bold) { $tb.FontWeight = 'SemiBold' }
    [void]$script:OvBody.Children.Add($tb)
}
function Add-OvLine([string]$main, [string]$tail, [string]$dot) {
    # DockPanel, а не горизонтальный StackPanel: иначе длинный текст не переносится и обрезается
    $sp = New-Object Windows.Controls.DockPanel; $sp.Margin = '0,0,0,5'
    $e = New-Object Windows.Shapes.Ellipse; $e.Width = 7; $e.Height = 7; $e.Fill = Brush $dot; $e.Margin = '2,6,10,0'; $e.VerticalAlignment = 'Top'
    $tb = New-Object Windows.Controls.TextBlock; $tb.FontSize = 13; $tb.TextWrapping = 'Wrap'
    $r1 = New-Object Windows.Documents.Run $main; $r1.Foreground = Brush '#E6E8EB'
    $r2 = New-Object Windows.Documents.Run $tail; $r2.Foreground = Brush '#8B93A1'
    $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
    [void]$sp.Children.Add($e); [void]$sp.Children.Add($tb)
    [void]$script:OvBody.Children.Add($sp)
}
function Add-OvBox([string]$title, [string[]]$lines, [string]$bg, [string]$border, [string]$fg) {
    $b = New-Object Windows.Controls.Border
    $b.Background = Brush $bg; $b.BorderBrush = Brush $border; $b.BorderThickness = 1; $b.CornerRadius = 10; $b.Padding = '16,12'; $b.Margin = '0,10,0,6'
    $sp = New-Object Windows.Controls.StackPanel
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $title; $t.FontWeight = 'SemiBold'; $t.Foreground = Brush $fg; $t.FontSize = 13; $t.Margin = '0,0,0,6'
    [void]$sp.Children.Add($t)
    foreach ($l in $lines) {
        $x = New-Object Windows.Controls.TextBlock; $x.Text = "•  $l"; $x.Foreground = Brush $fg; $x.FontSize = 13; $x.TextWrapping = 'Wrap'; $x.Margin = '0,0,0,3'
        [void]$sp.Children.Add($x)
    }
    $b.Child = $sp; [void]$script:OvBody.Children.Add($b)
}
function Add-OvButton([string]$text, [scriptblock]$action, $param, [string]$style = 'Btn') {
    $b = New-Object Windows.Controls.Button
    $b.Content = $text; $b.Style = $script:Styles[$style]; $b.Margin = '8,0,0,0'; $b.Tag = @{ A = $action; P = $param }
    $b.Add_Click({ & $this.Tag.A $this.Tag.P })
    [void]$script:OvButtons.Children.Add($b)
}
#endregion

#region Cards and list
function Update-Card($it) {
    $pending = Test-Pending $it
    if ($it.Appx -and $it.State -eq 'on') { $it.Toggle.IsEnabled = $false }
    $txt = switch ($it.State) { 'on' { if ($it.Appx) { 'Удалено' } else { 'Применено' } } 'partial' { 'Применено частично' } default { if ($it.Appx) { 'Установлено' } else { 'Не применено' } } }
    $col = switch ($it.State) { 'on' { '#4ADE80' } 'partial' { '#E3B341' } default { '#6B7380' } }
    if ($pending) { $txt += "  →  будет: $(Get-Verb $it -Done)"; $col = '#7FA8FF' }
    $it.StatusTb.Text = $txt
    $it.StatusTb.Foreground = Brush $col
    $it.Card.BorderBrush = Brush $(if ($pending) { '#4F8CFF' } else { '#232831' })
}
function Update-Pending {
    $total = 0; $byCat = @{}
    foreach ($it in $script:Items) {
        Update-Card $it
        if (Test-Pending $it) { $total++; $byCat[$it.Cat] = 1 + [int]$byCat[$it.Cat] }
    }
    $byCat['Все'] = $total
    foreach ($c in $script:NavItems.Keys) {
        $nav = $script:NavItems[$c]; $n = [int]$byCat[$c]
        $nav.Badge.Visibility = $(if ($n) { 'Visible' } else { 'Collapsed' })
        $nav.BadgeT.Text = "$n"
    }
    $script:BtnApply.IsEnabled = $total -gt 0
    $script:BtnApply.Content = $(if ($total) { "Проверить и применить ($total)" } else { 'Проверить и применить' })
}
function Update-View {
    $q = $script:Search.Text.Trim()
    $all = $script:CurCat -eq 'Все'
    foreach ($h in $script:Headers.Values) { $h.Visibility = 'Collapsed' }
    $shown = 0; $on = 0
    foreach ($it in $script:Items) {
        $text = "$($it.Title) $($it.Short) $($it.Desc) $($it.Warn)"
        $vis = ($all -or $it.Cat -eq $script:CurCat) -and
               (-not $q -or $text.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -and
               (-not $script:ChipPending.IsChecked -or $it.State -ne 'on') -and
               (-not $script:ChipSafe.IsChecked -or $it.Impact -eq 'none') -and
               (-not $script:ChipReboot.IsChecked -or $it.Reboot)
        $it.Card.Visibility = $(if ($vis) { 'Visible' } else { 'Collapsed' })
        if ($vis) { $shown++; if ($it.State -eq 'on') { $on++ }; $script:Headers[$it.Cat].Visibility = 'Visible' }
    }
    $script:Heading.Text = $(if ($all) { 'Все настройки' } else { $script:CurCat })
    $script:SubHeading.Text = $(if ($shown) { "Показано: $shown  ·  уже применено: $on" } else { 'Ничего не найдено. Попробуйте снять фильтры.' })
}
function Reset-Toggles { foreach ($it in $script:Items) { if ($it.Toggle) { $it.Toggle.IsChecked = ($it.State -eq 'on') } } }
function Build-List {
    foreach ($cat in $Cats.Keys) {
        $inCat = @($script:Items | Where-Object { $_.Cat -eq $cat })
        if (-not $inCat.Count) { continue }
        $h = New-Xaml $HeaderXaml
        $h.FindName('L').Text = $cat.ToUpper()
        $all = $h.FindName('All'); $all.Style = $script:Styles.Link; $all.Tag = $cat
        $all.Add_Click({
            foreach ($x in $script:Items) { if ($x.Cat -eq $this.Tag -and $x.Card.Visibility -eq 'Visible' -and $x.Toggle.IsEnabled) { $x.Toggle.IsChecked = $true } }
            Update-Pending
        })
        if (-not $script:Headers.Count) { $h.Margin = '2,0,4,10' }
        $script:Headers[$cat] = $h; [void]$script:List.Children.Add($h)
        foreach ($it in $inCat) {
            $card = New-Xaml $CardXaml
            $card.FindName('T').Text = $it.Title
            $card.FindName('Sh').Text = $it.Short
            $card.FindName('D').Text = $it.Desc
            if ($it.Warn) { $w = $card.FindName('W'); $w.Text = "⚠  $($it.Warn)"; $w.Foreground = Brush $WarnColor[$it.Impact]; $w.Visibility = 'Visible' }
            $stripe = $card.FindName('Stripe'); $stripe.Background = Brush $ImpactColor[$it.Impact]; $stripe.ToolTip = $ImpactText[$it.Impact]
            if ($it.Reboot) { $card.FindName('Boot').Visibility = 'Visible' }
            $more = $card.FindName('More'); $more.Style = $script:Styles.Link; $more.Tag = $card.FindName('D')
            $more.Add_Click({
                $open = $this.Tag.Visibility -ne 'Visible'
                $this.Tag.Visibility = $(if ($open) { 'Visible' } else { 'Collapsed' })
                $this.Content = $(if ($open) { 'Свернуть ▴' } else { 'Подробнее ▾' })
            })
            $cb = $card.FindName('C'); $cb.Style = $script:Styles.Toggle; $cb.Tag = $it
            $cb.Add_Click({ Update-Card $this.Tag; Update-Pending })
            $it.Card = $card; $it.Toggle = $cb; $it.StatusTb = $card.FindName('S')
            [void]$script:List.Children.Add($card)
        }
    }
}
#endregion

#region Navigation
function Add-NavItem([string]$tag, [int]$glyph, [string]$label) {
    $g = New-Xaml $NavXaml
    $g.FindName('G').Text = [string][char]$glyph
    $g.FindName('L').Text = $label
    $li = New-Object Windows.Controls.ListBoxItem
    $li.Content = $g; $li.Tag = $tag
    $script:NavItems[$tag] = @{ Badge = $g.FindName('Badge'); BadgeT = $g.FindName('BadgeT') }
    [void]$script:Nav.Items.Add($li)
}
function Add-NavHeader([string]$text) {
    $li = New-Object Windows.Controls.ListBoxItem
    $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $text; $tb.FontSize = 11; $tb.FontWeight = 'SemiBold'; $tb.Foreground = Brush '#5F6774'; $tb.Margin = '0,8,0,0'
    $li.Content = $tb; $li.IsEnabled = $false; $li.Focusable = $false
    [void]$script:Nav.Items.Add($li)
}
function Select-Nav([string]$tag) {
    foreach ($li in $script:Nav.Items) { if ($li.Tag -eq $tag) { $script:Nav.SelectedItem = $li; $script:Nav.ScrollIntoView($li); return } }
}
function Show-View([string]$v) {
    $script:CurView = $v
    $views = @{ home = $script:HomeView; wizard = $script:WizardView; list = $script:ListView; history = $script:HistoryView; clean = $script:CleanView; startup = $script:StartupView; drivers = $script:DriversView; apps = $script:AppsView; fixes = $script:FixView }
    foreach ($k in $views.Keys) { $views[$k].Visibility = $(if ($k -eq $v) { 'Visible' } else { 'Collapsed' }) }
    $script:Footer.Visibility = $(if ($v -eq 'list') { 'Visible' } else { 'Collapsed' })
    switch ($v) {
        'home' { Update-Home } 'history' { Build-History } 'list' { Update-Pending; Update-View }
        'clean' { if (-not $script:CleanBuilt) { Build-Clean } }
        'startup' { if (-not $script:StartupBuilt) { Invoke-Busy 'Проверяю автозагрузку…' { Build-Startup } } }
        'drivers' { if (-not $script:DrvBuilt) { Build-Drivers } }
        'apps' { if (-not $script:AppsBuilt) { Build-Apps } }
        'fixes' { if (-not $script:FixBuilt) { Build-Fixes } }
    }
    Update-Busy
}
function Invoke-Busy([string]$text, [scriptblock]$work) {
    # вкладка уже видна; надпись по центру отрисовывается до долгой работы, чтобы окно не казалось зависшим
    $script:Loading.Text = $text; $script:Loading.Visibility = 'Visible'; Pump
    try { & $work } finally { $script:Loading.Visibility = 'Collapsed' }
}
#endregion

#region Home and questionnaire
function Update-Home {
    $cfg = @($script:Items | Where-Object { -not $_.Appx })
    $on = @($cfg | Where-Object { $_.State -eq 'on' }).Count
    $script:HomeCount.Text = "$on из $($cfg.Count)"
    $script:HomeBar.Maximum = [Math]::Max(1, $cfg.Count); $script:HomeBar.Value = $on
    $apps = @($script:Items | Where-Object { $_.Appx -and $_.State -ne 'on' }).Count
    $script:HomeApps.Text = "Встроенных приложений можно удалить: $apps"
    $snaps = @(Get-ChildItem -Path $script:DataDir -Filter 'snapshot-*.json' -ErrorAction SilentlyContinue).Count
    $script:HomeSnaps.Text = "Изменений в истории для отката: $snaps"
    $n = Get-PlanCount (Get-Answers)
    $script:HomePlan.Text = $(if ($n) { "Без вопросов уже можно улучшить настроек: $n. После ответов, скорее всего, больше." } else { 'Основное уже настроено. Ответы на вопросы помогут донастроить остальное.' })
    Update-RebootUi
}
function Update-WizCount {
    $n = Get-PlanCount $script:Answers
    $script:WizCount.Text = $(if ($n) { "С такими ответами изменится настроек: $n" } else { 'С такими ответами менять нечего: всё уже как надо' })
}
function Start-Wizard {
    $script:Answers = Get-Answers
    $script:WizList.Children.Clear(); $script:QRadios = @{}; $script:Touched = @{}
    $lastSection = $null
    foreach ($q in $script:Questions) {
        if (-not (Test-Question $q)) { continue }
        if ($q.Section -ne $lastSection) {
            $h = New-Object Windows.Controls.TextBlock
            $h.Text = $q.Section.ToUpper(); $h.FontSize = 11; $h.FontWeight = 'SemiBold'; $h.Foreground = Brush '#6B7380'
            $h.Margin = $(if ($lastSection) { '2,16,0,8' } else { '2,4,0,8' })
            [void]$script:WizList.Children.Add($h); $lastSection = $q.Section
        }
        $row = New-Xaml $QuestionXaml
        $row.FindName('Q').Text = $q.Text
        $row.FindName('H').Text = $q.Hint
        if ($q.Detect -and $script:Detected[$q.Detect]) { $row.FindName('A').Visibility = 'Visible' }
        $pairRb = @{}
        foreach ($pair in @(@('Y', 'yes'), @('N', 'no'))) {
            $rb = $row.FindName($pair[0])
            $rb.Style = $script:Styles.Seg; $rb.GroupName = "q_$($q.Id)"; $rb.Tag = @{ Q = $q.Id; V = $pair[1] }
            $rb.IsChecked = $script:Answers[$q.Id] -eq $pair[1]
            $rb.Add_Checked({
                $script:Answers[$this.Tag.Q] = $this.Tag.V; $script:Touched[$this.Tag.Q] = $true
                $sets = $script:QById[$this.Tag.Q].Sets
                if ($this.Tag.V -eq 'yes' -and $sets) {
                    foreach ($k in $sets.Keys) {
                        if ($script:QRadios.ContainsKey($k)) { $script:QRadios[$k][$sets[$k]].IsChecked = $true } else { $script:Answers[$k] = $sets[$k] }
                    }
                }
                Update-WizCount
            })
            $pairRb[$pair[1]] = $rb
        }
        $script:QRadios[$q.Id] = $pairRb
        [void]$script:WizList.Children.Add($row)
    }
    Update-WizCount
    $script:NavBusy = $true; $script:Nav.SelectedIndex = -1; $script:NavBusy = $false
    Show-View 'wizard'
}
function Complete-Wizard {
    $want = Get-PlanWant $script:Answers
    foreach ($it in $script:Items) {
        if (-not $it.Toggle.IsEnabled) { continue }
        if ($want.ContainsKey($it.Id)) { $it.Toggle.IsChecked = $want[$it.Id] }
        else { $it.Toggle.IsChecked = ($it.State -eq 'on') }
    }
    Update-Pending
    Show-Review
}
#endregion

#region Review, apply, result
function Show-Review {
    $changes = @($script:Items | Where-Object { Test-Pending $_ })
    if (-not $changes.Count) {
        Show-Overlay 'Нечего применять' 'Выбранные настройки уже совпадают с тем, что есть в системе.'
        Add-OvButton 'Понятно' { Hide-Overlay } $null 'Primary'
        return
    }
    $script:ReviewChanges = $changes
    $reboot = @($changes | Where-Object { $_.Reboot }).Count
    Show-Overlay 'Что изменится' "Изменений: $($changes.Count). Перед применением сохранится снимок для отката."
    foreach ($c in $Cats.Keys) {
        $inCat = @($changes | Where-Object { $_.Cat -eq $c })
        if (-not $inCat.Count) { continue }
        Add-OvText $c.ToUpper() '#6B7380' 11 '0,8,0,6' -Bold
        foreach ($it in $inCat) {
            $dot = $(if ($it.Toggle.IsChecked) { $ImpactColor[$it.Impact] } else { '#6B7380' })
            # для применяемых — что получится (Short с карточки), а не глагол, который легко понять наоборот
            $tail = $(if ($it.Toggle.IsChecked -and -not $it.Appx -and $it.Short) { $it.Short } else { Get-Verb $it })
            Add-OvLine $it.Title "  —  $tail" $dot
        }
    }
    $on = @($changes | Where-Object { $_.Toggle.IsChecked -and $_.Warn -and -not $_.Appx })
    $breaks = @($on | Where-Object { $_.Impact -eq 'breaks' } | ForEach-Object { $_.Warn })
    $minor = @($on | Where-Object { $_.Impact -eq 'minor' } | ForEach-Object { $_.Warn })
    if ($breaks.Count) { Add-OvBox 'Перестанет работать' $breaks '#2A1414' '#6B2A2A' '#FF9B94' }
    if ($minor.Count) { Add-OvBox 'Может измениться' $minor '#2A2311' '#6B5418' '#F2CC60' }
    $apps = @($changes | Where-Object { $_.Appx } | ForEach-Object { $_.Title })
    if ($apps.Count) { Add-OvBox 'Будут удалены приложения (вернуть можно из Microsoft Store)' $apps '#1F1830' '#4B3A78' '#C4A5FF' }
    if ($reboot) { Add-OvText "После применения понадобится перезагрузка: настроек с перезагрузкой $reboot." '#9DB4FF' 13 '0,10,0,0' }

    $script:OvRestore = New-Object Windows.Controls.CheckBox
    $script:OvRestore.Style = $script:Styles.Toggle; $script:OvRestore.IsChecked = $true; $script:OvRestore.VerticalAlignment = 'Center'
    $lbl = New-Object Windows.Controls.TextBlock; $lbl.Text = 'Точка восстановления'; $lbl.Foreground = Brush '#AEB4BF'; $lbl.FontSize = 12; $lbl.Margin = '8,0,0,0'; $lbl.VerticalAlignment = 'Center'
    [void]$script:OvLeft.Children.Add($script:OvRestore); [void]$script:OvLeft.Children.Add($lbl)
    if ($script:CurView -ne 'list') { Add-OvButton 'Настроить вручную' { $script:Overlay.Visibility = 'Collapsed'; Select-Nav 'Все' } $null }
    Add-OvButton 'Назад' { Hide-Overlay } $null
    Add-OvButton 'Применить' { Invoke-Changes $script:ReviewChanges ([bool]$script:OvRestore.IsChecked) } $null 'Primary'
}
function Invoke-Changes($changes, [bool]$restore) {
    Show-Overlay 'Применяю изменения' 'Не закрывайте окно'
    $script:OvProgress.Visibility = 'Visible'; Pump
    if ($restore) {
        Write-Log 'Создаю точку восстановления…'; Pump
        # Windows создаёт максимум одну точку за 24 часа; frequency=0 снимает лимит на время вызова
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $freqPrev = Get-RegRaw $srKey 'SystemRestorePointCreationFrequency'
        $freqSet = $freqPrev -and $freqPrev.Value -ne '0'
        if ($freqSet) { try { Set-Reg $srKey 'SystemRestorePointCreationFrequency' 0 'DWord' } catch { $freqSet = $false } }
        $w = $null; $err = $null
        try { Checkpoint-Computer -Description 'OknoTune' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable w -WarningAction SilentlyContinue }
        catch { $err = $_.Exception.Message }
        if ($w) { $err = "$w" }
        if ($freqSet) { try { Set-Reg $srKey 'SystemRestorePointCreationFrequency' $freqPrev.Value $freqPrev.Kind } catch {} }
        if ($err -and [Windows.MessageBox]::Show($script:Win, "Точка восстановления не создана:`n$err`n`nПродолжить без неё? Снимок для отката всё равно сохранится.", 'OknoTune', 'YesNo', 'Warning') -ne 'Yes') {
            Write-Log 'Отменено'; Hide-Overlay; return
        }
    }
    Update-TaskCache
    $snap = @($changes | ForEach-Object { Get-Snapshot $_ ([bool]$_.Toggle.IsChecked) })
    $file = Join-Path $script:DataDir ('snapshot-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))
    ConvertTo-Json -InputObject $snap -Depth 6 | Set-Content -Path $file -Encoding UTF8
    $ok = @(); $bad = @(); $reboot = $false; $i = 0
    foreach ($it in $changes) {
        $i++; $en = [bool]$it.Toggle.IsChecked
        $script:OvProgress.Value = 100 * $i / $changes.Count
        Write-Log ('{0}: {1}' -f $(if ($en) { 'Применяю' } else { 'Возвращаю' }), $it.Title); Pump
        try { Set-TweakState $it $en; $ok += "$($it.Title)  —  $(Get-Verb $it -Done)"; if ($it.Reboot) { $reboot = $true } }
        catch { $bad += "$($it.Title): $($_.Exception.Message)"; Write-Log "Ошибка «$($it.Title)»: $($_.Exception.Message)" }
    }
    Write-Log 'Проверяю результат…'; Pump
    Update-Caches; Update-States; Reset-Toggles; Update-Pending
    if ($reboot) { Set-RebootPending }
    Write-Log "Готово: изменено $($ok.Count), ошибок $($bad.Count)"
    Show-Result $(if ($bad.Count) { 'Готово, но есть ошибки' } else { 'Готово' }) $ok $bad $reboot
}
function Show-Result([string]$title, $ok, $bad, [bool]$reboot) {
    Show-Overlay $title "Изменено: $(@($ok).Count)  ·  ошибок: $(@($bad).Count)"
    foreach ($l in $ok) { Add-OvText "✓  $l" '#7EE2A0' 13 '0,0,0,5' }
    if (@($bad).Count) { Add-OvBox 'Не получилось' $bad '#2A1414' '#6B2A2A' '#FF9B94' }
    if ($reboot) {
        Add-OvBox 'Нужна перезагрузка' @('Часть изменений заработает только после перезагрузки компьютера.') '#2A2311' '#6B5418' '#F2CC60'
        Add-OvButton 'Позже' { Hide-Overlay } $null
        Add-OvButton 'Перезагрузить сейчас' { Invoke-Reboot } $null 'Primary'
    } else {
        Add-OvButton 'Готово' { Hide-Overlay } $null 'Primary'
    }
}
#endregion

#region History
function Get-SnapTitle($e) { if ($e.Title) { $e.Title } elseif ($script:ItemsById[$e.Id]) { $script:ItemsById[$e.Id].Title } else { $e.Id } }
function Read-Snap([string]$path) { $x = ConvertFrom-Json (Get-Content -Path $path -Raw -Encoding UTF8); $x }   # PS 5.1 returns the array as one object; emitting $x unrolls it
function Get-SnapDate($f) {
    $m = [regex]::Match($f.Name, '\d{8}-\d{6}')
    if ($m.Success) { [datetime]::ParseExact($m.Value, 'yyyyMMdd-HHmmss', $null) } else { $f.LastWriteTime }
}
function Get-HistFiles { @(Get-ChildItem -Path $script:DataDir -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(snapshot|restored)-' } | Sort-Object { Get-SnapDate $_ } -Descending) }
function Invoke-HistoryPrune([int]$Days = 180) {
    $cut = (Get-Date).AddDays(-$Days)
    $old = @(Get-HistFiles | Where-Object { (Get-SnapDate $_) -lt $cut })
    foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    if ($old.Count) { Write-Log "История: удалено снимков старше $Days дней: $($old.Count)" }
}
function Confirm-HistoryClear {
    $files = Get-HistFiles
    if (-not $files.Count) { return }
    $bytes = [long]0; foreach ($f in $files) { $bytes += $f.Length }
    Show-Overlay 'Очистить историю?' "Будет удалено файлов: $($files.Count) ($(Format-Size $bytes)). После этого откатить эти применения будет нельзя."
    Add-OvButton 'Отмена' { Hide-Overlay } $null
    Add-OvButton 'Удалить историю' { Invoke-HistoryClear } $null 'Warn'
}
function Invoke-HistoryClear {
    $files = Get-HistFiles
    Show-Overlay 'Чищу историю' 'Не закрывайте окно'
    $script:OvProgress.Visibility = 'Visible'; $i = 0
    foreach ($f in $files) {
        $i++; $script:OvProgress.Value = 100 * $i / $files.Count
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue; Pump
    }
    Write-Log "История: очищено снимков: $($files.Count)"
    $script:OvProgress.Visibility = 'Collapsed'
    Show-Overlay 'Готово' "Удалено файлов: $($files.Count)."
    Add-OvButton 'Готово' { Hide-Overlay; Build-History } $null 'Primary'
}
function Build-History {
    $script:HistList.Children.Clear()
    $files = Get-HistFiles
    $active = @($files | Where-Object { $_.Name -like 'snapshot-*' }).Count
    $script:HistSub.Text = $(if ($files.Count) { "Каждое применение сохраняется здесь. Откат возвращает значения, которые были до него. Можно откатить: $active." } else { 'Пока ничего не применялось.' })
    foreach ($f in $files) {
        $entries = @(Read-Snap $f.FullName)
        $card = New-Xaml $HistXaml
        $card.FindName('T').Text = (Get-SnapDate $f).ToString('d MMMM yyyy, HH:mm', $script:Ru)
        $restored = $f.Name -like 'restored-*'
        $card.FindName('S').Text = "Изменений: $($entries.Count)" + $(if ($restored) { '  ·  уже откачено' } else { '' })
        $titles = @($entries | ForEach-Object { Get-SnapTitle $_ })
        $card.FindName('L').Text = (($titles | Select-Object -First 8) -join ', ') + $(if ($titles.Count -gt 8) { " и ещё $($titles.Count - 8)" } else { '' })
        $b = $card.FindName('B'); $b.Style = $script:Styles.Btn; $b.Tag = $f.FullName
        if ($restored) { $b.IsEnabled = $false; $card.Opacity = 0.6 }
        $b.Add_Click({ Confirm-Undo $this.Tag })
        [void]$script:HistList.Children.Add($card)
    }
}
function Confirm-Undo([string]$path) {
    $f = Get-Item $path
    $entries = @(Read-Snap $path)
    Show-Overlay 'Откатить изменения?' "От $((Get-SnapDate $f).ToString('d MMMM, HH:mm', $script:Ru)). Эти настройки вернутся к значениям, которые были до применения:"
    foreach ($e in $entries) {
        $note = $(if ($e.Id -like 'app:*') {
            $pk = @($e.Appx | Where-Object { $_ })
            $(if ($pk.Count) { "  —  приложение не вернётся, ставьте из Store (пакет: $($pk[0]))" } else { '  —  приложение не вернётся, ставьте из Store' })
        } elseif ($e.Id -like 'startup:*') { '  —  автозагрузка вернётся, как было' }
        elseif ($e.Id -eq 'fix:dns') { '  —  вернётся прежний DNS' }
        elseif ($e.Id -like 'fix:*') { '  —  службы снова будут отключены' } else { '' })
        Add-OvLine (Get-SnapTitle $e) $note '#6B7380'
    }
    Add-OvButton 'Отмена' { Hide-Overlay } $null
    Add-OvButton 'Откатить' { param($p) Invoke-Undo $p } $path 'Primary'
}
function Invoke-Undo([string]$path) {
    Show-Overlay 'Откатываю' 'Не закрывайте окно'
    $script:OvProgress.Visibility = 'Visible'; Pump
    $entries = @(Read-Snap $path)
    $ok = @(); $bad = @(); $reboot = $false; $i = 0
    foreach ($e in $entries) {
        $i++; $script:OvProgress.Value = 100 * $i / $entries.Count
        $t = Get-SnapTitle $e
        Write-Log "Откат: $t"; Pump
        if ($e.Id -like 'app:*') { continue }
        try { Restore-Entry $e; $ok += "$t  —  как было"; if ($script:ItemsById[$e.Id].Reboot) { $reboot = $true } }
        catch { $bad += "${t}: $($_.Exception.Message)" }
    }
    $f = Get-Item $path
    Rename-Item -Path $path -NewName ($f.Name -replace '^snapshot-', 'restored-')
    Update-Caches; Update-States; Reset-Toggles; Update-Pending
    if ($reboot) { Set-RebootPending }
    Write-Log "Откат: восстановлено $($ok.Count), ошибок $($bad.Count)"
    Show-Result $(if ($bad.Count) { 'Откат выполнен с ошибками' } else { 'Откат выполнен' }) $ok $bad $reboot
}
#endregion

#region Profile: selected settings to/from a file
function Export-Profile {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'Профиль OknoTune (*.json)|*.json'; $dlg.FileName = 'oknotune-profile.json'
    if (-not $dlg.ShowDialog($script:Win)) { return }
    $sel = [ordered]@{}
    foreach ($it in $script:Items) { if ($it.Toggle) { $sel[$it.Id] = [bool]$it.Toggle.IsChecked } }
    ConvertTo-Json -InputObject ([ordered]@{ App = 'OknoTune'; Version = 1; Items = $sel }) -Depth 4 | Set-Content -Path $dlg.FileName -Encoding UTF8
    Write-Log "Профиль сохранён: $($dlg.FileName) (настроек: $($sel.Count))"
}
function Import-Profile {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Профиль OknoTune (*.json)|*.json'
    if (-not $dlg.ShowDialog($script:Win)) { return }
    try { $p = ConvertFrom-Json (Get-Content -Path $dlg.FileName -Raw -Encoding UTF8) } catch { $p = $null }
    if (-not $p -or $p.App -ne 'OknoTune' -or -not $p.Items) { [void][Windows.MessageBox]::Show($script:Win, 'Это не файл профиля OknoTune.', 'OknoTune'); return }
    $n = 0
    foreach ($pr in $p.Items.PSObject.Properties) {
        $it = $script:ItemsById[$pr.Name]
        if ($it -and $it.Toggle -and $it.Toggle.IsEnabled) { $it.Toggle.IsChecked = [bool]$pr.Value; $n++ }
    }
    Update-Pending; Update-View
    Write-Log "Профиль загружен: отмечено настроек $n. Проверьте и нажмите «Проверить и применить»"
}
#endregion

#region Cleanup UI
$CleanXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Margin="0,0,0,8" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="5"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Border Name="Stripe" CornerRadius="9,0,0,9"/>
  <StackPanel Grid.Column="1" Margin="16,12,0,12">
   <TextBlock Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB"/>
   <TextBlock Name="D" TextWrapping="Wrap" Foreground="#8B93A1" FontSize="13" Margin="0,3,0,0"/>
   <TextBlock Name="W" TextWrapping="Wrap" FontSize="13" Margin="0,3,0,0" Visibility="Collapsed"/>
  </StackPanel>
  <TextBlock Name="Sz" Grid.Column="2" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB" VerticalAlignment="Center" Margin="16,0,8,0" MinWidth="80" TextAlignment="Right"/>
  <CheckBox Name="C" Grid.Column="3" VerticalAlignment="Center" Margin="8,0,18,0"/>
 </Grid>
</Border>
'@
function Update-CleanTotal {
    $sum = [long]0
    foreach ($c in $script:CleanItems) { if ($c.Toggle.IsChecked -and $c.Bytes) { $sum += $c.Bytes } }
    $script:CleanTotal.Text = Format-Size $sum
    $script:CleanDisk.Text = "Свободно на диске $($env:SystemDrive) $(Format-Size (Get-FreeBytes))"
    $script:BtnClean.IsEnabled = @($script:CleanItems | Where-Object { $_.Toggle.IsChecked }).Count -gt 0
}
function Set-CleanSize($c, $bytes) {
    $c.Bytes = $bytes
    $c.SizeTb.Text = Format-Size $bytes
    $c.SizeTb.Foreground = Brush $(if ($bytes -gt 100MB) { '#E6E8EB' } else { '#8B93A1' })
}
function Update-CleanSizes {
    # обход папок идёт в фоне, размеры появляются по мере подсчёта
    if ($script:BgJobs['clean']) { return }
    $script:BtnRescan.IsEnabled = $false; $script:BtnClean.IsEnabled = $false
    foreach ($c in $script:CleanItems) { $c.SizeTb.Text = '…'; $c.Bytes = $null }
    # пункты со своей функцией размера (корзина через COM, WinSxS) быстрые — считаем здесь
    foreach ($c in @($script:CleanItems | Where-Object { $_.Size })) { Set-CleanSize $c (Get-CleanSize $c) }
    $jobs = @($script:CleanItems | Where-Object { -not $_.Size } | ForEach-Object { @{ Id = $_.Id; Title = $_.Title; MinAge = $_.MinAge; Paths = $_.Paths.ToString() } })
    $script:CleanJobCount = $jobs.Count
    $script:CleanTotal.Text = '…'; $script:CleanDisk.Text = "Свободно на диске $($env:SystemDrive) $(Format-Size (Get-FreeBytes))"
    $script:CleanStatus.Text = "Считаю размер… 0 из $($jobs.Count)"
    $script:CleanBar.Value = 0; $script:CleanBar.Visibility = 'Visible'
    Start-Bg 'clean' @('Test-SafePath', 'Get-FilesSafe', 'Get-CleanFiles', 'Get-CleanSize') @{ CleanRoots = $script:CleanRoots; Lad = $Lad; CleanJobs = $jobs } {
        param($sync)
        $i = 0
        foreach ($c in $CleanJobs) {
            $sync.Text = $c.Title
            $c.Paths = [scriptblock]::Create($c.Paths)
            $sync.Partial[$c.Id] = Get-CleanSize $c
            $i++; $sync.Value = 100 * $i / $CleanJobs.Count
        }
    } {
        param($s)
        foreach ($id in @($s.Partial.Keys)) {
            $c = $script:CleanItems | Where-Object { $_.Id -eq $id }
            if ($c -and $null -eq $c.Bytes) { Set-CleanSize $c $s.Partial[$id] }
        }
        $script:CleanBar.Value = $s.Value
        $script:CleanStatus.Text = "Считаю размер… $($s.Partial.Count) из $($script:CleanJobCount)$(if ($s.Text) { ": $($s.Text)" })"
    } {
        param($s)
        $script:CleanBar.Visibility = 'Collapsed'; $script:BtnRescan.IsEnabled = $true
        foreach ($c in $script:CleanItems) { if ($null -eq $c.Bytes -and $s.Partial.ContainsKey($c.Id)) { Set-CleanSize $c $s.Partial[$c.Id] } elseif ($null -eq $c.Bytes -and -not $c.Size) { $c.SizeTb.Text = '—' } }
        $script:CleanStatus.Text = $(if ($s.Error) { "Не всё удалось посчитать: $($s.Error)" } else { 'Отметьте, что удалить, и нажмите «Очистить».' })
        Update-CleanTotal
    }
}
function Build-Clean {
    $script:CleanList.Children.Clear()
    foreach ($c in $script:CleanItems) {
        $card = New-Xaml $CleanXaml
        $card.FindName('T').Text = $c.Title
        $card.FindName('D').Text = $c.Desc
        if ($c.Warn) { $w = $card.FindName('W'); $w.Text = "⚠  $($c.Warn)"; $w.Foreground = Brush $WarnColor[$c.Impact]; $w.Visibility = 'Visible' }
        $card.FindName('Stripe').Background = Brush $ImpactColor[$c.Impact]
        $cb = $card.FindName('C'); $cb.Style = $script:Styles.Toggle; $cb.IsChecked = $c.Default
        $cb.Add_Click({ Update-CleanTotal })
        $c.Toggle = $cb; $c.SizeTb = $card.FindName('Sz')
        [void]$script:CleanList.Children.Add($card)
    }
    $script:CleanBuilt = $true
    Update-CleanSizes
}
function Confirm-Clean {
    $sel = @($script:CleanItems | Where-Object { $_.Toggle.IsChecked })
    if (-not $sel.Count) { return }
    $sum = [long]0; foreach ($c in $sel) { if ($c.Bytes) { $sum += $c.Bytes } }
    Show-Overlay 'Очистить выбранное?' "Будет удалено примерно $(Format-Size $sum). Удалённые файлы не восстановить."
    foreach ($c in $sel) { Add-OvLine $c.Title "  —  $(Format-Size $c.Bytes)" $ImpactColor[$c.Impact] }
    $warns = @($sel | Where-Object { $_.Warn } | ForEach-Object { $_.Warn })
    if ($warns.Count) { Add-OvBox 'Обратите внимание' $warns '#2A2311' '#6B5418' '#F2CC60' }
    Add-OvButton 'Отмена' { Hide-Overlay } $null
    Add-OvButton 'Очистить' { Invoke-CleanRun } $null 'Primary'
}
function Invoke-CleanRun {
    $sel = @($script:CleanItems | Where-Object { $_.Toggle.IsChecked })
    Show-Overlay 'Очищаю' 'Не закрывайте окно'
    $script:OvProgress.Visibility = 'Visible'; Pump
    $startFree = Get-FreeBytes; $ok = @(); $i = 0
    foreach ($c in $sel) {
        $i++; $script:OvProgress.Value = 100 * $i / $sel.Count
        Write-Log "Очистка: $($c.Title)"; $script:OvSub.Text = "Очистка: $($c.Title)"; Pump
        $before = Get-FreeBytes
        try { Invoke-Clean $c } catch { Write-Log "Ошибка очистки «$($c.Title)»: $($_.Exception.Message)" }
        $freed = [Math]::Max(0, (Get-FreeBytes) - $before)
        $ok += "$($c.Title)  —  $(Format-Size $freed)"
    }
    $total = [Math]::Max(0, (Get-FreeBytes) - $startFree)
    Write-Log "Очистка завершена, освобождено $(Format-Size $total)"
    Show-Overlay 'Готово' "Освобождено: $(Format-Size $total). Занятые программами файлы пропущены."
    foreach ($l in $ok) { Add-OvText "✓  $l" '#7EE2A0' 13 '0,0,0,5' }
    Add-OvButton 'Готово' { $script:Overlay.Visibility = 'Collapsed'; Update-CleanSizes } $null 'Primary'
}
#endregion

#region Startup UI
$SuXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Margin="0,0,0,10" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="5"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Border Name="Stripe" CornerRadius="9,0,0,9"/>
  <StackPanel Grid.Column="1" Margin="16,13,8,13">
   <TextBlock Name="K" FontSize="11" Foreground="#6B7380"/>
   <TextBlock Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB" TextTrimming="CharacterEllipsis" Margin="0,4,0,0"/>
   <TextBlock Name="Cm" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis" Foreground="#8B93A1" FontSize="12" Margin="0,4,0,0"/>
  </StackPanel>
  <StackPanel Grid.Column="2" VerticalAlignment="Center" Margin="20,0,18,0">
   <TextBlock Name="S" FontSize="12" HorizontalAlignment="Right" Margin="0,0,0,7" TextTrimming="CharacterEllipsis" MaxWidth="260"/>
   <CheckBox Name="C" HorizontalAlignment="Right"/>
  </StackPanel>
 </Grid>
</Border>
'@
function Update-StartupCard($it) {
    if ($it.Toggle -and ($it.On -ne [bool]$it.Toggle.IsChecked)) {
        $it.StatusTb.Text = $(if ($it.Toggle.IsChecked) { 'будет: вернуть' } else { 'будет: убрать' })
        $it.StatusTb.Foreground = Brush '#7FA8FF'
        $it.Card.BorderBrush = Brush '#4F8CFF'
    } else {
        $it.StatusTb.Text = $(if ($it.OknoTuneOff) { 'отключено в OknoTune' } elseif ($it.TmOff) { 'отключено в Диспетчере задач' } else { '' })
        $it.StatusTb.Foreground = Brush $(if ($it.TmOff) { '#E3B341' } else { '#6B7380' })
        $it.Card.BorderBrush = Brush '#232831'
    }
}
function Update-StartupPending {
    $n = 0
    foreach ($it in $script:StartupItems) { if ($it.Toggle -and ($it.On -ne [bool]$it.Toggle.IsChecked)) { $n++ } }
    $script:BtnSuApply.IsEnabled = $n -gt 0
    $script:BtnSuApply.Content = $(if ($n) { "Применить ($n)" } else { 'Применить' })
    $on = @($script:StartupItems | Where-Object { $_.On }).Count
    $script:SuSummary.Text = "Записей: $($script:StartupItems.Count)  ·  запускается при входе: $on. Зелёная полоска — активно, жёлтая — отключено в Диспетчере задач, серая — отключено здесь."
}
function Build-Startup {
    $script:SuList.Children.Clear()
    $script:SuStatus.Text = 'Проверяю автозагрузку…'; Pump
    $script:StartupItems = @(Get-StartupItems | Sort-Object Kind, Name)
    foreach ($it in $script:StartupItems) {
        $card = New-Xaml $SuXaml
        $card.FindName('K').Text = $it.Label
        $card.FindName('T').Text = $it.Name
        $cm = $card.FindName('Cm'); $cm.Text = $it.Command; $cm.ToolTip = $it.Command
        $card.FindName('Stripe').Background = Brush $(if ($it.OknoTuneOff) { '#6B7380' } elseif ($it.TmOff) { '#D29922' } else { '#3FB950' })
        $cb = $card.FindName('C'); $cb.Style = $script:Styles.Toggle; $cb.IsChecked = $it.On; $cb.Tag = $it
        $cb.Add_Click({ Update-StartupCard $this.Tag; Update-StartupPending })
        $it | Add-Member -MemberType NoteProperty -Name Card -Value $card -Force
        $it | Add-Member -MemberType NoteProperty -Name Toggle -Value $cb -Force
        $it | Add-Member -MemberType NoteProperty -Name StatusTb -Value $card.FindName('S') -Force
        [void]$script:SuList.Children.Add($card)
    }
    $script:StartupBuilt = $true
    if (-not $script:StartupItems.Count) { $script:SuStatus.Text = 'В автозагрузке пусто.' }
    else { $script:SuStatus.Text = 'Переключатель включён — программа запускается при входе в Windows.' }
    Update-StartupPending
}
function Confirm-Startup {
    $changes = @($script:StartupItems | Where-Object { $_.Toggle -and ($_.On -ne [bool]$_.Toggle.IsChecked) })
    if (-not $changes.Count) { return }
    Show-Overlay 'Что изменится в автозагрузке' "Изменений: $($changes.Count). Перед применением сохранится снимок для отката."
    foreach ($it in $changes) {
        Add-OvLine $it.Name $(if ($it.Toggle.IsChecked) { '  —  вернуть в автозагрузку' } else { '  —  убрать из автозагрузки' }) $(if ($it.Toggle.IsChecked) { '#3FB950' } else { '#6B7380' })
    }
    Add-OvBox 'Обратите внимание' @('Некоторые программы прописывают себя в автозагрузку заново при очередном запуске.',
        'Отключённое можно вернуть здесь в любой момент — или откатить всё сразу через «Историю».') '#2A2311' '#6B5418' '#F2CC60'
    Add-OvButton 'Назад' { Hide-Overlay } $null
    Add-OvButton 'Применить' { Invoke-StartupApply } $null 'Primary'
}
function Invoke-StartupApply {
    $changes = @($script:StartupItems | Where-Object { $_.Toggle -and ($_.On -ne [bool]$_.Toggle.IsChecked) })
    Show-Overlay 'Применяю изменения' 'Не закрывайте окно'
    $script:OvProgress.Visibility = 'Visible'; Pump
    $snap = @($changes | ForEach-Object { Get-StartupSnap $_ ([bool]$_.Toggle.IsChecked) })
    $file = Join-Path $script:DataDir ('snapshot-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))
    ConvertTo-Json -InputObject $snap -Depth 6 | Set-Content -Path $file -Encoding UTF8
    $ok = @(); $bad = @(); $i = 0
    foreach ($it in $changes) {
        $i++; $script:OvProgress.Value = 100 * $i / $changes.Count
        Write-Log ('Автозагрузка: {0} — {1}' -f $it.Name, $(if ($it.Toggle.IsChecked) { 'включаю' } else { 'отключаю' })); Pump
        try {
            Set-StartupState $it ([bool]$it.Toggle.IsChecked)
            $ok += "$($it.Name)  —  $(if ($it.Toggle.IsChecked) { 'в автозагрузке' } else { 'убрано из автозагрузки' })"
        } catch { $bad += "$($it.Name): $($_.Exception.Message)"; Write-Log "Ошибка автозагрузки «$($it.Name)»: $($_.Exception.Message)" }
    }
    Write-Log "Автозагрузка: изменено $($ok.Count), ошибок $($bad.Count)"
    Build-Startup
    Show-Result $(if ($bad.Count) { 'Готово, но есть ошибки' } else { 'Готово' }) $ok $bad $false
}
#endregion

#region Drivers UI
$DrvXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Margin="0,0,0,10" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="5"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Border Name="Stripe" CornerRadius="9,0,0,9"/>
  <StackPanel Grid.Column="1" Margin="16,13,0,13">
   <TextBlock Name="K" FontSize="11" FontWeight="SemiBold" Foreground="#6B7380"/>
   <TextBlock Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB" TextWrapping="Wrap" Margin="0,4,0,0"/>
   <TextBlock Name="D" FontSize="13" Foreground="#8B93A1" TextWrapping="Wrap" Margin="0,4,0,0"/>
   <TextBlock Name="A" FontSize="12" Margin="0,6,0,0"/>
  </StackPanel>
  <StackPanel Name="Btns" Grid.Column="2" VerticalAlignment="Center" Margin="20,0,18,0"/>
 </Grid>
</Border>
'@
function Open-Url([string]$url) {
    # Ask the desktop shell (running as the normal user) to open the link, so the browser does not start elevated.
    # explorer.exe <url> is not used: it opens Documents for URLs with a query string.
    try {
        $hwnd = 0
        $desk = (New-Object -ComObject Shell.Application).Windows().FindWindowSW(0, $null, 8, [ref]$hwnd, 1)   # SWC_DESKTOP, SWFO_NEEDDISPATCH
        $desk.Document.Application.ShellExecute($url)
    } catch { Start-Process $url }
}
function Build-Drivers {
    # скан в фоне; карточки рисует Show-Drivers, когда данные готовы
    if ($script:BgJobs['drivers']) { return }
    $script:DrvList.Children.Clear(); $script:BtnDrvRescan.IsEnabled = $false
    $script:DrvStatus.Text = 'Проверяю устройства…'
    Set-Busy 'drivers' 'Проверяю устройства и драйверы…' 0
    Start-Bg 'drivers' @('Get-DriverInfo', 'Get-HwId', 'Get-FindButtons', 'Get-SearchUrl') @{ VendorSites = $VendorSites; GpuSites = $GpuSites } {
        param($sync) Get-DriverInfo $sync
    } {
        param($s) if ($s.Text) { Set-Busy 'drivers' "Проверяю: $($s.Text)" $s.Value }
    } {
        param($s)
        Clear-Busy 'drivers'; $script:BtnDrvRescan.IsEnabled = $true
        if ($s.Error) { $script:DrvStatus.Text = "Не удалось проверить устройства: $($s.Error)"; Write-Log "Драйверы: $($s.Error)"; return }
        Show-Drivers @($s.Result)
    }
}
function Show-Drivers($cards) {
    $script:DrvList.Children.Clear()
    foreach ($d in $cards) {
        $card = New-Xaml $DrvXaml
        $card.FindName('K').Text = $d.Kind.ToUpper()
        $card.FindName('T').Text = $d.Title
        $card.FindName('D').Text = $d.Details
        $m = Get-AgeMonths $d.Date
        $color = '#3FB950'; $ageText = ''
        if ($d.Bad) { $color = '#F85149' }
        elseif ($null -ne $m) {
            $fresh = [int]$d.Fresh
            if ($m -gt $fresh * 3) { $color = '#F85149'; $hint = 'стоит обновить' } elseif ($m -gt $fresh) { $color = '#D29922'; $hint = 'есть смысл проверить обновление' } else { $hint = 'свежий' }
            $ageText = "Драйвер от $($d.Date.ToString('dd.MM.yyyy')) · $(Format-Age $d.Date) · $hint"
        }
        $card.FindName('Stripe').Background = Brush $color
        $a = $card.FindName('A'); $a.Text = $ageText; $a.Foreground = Brush $(if ($color -eq '#3FB950') { '#7EE2A0' } elseif ($color -eq '#D29922') { '#E3B341' } else { '#FF7B72' })
        $btns = $card.FindName('Btns'); $first = $true
        foreach ($b in $d.Buttons) {
            $btn = New-Object Windows.Controls.Button
            $btn.Content = $b[0]; $btn.Tag = $b[1]; $btn.Margin = '0,0,0,6'; $btn.HorizontalAlignment = 'Stretch'; $btn.MinWidth = 220; $btn.ToolTip = $b[1]
            $btn.Style = $script:Styles[$(if ($first) { 'Primary' } else { 'Btn' })]; $first = $false
            $btn.Add_Click({ Open-Url $this.Tag })
            [void]$btns.Children.Add($btn)
        }
        [void]$script:DrvList.Children.Add($card)
    }
    $script:DrvBuilt = $true
    $script:DrvStatus.Text = 'Зелёный — свежий, жёлтый — проверить, красный — старый или сломан'
}
#endregion

#region Recommended apps
# «Установить» — winget только из каталога winget (-s winget): он скачивает обычный установщик с сайта разработчика,
# версии из Microsoft Store не используются. «Сайт» — официальный сайт в браузере.
# Adv = $true — для опытных (жёлтая точка). Kind — своя подпись (например, ограничение лицензии). WinGet — пакет, если есть.
$AppCatalog = [ordered]@{
    'Интернет' = @(
        @{ Name = 'Google Chrome'; Url = 'https://www.google.com/chrome/'; WinGet = 'Google.Chrome'
           Desc = 'Популярный браузер. Быстрый, синхронизирует закладки и пароли между устройствами.' }
        @{ Name = 'qBittorrent'; Url = 'https://www.qbittorrent.org/'; WinGet = 'qBittorrent.qBittorrent'
           Desc = 'Торрент-клиент без рекламы и лишнего в установщике. С открытым кодом.' }
    )
    'Игры и общение' = @(
        @{ Name = 'Steam'; Url = 'https://store.steampowered.com/about/'; WinGet = 'Valve.Steam'
           Desc = 'Магазин и библиотека игр. Обновляет игры сам, хранит сохранения в облаке.' }
        @{ Name = 'Discord'; Url = 'https://discord.com/download'; WinGet = 'Discord.Discord'
           Desc = 'Голосовой чат и серверы для игр и сообществ. Демонстрация экрана.' }
        @{ Name = 'Telegram'; Url = 'https://desktop.telegram.org/'; WinGet = 'Telegram.TelegramDesktop'
           Desc = 'Мессенджер для компьютера. Чаты, каналы и файлы синхронизируются с телефоном.' }
    )
    'Файлы' = @(
        @{ Name = '7-Zip'; Url = 'https://www.7-zip.org/'; WinGet = '7zip.7zip'
           Desc = 'Архиватор: ZIP, RAR, 7z и другие. Быстрее встроенного в Windows.' }
        @{ Name = 'Notepad++'; Url = 'https://notepad-plus-plus.org/downloads/'; WinGet = 'Notepad++.Notepad++'
           Desc = 'Удобный блокнот: подсветка кода, большие файлы, поиск по нескольким файлам.' }
        @{ Name = 'Everything'; Url = 'https://www.voidtools.com/ru-ru/'; WinGet = 'voidtools.Everything'
           Desc = 'Мгновенный поиск файлов по имени на всех дисках.' }
        @{ Name = 'SpaceSniffer'; Url = 'http://www.uderzo.it/main_products/space_sniffer/'; WinGet = 'UderzoSoftware.SpaceSniffer'
           Desc = 'Показывает блоками, чем занят диск. Сразу видно, что съело место.' }
    )
    'Обслуживание системы' = @(
        @{ Name = 'HiBit Uninstaller'; Url = 'https://www.hibitsoft.ir/Uninstaller.html'; WinGet = 'HiBitSoftware.HiBitUninstaller'
           Desc = 'Удаляет программы вместе с «хвостами» в папках и реестре.' }
        @{ Name = 'Easy Service Optimizer'; Url = 'https://www.sordum.org/8637/easy-service-optimizer-v1-2/'; Adv = $true
           Desc = 'Отключает лишние службы по профилям, есть откат. Не трогайте службы, в которых не уверены.' }
        @{ Name = 'DriverStore Explorer'; Url = 'https://github.com/lostindark/driverstoreExplorer'; WinGet = 'lostindark.DriverStoreExplorer'; Adv = $true
           Desc = 'Удаляет старые версии драйверов из хранилища Windows. Текущие оставьте.' }
        @{ Name = 'Device Cleanup Tool'; Url = 'https://www.usbdev.ru/files/devicecleanup/'
           Desc = 'Удаляет записи о давно отключённых устройствах: флешках, телефонах, принтерах.' }
    )
    'Проверка на вирусы' = @(
        @{ Name = 'Kaspersky VRT'; Url = 'https://www.kaspersky.ru/downloads/free-virus-removal-tool'
           Desc = 'Разовая проверка на вирусы без установки. Не конфликтует с антивирусом.' }
        @{ Name = 'Dr.Web CureIt!'; Url = 'https://free.drweb.ru/cureit/'; Kind = 'БЕСПЛАТНО ДЛЯ ДОМА'
           Desc = 'Разовый сканер, хорош как второе мнение. Для организаций — платная лицензия.' }
        @{ Name = 'AdwCleaner'; Url = 'https://www.malwarebytes.com/ru/adwcleaner'; WinGet = 'Malwarebytes.AdwCleaner'
           Desc = 'Убирает рекламное ПО, навязанные панели и подменённую стартовую страницу.' }
    )
}
$AppTileXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Margin="0,0,10,10" Padding="14,12" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <DockPanel>
  <StackPanel Name="Btns" DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,10,0,0"/>
  <StackPanel>
   <DockPanel>
    <Ellipse Name="Dot" Width="8" Height="8" Margin="0,0,8,0" VerticalAlignment="Center"/>
    <TextBlock Name="T" FontSize="14" FontWeight="SemiBold" Foreground="#E6E8EB" TextTrimming="CharacterEllipsis"/>
   </DockPanel>
   <TextBlock Name="K" FontSize="10" FontWeight="SemiBold" Foreground="#6B7380" Margin="16,3,0,0"/>
   <TextBlock Name="D" FontSize="12" Foreground="#8B93A1" TextWrapping="Wrap" Margin="0,6,0,0"/>
  </StackPanel>
 </DockPanel>
</Border>
'@
function Install-App([string]$id) {
    # отдельное окно консоли: видно ход установки, OknoTune не зависает.
    # -s winget: только каталог winget, без версий из Store. Без --accept-*-agreements: условия принимает пользователь.
    Write-Log "Устанавливаю через winget: $id"
    Start-Process cmd.exe -ArgumentList "/c title OknoTune: установка $id & winget install --id $id -e -s winget & echo. & pause"
}
function New-AppButton([string]$text, $tag, [string]$style, [scriptblock]$click) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $text; $b.Tag = $tag; $b.Style = $script:Styles[$style]; $b.Margin = '0,0,6,0'; $b.Padding = '12,5'; $b.FontSize = 12
    $b.Add_Click($click)
    $b
}
function Build-Apps {
    $script:AppsList.Children.Clear()
    $winget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
    foreach ($cat in $AppCatalog.Keys) {
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = $cat.ToUpper(); $h.FontSize = 11; $h.FontWeight = 'SemiBold'; $h.Foreground = Brush '#6B7380'; $h.Margin = '2,12,0,8'
        [void]$script:AppsList.Children.Add($h)
        # плитки по три в ряд: на экран влезает почти весь список
        $grid = New-Object Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 3; $grid.Margin = '0,0,-10,0'
        foreach ($a in $AppCatalog[$cat]) {
            $tile = New-Xaml $AppTileXaml
            $tile.FindName('T').Text = $a.Name
            $tile.FindName('D').Text = $a.Desc
            $tile.FindName('K').Text = $(if ($a.Kind) { $a.Kind } elseif ($a.Adv) { 'ДЛЯ ОПЫТНЫХ' } else { ([Uri]$a.Url).Host -replace '^www\.', '' })
            $tile.FindName('Dot').Fill = Brush $(if ($a.Adv -or $a.Kind) { '#D29922' } else { '#3FB950' })
            $btns = $tile.FindName('Btns')
            $canInstall = $winget -and $a.WinGet
            if ($canInstall) { [void]$btns.Children.Add((New-AppButton 'Установить' $a.WinGet 'Primary' { Install-App $this.Tag })) }
            $site = New-AppButton 'Сайт' $a.Url $(if ($canInstall) { 'Btn' } else { 'Primary' }) { Open-Url $this.Tag }
            $site.ToolTip = $a.Url
            [void]$btns.Children.Add($site)
            [void]$grid.Children.Add($tile)
        }
        [void]$script:AppsList.Children.Add($grid)
    }
    $script:AppsBuilt = $true
}
#endregion

#region Fixes: common problems, repair, DNS, classic windows
# Svc: службы, которые нужны для работы. Меняем только отключённые (Disabled), остальные не трогаем.
# Типы запуска до исправления сохраняются в «Историю», их можно откатить.
$FixCatalog = @(
    @{ Id = 'vpn'; Title = 'Не подключается VPN'
       Desc = 'Включает службы, через которые Windows подключает VPN: встроенный (L2TP, IKEv2, SSTP) и большинство программ-клиентов. Сбрасывает DNS-кэш.'
       Svc = (SvcV BFE Automatic), (SvcV RasMan Manual), (SvcV RasAuto Manual), (SvcV IKEEXT Manual), (SvcV PolicyAgent Manual), (SvcV SstpSvc Manual),
             (SvcV Netman Manual), (SvcV iphlpsvc Automatic), (SvcV Dhcp Automatic), (SvcV Dnscache Automatic), (SvcV NlaSvc Automatic)
       Start = 'BFE', 'RasMan', 'IKEEXT', 'PolicyAgent', 'iphlpsvc'
       Run = { ipconfig /flushdns | Out-Null } }
    @{ Id = 'net'; Title = 'Пропал интернет'
       Desc = 'Включает сетевые службы, сбрасывает DNS-кэш, прокси и сетевые настройки Windows (winsock, TCP/IP). Если IP-адрес у вас прописан вручную, его придётся ввести заново. Нужна перезагрузка.'
       Svc = (SvcV Dhcp Automatic), (SvcV Dnscache Automatic), (SvcV NlaSvc Automatic), (SvcV netprofm Manual), (SvcV nsi Automatic), (SvcV Wcmsvc Automatic), (SvcV WlanSvc Automatic)
       Start = 'Dhcp', 'Dnscache', 'NlaSvc', 'WlanSvc'
       Run = { ipconfig /flushdns | Out-Null; netsh winhttp reset proxy | Out-Null; netsh winsock reset | Out-Null; netsh int ip reset | Out-Null }
       Reboot = $true }
    @{ Id = 'wu'; Title = 'Не устанавливаются обновления Windows'
       Desc = 'Включает службы обновления и очищает их кэш: папки SoftwareDistribution и catroot2 переименовываются, Windows создаст их заново. Список установленных обновлений в «Параметрах» может опустеть, сами обновления останутся.'
       Svc = (SvcV wuauserv Manual), (SvcV BITS Manual), (SvcV CryptSvc Automatic), (SvcV UsoSvc Automatic), (SvcV msiserver Manual)
       Start = 'CryptSvc', 'BITS', 'wuauserv'
       Run = {
           Stop-Service wuauserv, BITS, CryptSvc -Force -ErrorAction SilentlyContinue
           $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
           foreach ($d in "$env:windir\SoftwareDistribution", "$env:windir\System32\catroot2") {
               if (Test-Path -LiteralPath $d) { Rename-Item -LiteralPath $d -NewName "$(Split-Path $d -Leaf).old-$stamp" -ErrorAction Stop }
           }
       } }
    @{ Id = 'store'; Title = 'Не работает Microsoft Store'
       Desc = 'Включает службы, нужные магазину, и сбрасывает его кэш (wsreset). После сброса магазин откроется сам.'
       Svc = (SvcV InstallService Manual), (SvcV wuauserv Manual), (SvcV BITS Manual)
       Run = { Start-Process wsreset.exe } }
    @{ Id = 'print'; Title = 'Не печатает принтер'
       Desc = 'Включает службу печати, очищает зависшую очередь печати и перезапускает службу.'
       Svc = (SvcV Spooler Automatic), (SvcV PrintNotify Manual)
       Run = {
           Stop-Service Spooler -Force -ErrorAction SilentlyContinue
           Remove-Item "$env:windir\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
           Start-Service Spooler -ErrorAction Stop
       } }
    @{ Id = 'audio'; Title = 'Пропал звук'
       Desc = 'Включает и перезапускает службы звука Windows. Помогает, когда значок звука перечёркнут, а с колонками всё в порядке.'
       Svc = (SvcV AudioEndpointBuilder Automatic), (SvcV Audiosrv Automatic)
       Run = { Restart-Service AudioEndpointBuilder -Force -ErrorAction Stop; Start-Service Audiosrv -ErrorAction Stop } }
    @{ Id = 'bt'; Title = 'Не работает Bluetooth'
       Desc = 'Включает службы Bluetooth, в том числе для беспроводных наушников (гарнитура и управление звуком).'
       Svc = (SvcV bthserv Manual), (SvcV BTAGService Manual), (SvcV BthAvctpSvc Manual)
       Start = 'bthserv' }
    @{ Id = 'camera'; Title = 'Не работает камера'
       Desc = 'Включает службы, через которые программы получают картинку с веб-камеры (Zoom, Teams, Telegram, браузер).'
       Svc = (SvcV FrameServer Manual), (SvcV FrameServerMonitor Manual) }
    @{ Id = 'token'; Title = 'Не видит токен ЭЦП или смарт-карту'
       Desc = 'Включает службы смарт-карт. Нужны для Рутокена, eToken, JaCarta и входа по смарт-карте.'
       Svc = (SvcV SCardSvr Manual), (SvcV ScDeviceEnum Manual), (SvcV SCPolicySvc Manual)
       Start = 'SCardSvr' }
    @{ Id = 'search'; Title = 'Не работает поиск в Пуске'
       Desc = 'Включает и запускает службу поиска Windows. Если поиск был выключен долго, индекс соберётся заново за 10–30 минут.'
       Svc = (SvcV WSearch Automatic)
       Start = 'WSearch' }
    @{ Id = 'time'; Title = 'Неправильное время на часах'
       Desc = 'Включает службу времени и сверяет часы с сервером времени. Нужен интернет.'
       Svc = (SvcV W32Time Manual)
       Start = 'W32Time'
       Run = { w32tm /resync /force | Out-Null } }
)
$RepairCatalog = @(
    @{ Title = 'Восстановить системные файлы'
       Desc = 'Проверяет и чинит повреждённые файлы Windows (DISM и sfc). Откроется окно с ходом проверки. Займёт 15–40 минут, нужен интернет.'
       Cmd = 'title OknoTune: ремонт & DISM /Online /Cleanup-Image /RestoreHealth & sfc /scannow & echo. & echo Готово. Если были исправления, перезагрузите компьютер. & pause' }
    @{ Title = 'Проверить диск на ошибки'
       Desc = 'Ищет ошибки файловой системы на диске C: без перезагрузки и без остановки работы. Откроется окно с результатом.'
       Cmd = 'title OknoTune: проверка диска & chkdsk C: /scan & echo. & pause' }
)
$DnsCatalog = [ordered]@{
    'Cloudflare' = '1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001'
    'Google'     = '8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844'
    'AdGuard'    = '94.140.14.14', '94.140.15.15', '2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff'
}
$ClassicLinks = [ordered]@{
    'Панель управления' = 'control.exe'; 'Сетевые подключения' = 'ncpa.cpl'; 'Электропитание' = 'powercfg.cpl'
    'Программы и компоненты' = 'appwiz.cpl'; 'Свойства системы' = 'sysdm.cpl'; 'Конфигурация системы' = 'msconfig.exe'
    'Службы' = 'services.msc'; 'Управление дисками' = 'diskmgmt.msc'; 'Диспетчер устройств' = 'devmgmt.msc'
}

function Get-DnsAdapters { @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }) }
function Get-DnsState {
    # NameServer в реестре пуст — DNS выдаёт роутер (DHCP); иначе прописан вручную
    foreach ($a in Get-DnsAdapters) {
        $v4 = Get-RegRaw "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)" 'NameServer'
        $v6 = Get-RegRaw "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$($a.InterfaceGuid)" 'NameServer'
        [pscustomobject]@{ Idx = $a.ifIndex; Name = $a.Name; Servers = @("$(if ($v4) { $v4.Value }) $(if ($v6) { $v6.Value })" -split '[,\s\x00]+' | Where-Object { $_ }) }   # в NameServer бывают хвостовые \0
    }
}
function Set-AdapterDns([int]$idx, $servers) {
    if (@($servers).Count) { Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $servers -ErrorAction Stop }
    else { Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop }
}
function Get-DnsLabel {
    $st = @(Get-DnsState)
    if (-not $st.Count) { return 'Нет активного сетевого подключения' }
    $srv = @($st | ForEach-Object { $_.Servers } | Select-Object -Unique)
    if (-not $srv.Count) { return 'Сейчас: автоматически (от роутера или провайдера)' }
    foreach ($k in $DnsCatalog.Keys) { if ($srv[0] -in $DnsCatalog[$k]) { return "Сейчас: $k ($($srv[0]))" } }
    "Сейчас: $($srv -join ', ')"
}

function Save-FixSnapshot($entry) {
    $file = Join-Path $script:DataDir ('snapshot-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))
    ConvertTo-Json -InputObject @($entry) -Depth 6 | Set-Content -Path $file -Encoding UTF8
}
function Confirm-Fix($f) {
    Show-Overlay $f.Title $f.Desc
    $off = @($f.Svc | Where-Object { (Get-SvcStart $_.S) -eq 'Disabled' } | ForEach-Object { $_.S })
    Add-OvText $(if ($off.Count) { "Будут включены отключённые службы: $($off -join ', ')." } else { 'Все нужные службы уже включены.' }) '#AEB4BF'
    if ($off.Count) { Add-OvText 'Прежние настройки служб сохранятся в «Истории», их можно откатить.' '#8B93A1' 12 }
    Add-OvButton 'Отмена' { Hide-Overlay } $null
    Add-OvButton 'Исправить' { param($x) Invoke-Fix $x } $f 'Primary'
}
function Invoke-Fix($f) {
    Show-Overlay $f.Title 'Не закрывайте окно'
    $script:OvProgress.Visibility = 'Visible'; $script:OvProgress.IsIndeterminate = $true; Pump
    $ok = @(); $bad = @()
    $changed = @($f.Svc | Where-Object { (Get-SvcStart $_.S) -eq 'Disabled' })
    if ($changed.Count) {
        Save-FixSnapshot ([pscustomobject]@{ Id = "fix:$($f.Id)"; Title = "Исправление: $($f.Title)"; Enable = $true; State = 'off'
            Reg = @(); Task = @(); Svc = @($changed | ForEach-Object { [pscustomobject]@{ S = $_.S; Start = 'Disabled' } }) })
    }
    foreach ($s in $changed) {
        Write-Log "Включаю службу $($s.S)"; Pump
        try { Set-SvcStart $s.S $s.V; $ok += "Служба $($s.S): $($s.V)" } catch { $bad += "Служба $($s.S): $($_.Exception.Message)" }
    }
    foreach ($n in @($f.Start)) { if ($n -and (Get-Service $n -ErrorAction SilentlyContinue)) { Start-Service $n -ErrorAction SilentlyContinue } }
    if ($f.Run) {
        Write-Log "Исправляю: $($f.Title)"; Pump
        try { & $f.Run; $ok += 'Сброс и перезапуск выполнены' } catch { $bad += $_.Exception.Message }
    }
    if (-not $ok.Count -and -not $bad.Count) { $ok += 'Службы уже были включены, менять ничего не пришлось' }
    $script:OvProgress.IsIndeterminate = $false
    Update-Caches -FastOnly; Update-States; Reset-Toggles; Update-Pending
    if ($f.Reboot) { Set-RebootPending }
    Write-Log "Исправление «$($f.Title)»: готово, ошибок $($bad.Count)"
    Show-Result $(if ($bad.Count) { 'Готово, но есть ошибки' } else { 'Готово' }) $ok $bad ([bool]$f.Reboot)
}
function Invoke-Dns([string]$name) {
    $servers = $(if ($name) { $DnsCatalog[$name] } else { @() })
    $st = @(Get-DnsState)
    if (-not $st.Count) { [void][Windows.MessageBox]::Show($script:Win, 'Нет активного сетевого подключения.', 'OknoTune'); return }
    Save-FixSnapshot ([pscustomobject]@{ Id = 'fix:dns'; Title = "DNS: $(if ($name) { $name } else { 'автоматически' })"; Enable = $true; State = 'off'
        Reg = @(); Svc = @(); Task = @(); Dns = $st })
    $ok = @(); $bad = @()
    foreach ($a in $st) {
        try { Set-AdapterDns $a.Idx $servers; $ok += "$($a.Name): $(if ($name) { $servers -join ', ' } else { 'автоматически' })" } catch { $bad += "$($a.Name): $($_.Exception.Message)" }
    }
    ipconfig /flushdns | Out-Null
    Write-Log "DNS: $(if ($name) { $name } else { 'автоматически' })"
    $script:DnsLabel.Text = Get-DnsLabel
    Show-Result $(if ($bad.Count) { 'Готово, но есть ошибки' } else { 'DNS изменён' }) $ok $bad $false
}

function New-FixButton([string]$text, $tag, [scriptblock]$click, [string]$style = 'Btn') {
    $b = New-Object Windows.Controls.Button
    $b.Content = $text; $b.Tag = $tag; $b.Style = $script:Styles[$style]; $b.Margin = '0,0,0,6'; $b.MinWidth = 160; $b.HorizontalAlignment = 'Stretch'
    $b.Add_Click($click)
    $b
}
function Add-FixHeader([string]$text) {
    $h = New-Object Windows.Controls.TextBlock
    $h.Text = $text; $h.FontSize = 11; $h.FontWeight = 'SemiBold'; $h.Foreground = Brush '#6B7380'; $h.Margin = '2,14,0,8'
    [void]$script:FixList.Children.Add($h)
}
function New-FixCard([string]$kind, [string]$title, [string]$desc, [string]$color) {
    $card = New-Xaml $DrvXaml
    $card.FindName('K').Text = $kind; $card.FindName('T').Text = $title; $card.FindName('D').Text = $desc
    $card.FindName('Stripe').Background = Brush $color
    [void]$script:FixList.Children.Add($card)
    $card
}
function Build-Fixes {
    $script:FixList.Children.Clear()
    Add-FixHeader 'ЧАСТЫЕ ПРОБЛЕМЫ'
    foreach ($f in $FixCatalog) {
        $card = New-FixCard $(if ($f.Reboot) { 'НУЖНА ПЕРЕЗАГРУЗКА' } else { 'ИСПРАВЛЕНИЕ' }) $f.Title $f.Desc '#4F8CFF'
        [void]$card.FindName('Btns').Children.Add((New-FixButton 'Исправить' $f { Confirm-Fix $this.Tag } 'Primary'))
    }
    Add-FixHeader 'РЕМОНТ WINDOWS'
    foreach ($r in $RepairCatalog) {
        $card = New-FixCard 'ДОЛГО' $r.Title $r.Desc '#D29922'
        [void]$card.FindName('Btns').Children.Add((New-FixButton 'Запустить' $r.Cmd { Start-Process cmd.exe -ArgumentList "/c $($this.Tag)" } 'Primary'))
    }
    Add-FixHeader 'DNS-СЕРВЕР'
    $card = New-FixCard 'СЕТЬ' 'Сменить DNS' 'DNS превращает адреса сайтов в IP. Свой DNS иногда открывает сайты быстрее, а AdGuard ещё и режет рекламу. Прежний DNS сохранится в «Истории».' '#3FB950'
    $script:DnsLabel = $card.FindName('A'); $script:DnsLabel.Foreground = Brush '#7FA8FF'; $script:DnsLabel.Text = 'Проверяю текущий DNS…'
    # Get-NetAdapter занимает до секунды — читаем в фоне
    Start-Bg 'dns' @('Get-DnsLabel', 'Get-DnsState', 'Get-DnsAdapters', 'Get-RegRaw', 'Format-RegVal') @{ DnsCatalog = $DnsCatalog } { param($sync) Get-DnsLabel } $null {
        param($s) $script:DnsLabel.Text = $(if ($s.Error) { 'Не удалось прочитать текущий DNS' } else { "$($s.Result[0])" })
    }
    $btns = $card.FindName('Btns')
    foreach ($k in $DnsCatalog.Keys) { [void]$btns.Children.Add((New-FixButton $k $k { Invoke-Dns $this.Tag })) }
    [void]$btns.Children.Add((New-FixButton 'Автоматически' '' { Invoke-Dns '' }))
    Add-FixHeader 'КЛАССИЧЕСКИЕ ОКНА WINDOWS'
    $wrap = New-Object Windows.Controls.WrapPanel
    foreach ($k in $ClassicLinks.Keys) {
        $b = New-FixButton $k $ClassicLinks[$k] { Start-Process $this.Tag }
        $b.Margin = '0,0,8,8'; $b.MinWidth = 200; $b.HorizontalAlignment = 'Left'
        [void]$wrap.Children.Add($b)
    }
    [void]$script:FixList.Children.Add($wrap)
    $script:FixBuilt = $true
}
#endregion

function Initialize-Ui {
    Invoke-HistoryPrune
    Initialize-Items
    Build-List
    Add-NavItem 'home' 0xE80F 'Главная'
    Add-NavHeader 'НАСТРОЙКИ'
    Add-NavItem 'Все' 0xE71D 'Все настройки'
    foreach ($c in $Cats.Keys) { if (@($script:Items | Where-Object { $_.Cat -eq $c }).Count) { Add-NavItem $c $Cats[$c] $c } }
    Add-NavHeader 'ИНСТРУМЕНТЫ'
    Add-NavItem 'clean' 0xE74D 'Очистка диска'
    Add-NavItem 'startup' 0xE7E8 'Автозагрузка'
    Add-NavItem 'drivers' 0xE772 'Драйверы'
    Add-NavItem 'fixes' 0xE9D9 'Исправления'
    Add-NavItem 'apps' 0xE8F1 'Полезные программы'
    Add-NavItem 'history' 0xE81C 'История'
    $script:RebootPending = (Test-Path $script:RebootFile) -and ((Get-Content $script:RebootFile -Raw).Trim() -eq (Get-BootTicks))
    if (-not $script:RebootPending) { Remove-Item $script:RebootFile -ErrorAction SilentlyContinue }
    $os = Get-CimInstance Win32_OperatingSystem
    $script:SysInfo.Text = "$($os.Caption)`nсборка $($os.BuildNumber)  ·  $env:USERNAME"
    $script:Loading.Visibility = 'Collapsed'
    Reset-Toggles; Update-Pending
    Select-Nav 'home'
    Write-Log "Настроек: $($script:Items.Count) · применено: $(@($script:Items | Where-Object { $_.State -eq 'on' }).Count)"
}

$script:Nav.Add_SelectionChanged({
    if ($script:NavBusy -or -not $script:Nav.SelectedItem) { return }
    $tag = $script:Nav.SelectedItem.Tag
    if ($tag -in 'home', 'history', 'clean', 'startup', 'drivers', 'apps', 'fixes') { Show-View $tag }
    else { $script:CurCat = $tag; Show-View 'list' }
})
$script:Search.Add_TextChanged({ $script:SearchHint.Visibility = $(if ($script:Search.Text) { 'Collapsed' } else { 'Visible' }); if ($script:Items) { Update-View } })
foreach ($chip in $script:ChipPending, $script:ChipSafe, $script:ChipReboot) { $chip.Add_Click({ Update-View }) }
$script:BtnSafe.Add_Click({
    foreach ($it in $script:Items) { if ($it.Impact -eq 'none' -and $it.Card.Visibility -eq 'Visible' -and $it.State -ne 'on') { $it.Toggle.IsChecked = $true } }
    Update-Pending
})
$script:BtnReset.Add_Click({ Reset-Toggles; Update-Pending })
$script:BtnProfSave.Add_Click({ Export-Profile })
$script:BtnProfLoad.Add_Click({ Import-Profile })
$script:BtnApply.Add_Click({ Show-Review })
$script:BtnReboot.Add_Click({ Invoke-Reboot })
$script:BtnReboot2.Add_Click({ Invoke-Reboot })
$script:BtnStart.Add_Click({ Start-Wizard })
$script:BtnManual.Add_Click({ Select-Nav 'Все' })
$script:WizBack.Add_Click({ Select-Nav 'home' })
$script:WizNext.Add_Click({ Complete-Wizard })
$script:BtnLog.Add_Click({ Start-Process explorer.exe $script:DataDir })
$script:BtnClean.Add_Click({ Confirm-Clean })
$script:BtnRescan.Add_Click({ Update-CleanSizes })
$script:BtnCleanMgr.Add_Click({ Start-Process cleanmgr.exe })
$script:BtnSuApply.Add_Click({ Confirm-Startup })
$script:BtnSuRescan.Add_Click({ Invoke-Busy 'Проверяю автозагрузку…' { Build-Startup } })
$script:BtnHistClear.Add_Click({ Confirm-HistoryClear })
$script:BtnDrvRescan.Add_Click({ Build-Drivers })
$script:BtnDevMgr.Add_Click({ Start-Process devmgmt.msc })
$script:BtnWuDrivers.Add_Click({ Open-Url 'ms-settings:windowsupdate-optionalupdates' })
$script:Win.Add_SourceInitialized({
    $h = (New-Object Windows.Interop.WindowInteropHelper $script:Win).Handle
    $v = 1; [void][WT.Native]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)          # dark title bar
    $c = 0x0015110F; [void][WT.Native]::DwmSetWindowAttribute($h, 35, [ref]$c, 4)  # caption color (Win11)
})
$script:AcceptFile = Join-Path $script:DataDir 'accepted.txt'
function Show-Welcome {
    # один раз при первом запуске; согласие запоминается файлом accepted.txt
    Show-Overlay 'Перед началом' 'OknoTune меняет настройки Windows с правами администратора.'
    Add-OvLine 'Почти всё откатывается в «Истории»' '  — кроме удалённых приложений и файлов.' '#3FB950'
    Add-OvLine 'Не выключайте точку восстановления' '  — это запасной выход.' '#D29922'
    Add-OvLine 'Замерьте FPS в любимой игре до и после' '  — так будет виден реальный результат.' '#4F8CFF'
    Add-OvText 'Программа предоставляется «как есть», без гарантий (лицензия MIT).' '#6B7380' 12 '0,10,0,0'
    Add-OvButton 'Выйти' { $script:Win.Close() } $null
    Add-OvButton 'Понятно, начать' { Set-Content -Path $script:AcceptFile -Value (Get-Date -Format s) -Encoding UTF8; Hide-Overlay } $null 'Primary'
}
function Finish-Startup {
    # скан железа и каталога готов (или не удался) — строим интерфейс
    Initialize-Ui
    if (-not $Snapshot -and -not (Test-Path $script:AcceptFile)) { Show-Welcome }
    if ($Snapshot) {
        # <вкладка>-busy — снимок посреди фонового скана, иначе ждём, пока он закончится
        switch ($View -replace '-busy$', '') {
            'list'    { Select-Nav 'Все' }
            'history' { Select-Nav 'history' }
            'clean'   { Select-Nav 'clean' }
            'startup' { Select-Nav 'startup' }
            'drivers' { Select-Nav 'drivers' }
            'apps'    { Select-Nav 'apps' }
            'fixes'   { Select-Nav 'fixes' }
            'welcome' { Show-Welcome }
            'wizard'  { Start-Wizard }
            'review'  { Start-Wizard; $script:QRadios['privacy']['yes'].IsChecked = $true; $script:QRadios['games']['yes'].IsChecked = $true; Complete-Wizard }
        }
        if ($View -like '*-busy') { Start-Sleep -Milliseconds 700; foreach ($j in @($script:BgJobs.Values)) { if ($j.Tick) { & $j.Tick $j.Sync } } }
        else { Wait-Bg }
        Pump
        $el = $script:Win.Content
        $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$el.ActualWidth), ([int]$el.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $rtb.Render($el)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($Snapshot); $enc.Save($fs); $fs.Close()
        $script:Win.Close()
    }
}
$script:Win.Add_ContentRendered({
    # медленная часть сканирования уже идёт фоном; ждём её без блокировки окна (лимит 20 секунд)
    if (-not $script:SlowScan -or $script:SlowScan.Table.Done) { Finish-Startup; return }
    $script:ScanTicks = 0
    $script:ScanTimer = New-Object Windows.Threading.DispatcherTimer
    $script:ScanTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $script:ScanTimer.Add_Tick({
        $script:ScanTicks++
        if ($script:SlowScan.Table.Done) { $script:ScanTimer.Stop(); Finish-Startup }
        elseif ($script:ScanTicks -ge 200) { $script:ScanTimer.Stop(); Stop-SlowScan; Finish-Startup }
    })
    $script:ScanTimer.Start()
})
Start-SlowScan
if ($Snapshot) { $script:Win.WindowStartupLocation = 'Manual'; $script:Win.Left = -4000; $script:Win.Top = 0; $script:Win.ShowInTaskbar = $false }
[void]$script:Win.ShowDialog()
#endregion
