#region Registry / services / tasks helpers
function Open-Key([string]$p, [bool]$create) {
    $hive, $sub = $p -split ':\\', 2
    $root = if ($hive -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    if ($create) { $root.CreateSubKey($sub) } else { $root.OpenSubKey($sub, $true) }
}
function Get-RegRaw([string]$p, [string]$n) {
    $hive, $sub = $p -split ':\\', 2
    $root = if ($hive -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $k = $root.OpenSubKey($sub)
    if (-not $k) { return $null }
    try {
        $v = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
        if ($null -eq $v) { return $null }
        [pscustomobject]@{ Value = (Format-RegVal $v); Kind = "$($k.GetValueKind($n))" }
    } finally { $k.Close() }
}
function Format-RegVal($v) {
    if ($v -is [byte[]]) { return ([BitConverter]::ToString($v) -replace '-', '') }
    if ($v -is [int] -and $v -lt 0) { return [string]([long]$v + 4294967296) }
    "$v"
}
function Set-Reg([string]$p, [string]$n, $v, [string]$kind) {
    $k = Open-Key $p $true
    try {
        switch ($kind) {
            'String'       { $k.SetValue($n, [string]$v, 'String') }
            'ExpandString' { $k.SetValue($n, [string]$v, 'ExpandString') }
            'QWord'        { $k.SetValue($n, [long]$v, 'QWord') }
            'Binary'       { if ($v -is [byte[]]) { $b = $v } else { $b = New-Object byte[] ("$v".Length / 2); for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte("$v".Substring(2 * $i, 2), 16) } }; $k.SetValue($n, $b, 'Binary') }
            default        { $k.SetValue($n, [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]"$v"), 0), 'DWord') }
        }
    } finally { $k.Close() }
}
function Remove-Reg([string]$p, [string]$n) {
    $k = Open-Key $p $false
    if ($k) { $k.DeleteValue($n, $false); $k.Close() }
}
function Get-SvcStart([string]$s) {
    $x = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($x) { "$($x.StartType)" }
}
function Set-SvcStart([string]$s, [string]$mode) {
    if ($mode -eq 'Disabled') { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    try { Set-Service -Name $s -StartupType $mode -ErrorAction Stop }
    catch {
        # some services refuse Set-Service; the Start value works for them
        $n = @{ Automatic = 2; Manual = 3; Disabled = 4 }[$mode]
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\$s" 'Start' $n 'DWord'
    }
}
function Set-TaskEnabled([string]$full, [bool]$enabled) {
    $i = $full.LastIndexOf('\')
    $tp = $full.Substring(0, $i + 1); $tn = $full.Substring($i + 1)
    if ($enabled) { Enable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
}
$GuidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$FastPlanRx = 'Ultimate Performance|High performance|Максимальная производительность|Высокая производительность'
$UsbSub = '2a737441-1930-4402-8d77-b2bebba308a3'; $UsbSet = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
#endregion
