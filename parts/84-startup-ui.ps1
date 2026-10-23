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
