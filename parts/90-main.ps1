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
    $script:SysInfo.Text = "OknoTune $script:Version`n$($os.Caption)`nсборка $($os.BuildNumber)  ·  $env:USERNAME"
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
$script:BtnReport.Add_Click({ Confirm-Report })
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
            'report'  { Confirm-Report }
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
