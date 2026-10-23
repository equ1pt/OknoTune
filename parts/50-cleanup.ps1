#region Cleanup catalog
# Only paths under these roots are ever deleted; reparse points (junctions/symlinks) are never followed.
$script:CleanRoots = @($env:windir, $env:LOCALAPPDATA, $env:ProgramData) | ForEach-Object { $_.TrimEnd('\') }
function Test-SafePath([string]$p) {
    $full = [IO.Path]::GetFullPath($p)
    foreach ($r in $script:CleanRoots) { if ($full.StartsWith("$r\", [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    $false
}
function Get-FilesSafe([string]$dir) {
    foreach ($e in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
        if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($e.PSIsContainer) { Get-FilesSafe $e.FullName } else { $e }
    }
}
function Get-CleanFiles($c) {
    $cut = (Get-Date).AddHours(-[int]$c.MinAge)
    foreach ($p in @(& $c.Paths)) {
        if (-not $p -or -not (Test-SafePath $p) -or -not (Test-Path -LiteralPath $p)) { continue }
        $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $i -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        if ($i.PSIsContainer) { Get-FilesSafe $p | Where-Object { $_.LastWriteTime -lt $cut } } elseif ($i.LastWriteTime -lt $cut) { $i }
    }
}
function Get-CleanSize($c) {
    if ($c.Size) { return (& $c.Size) }
    [long](@(Get-CleanFiles $c) | Measure-Object Length -Sum).Sum
}
function Format-Size($b) {
    if ($null -eq $b) { return '—' }
    if ($b -ge 1GB) { '{0:N1} ГБ' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} МБ' -f ($b / 1MB) } elseif ($b -gt 0) { '{0:N0} КБ' -f [Math]::Max(1, $b / 1KB) } else { '0' }
}
function Get-FreeBytes { [long](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace }
function Invoke-Clean($c) {
    if ($c.Before) { & $c.Before }
    if ($c.Clean) { & $c.Clean; return }
    $files = @(Get-CleanFiles $c)
    foreach ($f in $files) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    # remove folders left empty, but never the listed folders themselves
    foreach ($p in @(& $c.Paths)) {
        if (-not $p -or -not (Test-SafePath $p) -or -not (Test-Path -LiteralPath $p -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $p -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
}
$Lad = $env:LOCALAPPDATA
$script:CleanItems = @(
    @{ Id = 'usertemp'; Title = 'Временные файлы пользователя'; Impact = 'none'; Default = $true; MinAge = 24
       Desc = 'Папка TEMP вашей учётной записи. Файлы моложе суток не трогаем: их может использовать работающий установщик.'
       Paths = { $env:TEMP } }
    @{ Id = 'wintemp'; Title = 'Временные файлы Windows'; Impact = 'none'; Default = $true; MinAge = 24
       Desc = 'Системная папка Windows\Temp. Файлы моложе суток не трогаем.'
       Paths = { "$env:windir\Temp" } }
    @{ Id = 'wucache'; Title = 'Загрузки Windows Update'; Impact = 'none'; Default = $true
       Desc = 'Пакеты уже скачанных обновлений. Если какое-то ещё не установлено, Windows скачает его заново.'
       Paths = { "$env:windir\SoftwareDistribution\Download" }
       Before = { Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue } }
    @{ Id = 'docache'; Title = 'Кэш оптимизации доставки'; Impact = 'none'; Default = $true
       Desc = 'Копии обновлений, которые Windows хранит, чтобы раздавать другим ПК.'
       Paths = { "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" }
       Clean = { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue } }
    @{ Id = 'wer'; Title = 'Отчёты об ошибках'; Impact = 'none'; Default = $true
       Desc = 'Отчёты о сбоях программ, которые Windows собирала для отправки в Microsoft.'
       Paths = { "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$Lad\Microsoft\Windows\WER" } }
    @{ Id = 'thumbs'; Title = 'Кэш миниатюр'; Impact = 'none'; Default = $true
       Desc = 'Превью картинок и видео в Проводнике. Пересоздастся сам при просмотре папок (занятые файлы пропускаются).'
       Paths = { Get-ChildItem "$Lad\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } } }
    @{ Id = 'logs'; Title = 'Журналы установки Windows'; Impact = 'none'; Default = $true; MinAge = 24
       Desc = 'Журналы CBS и DISM от прошлых установок обновлений.'
       Paths = { "$env:windir\Logs\CBS", "$env:windir\Logs\DISM" } }
    @{ Id = 'dumps'; Title = 'Дампы памяти после сбоев'; Impact = 'minor'; Default = $true
       Desc = 'Файлы для разбора синих экранов и вылетов программ.'
       Warn = 'Не получится разобрать причину уже случившихся сбоев'
       Paths = { "$env:windir\Minidump", "$env:windir\MEMORY.DMP", "$Lad\CrashDumps" } }
    @{ Id = 'shaders'; Title = 'Кэш шейдеров видеокарты'; Impact = 'minor'; Default = $false
       Desc = 'Скомпилированные шейдеры игр DirectX, NVIDIA и AMD. Помогает при графических глюках после обновления драйвера.'
       Warn = 'Первые запуски игр будут подтормаживать, пока кэш не соберётся заново'
       Paths = { "$Lad\D3DSCache", "$Lad\NVIDIA\DXCache", "$Lad\NVIDIA\GLCache", "$Lad\AMD\DxCache", "$Lad\AMD\GLCache" } }
    @{ Id = 'browsers'; Title = 'Кэш браузеров'; Impact = 'minor'; Default = $false
       Desc = 'Кэш Chrome, Edge, Яндекс Браузера, Brave и Firefox. Пароли, история, вкладки и вход на сайты остаются.'
       Warn = 'Закройте браузеры перед очисткой. Сайты в первый раз будут открываться медленнее'
       Paths = {
           foreach ($b in 'Google\Chrome', 'Microsoft\Edge', 'Yandex\YandexBrowser', 'BraveSoftware\Brave-Browser') {
               Get-ChildItem "$Lad\$b\User Data" -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\Cache", "$($_.FullName)\Code Cache", "$($_.FullName)\GPUCache" }
           }
           Get-ChildItem "$Lad\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\cache2" }
       } }
    @{ Id = 'recycle'; Title = 'Корзина'; Impact = 'breaks'; Default = $false
       Desc = 'Все файлы в корзине на всех дисках.'
       Warn = 'Удалённые файлы нельзя будет восстановить'
       Paths = { }
       Size = { $sum = [long]0; foreach ($i in (New-Object -ComObject Shell.Application).NameSpace(10).Items()) { $sum += [long]$i.ExtendedProperty('Size') }; $sum }
       Clean = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } }
    @{ Id = 'winsxs'; Title = 'Старые версии компонентов Windows'; Impact = 'minor'; Default = $false
       Desc = 'Удаляет заменённые обновлениями версии системных файлов (DISM /StartComponentCleanup). Займёт 5–15 минут, размер станет известен после очистки.'
       Warn = 'Уже установленные обновления нельзя будет удалить'
       Paths = { }; Size = { $null }
       Clean = {
           $p = Start-Process dism.exe -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' -WindowStyle Hidden -PassThru
           while (-not $p.HasExited) { if (Get-Command Pump -ErrorAction SilentlyContinue) { Pump }; Start-Sleep -Milliseconds 300 }
       } }
)
#endregion
