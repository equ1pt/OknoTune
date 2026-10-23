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
