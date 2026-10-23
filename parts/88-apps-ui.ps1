#region Recommended apps
# «Открыть сайт» — официальный сайт в браузере; «Установить» — winget, если у программы есть пакет.
# Adv = $true — для опытных (жёлтая полоска).
$AppCatalog = [ordered]@{
    'На каждый день' = @(
        @{ Name = '7-Zip'; Url = 'https://www.7-zip.org/'
           Desc = 'Архиватор. Открывает и создаёт архивы ZIP, RAR, 7z и другие. Бесплатный и быстрее встроенного в Windows.' }
        @{ Name = 'Notepad++'; Url = 'https://notepad-plus-plus.org/downloads/'
           Desc = 'Удобный блокнот. Подсвечивает код, открывает большие файлы, умеет искать и заменять сразу в нескольких файлах.' }
        @{ Name = 'Everything'; Url = 'https://www.voidtools.com/ru-ru/'
           Desc = 'Мгновенный поиск файлов по имени на всех дисках. Находит нужное за доли секунды, в отличие от поиска Windows.' }
        @{ Name = 'qBittorrent'; Url = 'https://www.qbittorrent.org/'
           Desc = 'Торрент-клиент без рекламы и лишних программ в установщике. Простой, бесплатный, с открытым кодом.' }
    )
    'Обслуживание системы' = @(
        @{ Name = 'HiBit Uninstaller'; Url = 'https://www.hibitsoft.ir/Uninstaller.html'
           Desc = 'Удаляет программы вместе с «хвостами»: оставшимися папками и записями в реестре. Помогает, когда программа не удаляется обычным способом.' }
        @{ Name = 'SpaceSniffer'; Url = 'http://www.uderzo.it/main_products/space_sniffer/'
           Desc = 'Показывает, чем занят диск, в виде цветных блоков: чем больше блок, тем больше файл или папка. Сразу видно, что съело место.' }
        @{ Name = 'Easy Service Optimizer'; Url = 'https://www.sordum.org/8637/easy-service-optimizer-v1-2/'; Adv = $true
           Desc = 'Отключает лишние службы Windows по готовым профилям. Есть откат к настройкам по умолчанию. Если не уверены, что делает служба, не трогайте её.' }
    )
    'Драйверы и устройства' = @(
        @{ Name = 'DriverStore Explorer'; Url = 'https://github.com/lostindark/driverstoreExplorer'; Adv = $true
           Desc = 'Показывает все драйверы, которые Windows хранит про запас, и удаляет старые версии. Освобождает от сотен мегабайт до нескольких гигабайт. Удаляйте только старые версии, текущие оставьте.' }
        @{ Name = 'Device Cleanup Tool'; Url = 'https://www.usbdev.ru/files/devicecleanup/'
           Desc = 'Удаляет из системы записи об устройствах, которые давно не подключались: старые флешки, телефоны, принтеры. Полезно, если устройство перестало определяться.' }
    )
    'Проверка на вирусы' = @(
        @{ Name = 'Kaspersky Virus Removal Tool'; Url = 'https://www.kaspersky.ru/downloads/free-virus-removal-tool'
           Desc = 'Разовая проверка компьютера на вирусы. Установка не нужна, с обычным антивирусом не конфликтует.' }
        @{ Name = 'Dr.Web CureIt!'; Url = 'https://free.drweb.ru/cureit/'
           Desc = 'Ещё один бесплатный разовый сканер. Хорошо подходит как второе мнение после другого антивируса.' }
        @{ Name = 'AdwCleaner'; Url = 'https://www.malwarebytes.com/ru/adwcleaner'
           Desc = 'Убирает рекламное ПО, навязанные панели в браузере и подменённую стартовую страницу. Обычные антивирусы такое часто пропускают.' }
    )
}
# Пакеты winget: у остальных программ пакета нет, только сайт
$WinGetIds = @{ '7-Zip' = '7zip.7zip'; 'Notepad++' = 'Notepad++.Notepad++'; 'Everything' = 'voidtools.Everything'; 'qBittorrent' = 'qBittorrent.qBittorrent'
                'HiBit Uninstaller' = 'HiBitSoftware.HiBitUninstaller'; 'SpaceSniffer' = 'UderzoSoftware.SpaceSniffer'
                'DriverStore Explorer' = 'lostindark.DriverStoreExplorer'; 'AdwCleaner' = 'Malwarebytes.AdwCleaner' }
function Install-App([string]$id) {
    # отдельное окно консоли: видно ход установки, OknoTune не зависает
    Write-Log "Устанавливаю через winget: $id"
    Start-Process cmd.exe -ArgumentList "/c title OknoTune: установка $id & winget install --id $id -e --accept-source-agreements --accept-package-agreements & echo. & pause"
}
function Build-Apps {
    $script:AppsList.Children.Clear()
    $winget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
    foreach ($cat in $AppCatalog.Keys) {
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = $cat.ToUpper(); $h.FontSize = 11; $h.FontWeight = 'SemiBold'; $h.Foreground = Brush '#6B7380'; $h.Margin = '2,14,0,8'
        [void]$script:AppsList.Children.Add($h)
        foreach ($a in $AppCatalog[$cat]) {
            $card = New-Xaml $DrvXaml
            $card.FindName('K').Text = $(if ($a.Adv) { 'ДЛЯ ОПЫТНЫХ' } else { 'БЕСПЛАТНО' })
            $card.FindName('T').Text = $a.Name
            $card.FindName('D').Text = $a.Desc
            $card.FindName('Stripe').Background = Brush $(if ($a.Adv) { '#D29922' } else { '#3FB950' })
            $al = $card.FindName('A'); $al.Text = ([Uri]$a.Url).Host -replace '^www\.', ''; $al.Foreground = Brush '#7FA8FF'
            $btns = $card.FindName('Btns'); $id = $WinGetIds[$a.Name]
            if ($winget -and $id) {
                $ib = New-Object Windows.Controls.Button
                $ib.Content = 'Установить'; $ib.Tag = $id; $ib.ToolTip = "winget install $id"; $ib.MinWidth = 160; $ib.Margin = '0,0,0,6'; $ib.Style = $script:Styles['Primary']
                $ib.Add_Click({ Install-App $this.Tag })
                [void]$btns.Children.Add($ib)
            }
            $btn = New-Object Windows.Controls.Button
            $btn.Content = 'Открыть сайт'; $btn.Tag = $a.Url; $btn.ToolTip = $a.Url; $btn.MinWidth = 160
            $btn.Style = $script:Styles[$(if ($winget -and $id) { 'Btn' } else { 'Primary' })]
            $btn.Add_Click({ Open-Url $this.Tag })
            [void]$btns.Children.Add($btn)
            [void]$script:AppsList.Children.Add($card)
        }
    }
    $script:AppsBuilt = $true
}
#endregion
