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
