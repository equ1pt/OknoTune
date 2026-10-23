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
    $script:DrvList.Children.Clear()
    $script:DrvStatus.Text = 'Проверяю устройства…'; Pump
    $cards = @(Get-DriverInfo)
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
