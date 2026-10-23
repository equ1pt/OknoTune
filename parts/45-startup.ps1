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
