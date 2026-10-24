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
    # видимые плитки раскладываем заново, иначе на месте скрытых остались бы дыры
    foreach ($g in $script:CatGrids.Values) { $g.Children.Clear() }
    $shown = 0; $on = 0
    foreach ($it in $script:Items) {
        $text = "$($it.Title) $($it.Short) $($it.Desc) $($it.Warn)"
        $vis = ($all -or $it.Cat -eq $script:CurCat) -and
               (-not $q -or $text.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -and
               (-not $script:ChipPending.IsChecked -or $it.State -ne 'on') -and
               (-not $script:ChipSafe.IsChecked -or $it.Impact -eq 'none') -and
               (-not $script:ChipReboot.IsChecked -or $it.Reboot)
        $it.Card.Visibility = $(if ($vis) { 'Visible' } else { 'Collapsed' })
        if ($vis) { $shown++; if ($it.State -eq 'on') { $on++ }; $script:Headers[$it.Cat].Visibility = 'Visible'; Add-Tile2 $script:CatGrids[$it.Cat] $it.Card }
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
        $grid = New-Object Windows.Controls.Grid; $grid.Margin = '0,0,-10,0'
        1..2 | ForEach-Object { $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) }
        $script:CatGrids[$cat] = $grid; [void]$script:List.Children.Add($grid)
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
            Add-Tile2 $grid $card
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
function Start-FadeIn($el) {
    # проявление и сдвиг на 8 px снизу, 180 мс; в -Snapshot без анимации, иначе снимок выйдет полупрозрачным
    if ($Snapshot) { return }
    $dur = [Windows.Duration][TimeSpan]::FromMilliseconds(180)
    $ease = New-Object Windows.Media.Animation.QuadraticEase -Property @{ EasingMode = 'EaseOut' }
    $tt = New-Object Windows.Media.TranslateTransform; $el.RenderTransform = $tt
    $el.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation -Property @{ From = 0; To = 1; Duration = $dur; EasingFunction = $ease }))
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (New-Object Windows.Media.Animation.DoubleAnimation -Property @{ From = 8; To = 0; Duration = $dur; EasingFunction = $ease }))
}
function Show-View([string]$v) {
    $script:CurView = $v
    $views = @{ home = $script:HomeView; wizard = $script:WizardView; list = $script:ListView; history = $script:HistoryView; clean = $script:CleanView; startup = $script:StartupView; drivers = $script:DriversView; apps = $script:AppsView; fixes = $script:FixView }
    foreach ($k in $views.Keys) { $views[$k].Visibility = $(if ($k -eq $v) { 'Visible' } else { 'Collapsed' }) }
    # анимируем только смену раздела или категории: Hide-Overlay снова показывает тот же раздел
    $key = "$v|$(if ($v -eq 'list') { $script:CurCat })"
    if ($key -ne $script:LastShown) { $script:LastShown = $key; Start-FadeIn $views[$v] }
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
    $script:HomeApps.Text = "$apps"
    $snaps = @(Get-ChildItem -Path $script:DataDir -Filter 'snapshot-*.json' -ErrorAction SilentlyContinue).Count
    $script:HomeSnaps.Text = "$snaps"
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

#region Feedback: Google Form, заполненная заранее; отправляет сам пользователь
$FeedbackForm = 'https://docs.google.com/forms/d/e/1FAIpQLSccuidwtiVW_wYU4d-Fho5KH2bjUJKghmrY3M7iF6exg0-YpQ/viewform'
$FeedbackFields = @{ Section = 'entry.1250054791'; Version = 'entry.1466109807'; Windows = 'entry.859605807'; Log = 'entry.1585251946' }
function Get-AnonLog([int]$lines = 300) {
    # журнал без имени пользователя и компьютера
    if (-not (Test-Path $script:LogFile)) { return '' }
    $t = @(Get-Content -Path $script:LogFile -Tail $lines -Encoding UTF8) -join "`n"
    if ($env:USERPROFILE) { $t = $t -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%' }
    if ($env:USERNAME) { $t = $t -replace "(?i)(?<!\w)$([regex]::Escape($env:USERNAME))(?!\w)", '<user>' }
    if ($env:COMPUTERNAME) { $t = $t -replace "(?i)(?<!\w)$([regex]::Escape($env:COMPUTERNAME))(?!\w)", '<pc>' }
    $t
}
function Get-WinLabel {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    "$((Get-CimInstance Win32_OperatingSystem).Caption) $($cv.DisplayVersion) (сборка $($cv.CurrentBuild).$($cv.UBR))".Trim()
}
function Get-ReportUrl([string]$log) {
    # раздел — по текущей вкладке; значения должны совпадать с пунктами списка в форме
    $section = switch ($script:CurView) { { $_ -in 'home', 'wizard' } { 'Главное окно' } 'list' { 'Настройки' }
        { $_ -in 'clean', 'startup', 'drivers', 'fixes', 'apps' } { 'Инструменты' } default { 'Другое' } }
    $q = "usp=pp_url&$($FeedbackFields.Section)=$([Uri]::EscapeDataString($section))&$($FeedbackFields.Version)=$([Uri]::EscapeDataString($script:Version))&$($FeedbackFields.Windows)=$([Uri]::EscapeDataString((Get-WinLabel)))"
    # в ссылку — только конец журнала: длину адреса ограничивает браузер; полный журнал уходит в буфер обмена
    $tail = @($log -split "`n"); $take = $tail.Count
    while ($take -gt 0 -and [Uri]::EscapeDataString(($tail[-$take..-1] -join "`n")).Length -gt 4000) { $take-- }
    if ($take -gt 0) { $q += "&$($FeedbackFields.Log)=$([Uri]::EscapeDataString(($tail[-$take..-1] -join "`n")))" }
    "$FeedbackForm`?$q"
}
function Confirm-Report {
    Show-Overlay 'Сообщить о проблеме' 'Откроется Google Форма. Входить в Google не нужно, отправляете вы сами.'
    Add-OvLine 'Уже заполнено' '  — версия OknoTune, Windows, раздел программы и последние строки журнала.' '#4F8CFF'
    Add-OvLine 'Журнал целиком скопируется в буфер обмена' '  — если в форме не все строки, вставьте его в поле «Журнал» (Ctrl+V).' '#D29922'
    Add-OvLine 'Имя пользователя и компьютера' '  — в журнале заменены на <user> и <pc>.' '#3FB950'
    Add-OvLine 'Не пишите личные данные' '  — имя, телефон, почту, адрес. Ответ на заявку будет в описании нового релиза.' '#F85149'
    Add-OvButton 'Отмена' { Hide-Overlay } $null
    Add-OvButton 'Открыть форму' { Open-Report } $null 'Primary'
}
function Open-Report {
    $log = Get-AnonLog
    try { if ($log) { [Windows.Clipboard]::SetText($log) } } catch {}
    Open-Url (Get-ReportUrl $log)
    Write-Log 'Открыта форма обратной связи'
    Hide-Overlay
}
#endregion
