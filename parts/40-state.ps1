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
