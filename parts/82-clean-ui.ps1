#region Cleanup UI
$CleanXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Margin="0,0,10,10" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
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
    Build-DevClean
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
        Add-Tile2 $script:CleanList $card
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
# Карточки устройств и драйверов под файлами; скан в фоне
function Build-DevClean {
    if ($script:BgJobs['devclean']) { return }
    $script:DevList.Children.Clear(); $script:DevList.RowDefinitions.Clear()
    Start-Bg 'devclean' @('Get-DevCleanCards', 'Get-GhostDevices', 'Get-StaleDrivers') @{} { param($sync) Get-DevCleanCards $sync } $null {
        param($s)
        if ($s.Error) { Write-Log "Устройства и драйверы: $($s.Error)"; return }
        foreach ($d in @($s.Result)) {
            $card = New-Xaml $DrvXaml
            $card.FindName('K').Text = $d.Kind.ToUpper(); $card.FindName('T').Text = $d.Title; $card.FindName('D').Text = $d.Details
            $card.FindName('Stripe').Background = Brush $(if ($d.Items.Count) { '#D29922' } else { '#3FB950' })
            if ($d.Items.Count) { [void]$card.FindName('Btns').Children.Add((New-AppButton 'Выбрать и удалить' $d 'Primary' { Show-DrvCleanup $this.Tag })) }
            Add-Tile2 $script:DevList $card
        }
    }
}
# Окно со списком галочек: отключённые устройства или лишние драйверы
function Show-DrvCleanup($d) {
    $ghosts = $d.Action -eq 'ghosts'
    Show-Overlay $(if ($ghosts) { 'Отключённые устройства' } else { 'Лишние драйверы' }) $(if ($ghosts) {
            'Отмеченные записи будут удалены из системы. Подключите устройство снова — Windows установит его заново.'
        } else { 'Удалённый драйвер не вернуть без установщика. Если устройство подключается редко (принтер, донгл, телефон), оставьте его драйвер.' })
    if (-not $ghosts) { Add-OvBox 'Сначала удалите отключённые устройства' @('Драйвер, который записан за отключённым устройством, Windows не удалит.', 'Отмечены только старые версии: новая версия того же драйвера остаётся.') '#2A2311' '#6B5418' '#F2CC60' }
    $boxes = @()
    foreach ($it in $d.Items) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Foreground = Brush '#E6E8EB'; $cb.Margin = '0,0,0,6'; $cb.Tag = $it
        $cb.Content = $(if ($ghosts) { "$($it.Name)   ·   $($it.Class)" } else {
                "$($it.Provider) — $($it.Name) $($it.Version)$(if ($it.Date) { ' от ' + ([datetime]$it.Date).ToString('dd.MM.yyyy') })   ·   $($it.Class)$(if ($it.Old) { '   ·   старая версия' })" })
        $cb.IsChecked = $ghosts -or $it.Old
        [void]$script:OvBody.Children.Add($cb); $boxes += $cb
    }
    Add-OvButton 'Отмена' { Hide-Overlay } $null
    Add-OvButton 'Удалить отмеченное' { Invoke-DrvCleanup $script:DrvCleanAction @($script:DrvCleanBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag }) } $null 'Primary'
    $script:DrvCleanAction = $d.Action; $script:DrvCleanBoxes = $boxes
}
function Invoke-DrvCleanup([string]$action, $items) {
    if (-not $items.Count) { return }
    Show-Overlay 'Удаляю' 'Не закрывайте окно'
    $script:OvProgress.Visibility = 'Visible'; Pump
    if ($action -eq 'drivers') {
        $err = New-RestorePoint 'OknoTune: драйверы'
        if ($err) { Write-Log "Точка восстановления не создана: $err" }
    }
    $ok = 0; $fail = @(); $i = 0
    foreach ($it in $items) {
        $i++; $script:OvProgress.Value = 100 * $i / $items.Count
        $name = $(if ($action -eq 'ghosts') { $it.Name } else { "$($it.Provider) — $($it.Name) $($it.Version)" })
        $script:OvSub.Text = $name; Pump
        # без /force: используемый драйвер pnputil не удалит
        $out = $(if ($action -eq 'ghosts') { & pnputil.exe /remove-device $it.Id 2>&1 } else { & pnputil.exe /delete-driver $it.Inf 2>&1 })
        if ($LASTEXITCODE -eq 0) { $ok++; Write-Log "Удалено: $name" } else { $fail += $name; Write-Log "Не удалено: $name — $(($out | Out-String).Trim())" }
    }
    Show-Overlay 'Готово' "Удалено: $ok из $($items.Count)."
    if ($fail.Count) { Add-OvBox 'Не удалось удалить (драйвер используется или занят отключённым устройством; подробности в журнале)' $fail '#2A1416' '#6B2A2E' '#FF7B72' }
    Add-OvButton 'Готово' { $script:Overlay.Visibility = 'Collapsed'; Build-DevClean } $null 'Primary'
}
#endregion
