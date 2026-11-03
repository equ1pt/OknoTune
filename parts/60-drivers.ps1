#region Driver info
function Get-AgeMonths($d) { if ($d) { [int][Math]::Floor(((Get-Date) - $d).TotalDays / 30.4) } }
function Format-Age($d) {
    $m = Get-AgeMonths $d
    if ($null -eq $m) { return '' }
    if ($m -lt 1) { 'меньше месяца назад' } elseif ($m -lt 12) { "$m мес. назад" } else { "$([Math]::Floor($m / 12)) г. назад" }
}
function Get-SearchUrl([string]$q) { 'https://www.google.com/search?q=' + [Uri]::EscapeDataString($q) }
# driver.ru finds drivers only by "BUS\VEN_xxxx&DEV_xxxx" (or HDAUDIO\FUNC_xx&VEN&DEV, USB\VID&PID) without SUBSYS/REV
function Get-HwId($ids) {
    foreach ($i in @($ids)) {
        $m = [regex]::Match("$i", '^[^\\]+\\(?:FUNC_\w+&)?(?:VEN|VID)_\w{4}&(?:DEV|PID)_\w{4}')
        if ($m.Success) { return $m.Value.ToUpper() }
    }
}
function Get-FindButtons([string]$hw, [string]$name) {
    $google = @('Поиск в Google', (Get-SearchUrl $(if ($hw) { "$hw driver" } else { "$name driver" })))
    # driver.ru — неофициальный каталог: подпись говорит об этом прямо, сайт производителя надёжнее
    if ($hw) { @(@('driver.ru (неофициальный)', ('https://driver.ru/Search/' + [Uri]::EscapeDataString($hw))), $google) } else { @(, $google) }
}
$VendorSites = @(
    @{ Rx = 'ASUS'; Name = 'ASUS'; Url = 'https://www.asus.com/ru/support/download-center/'; Site = 'asus.com' }
    @{ Rx = 'Micro-Star|^MSI'; Name = 'MSI'; Url = 'https://www.msi.com/support/download'; Site = 'msi.com' }
    @{ Rx = 'Gigabyte'; Name = 'Gigabyte'; Url = 'https://www.gigabyte.com/ru/Support'; Site = 'gigabyte.com' }
    @{ Rx = 'ASRock'; Name = 'ASRock'; Url = 'https://www.asrock.com/support/index.asp'; Site = 'asrock.com' }
    @{ Rx = 'Lenovo'; Name = 'Lenovo'; Url = 'https://pcsupport.lenovo.com/'; Site = 'lenovo.com' }
    @{ Rx = 'HP|Hewlett'; Name = 'HP'; Url = 'https://support.hp.com/ru-ru/drivers'; Site = 'hp.com' }
    @{ Rx = 'Dell'; Name = 'Dell'; Url = 'https://www.dell.com/support/home/ru-ru'; Site = 'dell.com' }
    @{ Rx = 'Acer'; Name = 'Acer'; Url = 'https://www.acer.com/ru-ru/support'; Site = 'acer.com' }
    @{ Rx = 'Huawei'; Name = 'Huawei'; Url = 'https://consumer.huawei.com/ru/support/'; Site = 'huawei.com' }
    @{ Rx = 'Samsung'; Name = 'Samsung'; Url = 'https://www.samsung.com/ru/support/'; Site = 'samsung.com' }
)
$GpuSites = @{
    NVIDIA = @(@('Скачать драйвер NVIDIA', 'https://www.nvidia.com/ru-ru/geforce/drivers/'), @('NVIDIA App', 'https://www.nvidia.com/ru-ru/software/nvidia-app/'))
    AMD    = @(, @('Скачать драйвер AMD', 'https://www.amd.com/ru/support/download/drivers.html'))
    Intel  = @(, @('Intel Driver & Support Assistant', 'https://www.intel.com/content/www/us/en/support/detect.html'))
}
# Returns a list of cards: @{ Kind; Title; Details; Date; Fresh (months); Bad; Buttons = @(@(text, url)) }
# $sync (необязательно) — прогресс для фонового запуска: Value 0..100, Text
function Get-DriverInfo($sync) {
    function Step([int]$v, [string]$t) { if ($sync) { $sync.Value = $v; $sync.Text = $t } }
    $cards = New-Object System.Collections.Generic.List[object]
    Step 5 'Видеокарта…'
    foreach ($g in Get-CimInstance Win32_VideoController) {
        $vendor = switch -Regex ($g.PNPDeviceID) { 'VEN_10DE' { 'NVIDIA' } 'VEN_1002' { 'AMD' } 'VEN_8086' { 'Intel' } default { $null } }
        if (-not $vendor -and $g.Name -notmatch 'Basic Display|Базовый видеоадаптер') { continue }   # skip virtual adapters
        $basic = $g.Name -match 'Basic Display|Базовый видеоадаптер'
        $btns = $(if ($vendor) { $GpuSites[$vendor] } else { Get-FindButtons (Get-HwId $g.PNPDeviceID) $g.Name })
        $cards.Add(@{ Kind = 'Видеокарта'; Title = $g.Name; Date = $g.DriverDate; Fresh = 4; Bad = $basic; Buttons = $btns
            Details = $(if ($basic) { 'Драйвер видеокарты не установлен: работает стандартный драйвер Windows.' } else { "Драйвер $($g.DriverVersion)" }) })
    }
    Step 20 'Материнская плата и BIOS…'
    $cs = Get-CimInstance Win32_ComputerSystem; $bb = Get-CimInstance Win32_BaseBoard; $bios = Get-CimInstance Win32_BIOS
    $generic = 'System manufacturer|To Be Filled|Default string|O\.E\.M|^$'
    $isLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($isLaptop -and $cs.Manufacturer -notmatch $generic) { $mf = $cs.Manufacturer; $model = $cs.Model; $kind = 'Ноутбук' }
    else { $mf = $bb.Manufacturer; $model = $bb.Product; $kind = 'Материнская плата' }
    $v = $VendorSites | Where-Object { $mf -match $_.Rx } | Select-Object -First 1
    $btns = @(, @("Драйверы для $model", (Get-SearchUrl $(if ($v) { "site:$($v.Site) $model support drivers" } else { "$mf $model drivers" }))))
    if ($v) { $btns += , @("Сайт поддержки $($v.Name)", $v.Url) }
    $cards.Add(@{ Kind = $kind; Title = "$mf $model".Trim(); Date = $bios.ReleaseDate; Fresh = 24; Buttons = $btns
        Details = "BIOS $($bios.SMBIOSBIOSVersion). Звук, сеть, USB и BIOS берите на странице этой модели." })
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    if ($cpu -match 'AMD') { $cards.Add(@{ Kind = 'Чипсет'; Title = "Чипсет AMD ($($cpu.Trim()))"; Details = 'Драйвер чипсета AMD улучшает работу планировщика Ryzen и энергосбережения.'; Buttons = @(, @('Скачать драйвер чипсета AMD', 'https://www.amd.com/ru/support/download/drivers.html')) }) }
    elseif ($cpu -match 'Intel') { $cards.Add(@{ Kind = 'Чипсет'; Title = "Чипсет Intel ($($cpu.Trim()))"; Details = 'Intel Driver & Support Assistant сам найдёт драйверы чипсета и других устройств Intel.'; Buttons = @(, @('Intel Driver & Support Assistant', 'https://www.intel.com/content/www/us/en/support/detect.html')) }) }
    Step 40 'Сеть и звук…'
    $skip = 'Microsoft|VMware|VirtualBox|Hyper-V|Virtual|TAP-|Wintun|-tun|Tunnel|WireGuard|OpenVPN|Npcap|WAN Miniport|SoftEther|NVIDIA High Definition|AMD High Definition|Steam|VB-Audio|Bluetooth|Remote|Loopback'
    Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET' OR DeviceClass='MEDIA'" -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceName -and $_.DriverProviderName -notmatch 'Microsoft' -and "$($_.DeviceName) $($_.DriverProviderName)" -notmatch $skip } |
        Sort-Object DeviceName -Unique | Select-Object -First 6 | ForEach-Object {
            $hw = Get-HwId @($_.HardWareID, $_.DeviceID)
            $cards.Add(@{ Kind = $(if ($_.DeviceClass -eq 'NET') { 'Сеть' } else { 'Звук' }); Title = $_.DeviceName; Date = $_.DriverDate; Fresh = 24
                Details = "$($_.DriverProviderName), драйвер $($_.DriverVersion)$(if ($hw) { ". ID: $hw" })"; Buttons = (Get-FindButtons $hw $_.DeviceName) })
        }
    # code 22 = disabled on purpose, not broken
    Step 75 'Устройства с ошибками…'
    $bad =@(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 22' -ErrorAction SilentlyContinue)
    foreach ($d in $bad) {
        $hw = Get-HwId @($d.HardwareID + $d.DeviceID)
        $why = $(if ($d.ConfigManagerErrorCode -eq 28) { 'Драйвер не установлен.' } else { "Ошибка устройства (код $($d.ConfigManagerErrorCode))." })
        $cards.Add(@{ Kind = 'Устройство с ошибкой'; Title = $(if ($d.Name) { $d.Name } else { $d.DeviceID }); Bad = $true
            Details = "$why $(if ($hw) { "ID: $hw" })"; Buttons = (Get-FindButtons $hw $d.Name) })
    }
    if (-not $bad.Count) { $cards.Add(@{ Kind = 'Проверка устройств'; Title = 'Все устройства работают'; Details = 'В Диспетчере устройств нет устройств без драйвера или с ошибкой.'; Buttons = @() }) }
    $cards
}
# Карточки «Отключённые устройства» и «Лишние драйверы» для раздела «Очистка»
function Get-DevCleanCards($sync) {
    function Step([int]$v, [string]$t) { if ($sync) { $sync.Value = $v; $sync.Text = $t } }
    $cards = New-Object System.Collections.Generic.List[object]
    Step 10 'Отключённые устройства…'
    $ghosts = @(Get-GhostDevices)
    $cards.Add(@{ Kind = 'Отключённые устройства'; Title = $(if ($ghosts.Count) { "Найдено: $($ghosts.Count)" } else { 'Лишних записей нет' }); Action = 'ghosts'; Items = $ghosts; Buttons = @()
        Details = 'Флешки, мониторы, телефоны и другие устройства, которые когда-то подключались. Их записи можно убрать: при новом подключении Windows создаст запись заново.' })
    Step 50 'Хранилище драйверов…'
    $pkgs = @(try { Get-StaleDrivers } catch {})   # без DISM карточка просто покажет «нет»
    $old = @($pkgs | Where-Object { $_.Old }).Count
    $cards.Add(@{ Kind = 'Лишние драйверы'; Title = $(if ($pkgs.Count) { "Найдено: $($pkgs.Count), из них старых версий: $old" } else { 'Лишних драйверов нет' }); Action = 'drivers'; Items = $pkgs; Buttons = @()
        Details = 'Старые версии драйверов и драйверы устройств, которых сейчас нет. Используемые драйверы Windows удалить не даст.' })
    $cards
}
# Записи устройств, которых сейчас нет в компьютере (как Device Cleanup)
function Get-GhostDevices {
    Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { -not $_.Present } | Sort-Object Class, FriendlyName | ForEach-Object {
        @{ Id = "$($_.InstanceId)"; Name = $(if ($_.FriendlyName) { "$($_.FriendlyName)" } else { "$($_.InstanceId)" }); Class = "$($_.Class)" }
    }
}
# Пакеты в хранилище драйверов, которые не использует ни одно подключённое устройство (как DriverStoreExplorer).
# Old = есть более новая версия того же драйвера. Последнюю версию Extension/SoftwareComponent/Printer, фильтров (HSM)
# и звуковых эффектов (APO) не предлагаем: они работают не через устройство, по ним не видно, нужны ли они.
function Get-StaleDrivers {
    $used = @{}
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | ForEach-Object { if ($_.InfName) { $used["$($_.InfName)".ToLower()] = $true } }
    Get-WindowsDriver -Online -ErrorAction Stop | Group-Object { "$(Split-Path $_.OriginalFileName -Leaf)|$($_.ProviderName)|$($_.ClassName)" } | ForEach-Object {
        $sorted = @($_.Group | Sort-Object { try { [version]$_.Version } catch { [version]'0.0' } } -Descending)
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $p = $sorted[$i]
            if ($used["$($p.Driver)".ToLower()]) { continue }
            if ($i -eq 0 -and $p.ClassName -in 'Extension', 'SoftwareComponent', 'Printer', 'HSM', 'AudioProcessingObject') { continue }
            @{ Inf = "$($p.Driver)"; Name = "$(Split-Path $p.OriginalFileName -Leaf)"; Provider = "$($p.ProviderName)"; Class = "$($p.ClassName)"
                Version = "$($p.Version)"; Date = $p.Date; Old = $i -gt 0 }
        }
    } | Sort-Object { -not $_.Old }, Provider, Name
}
#endregion
