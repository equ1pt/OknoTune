<#
  Сборка OknoTune.ps1 из parts/*.ps1 (склеиваются по порядку имён).
  Правьте файлы в parts/, затем запустите:  powershell -ExecutionPolicy Bypass -File build.ps1
#>
param([string]$Out = "$PSScriptRoot\OknoTune.ps1")

$parts = Get-ChildItem -LiteralPath "$PSScriptRoot\parts" -Filter '*.ps1' | Sort-Object Name
if (-not $parts) { throw 'В parts/ нет файлов' }
$chunks = New-Object System.Collections.Generic.List[string]
foreach ($p in $parts) {
    $t = [IO.File]::ReadAllText($p.FullName)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }   # снять BOM части
    $chunks.Add($t.TrimEnd("`r", "`n", ' ', "`t"))
}
[IO.File]::WriteAllText($Out, (($chunks -join "`n`n") + "`n"), (New-Object Text.UTF8Encoding $true))   # UTF-8 с BOM, LF
Write-Host "Собрано $Out из $($parts.Count) частей"

# Логотип: New-Logo берётся из parts/70-ui-base.ps1, чтобы рисунок был один на всё
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$ast = [Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\parts\70-ui-base.ps1", [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in 'New-Xaml', 'New-Logo' }, $true)) {
    . ([scriptblock]::Create($f.Extent.Text))
}
function Get-Png([int]$size) {
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create((New-Logo $size)))
    $ms = New-Object IO.MemoryStream; $enc.Save($ms); , $ms.ToArray()   # запятая: вернуть byte[] целиком, а не поток байтов
}
[IO.File]::WriteAllBytes("$PSScriptRoot\docs\logo.png", (Get-Png 128))
# .ico с PNG внутри: заголовок, таблица размеров, затем сами картинки
$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$pngs = foreach ($s in $sizes) { , [byte[]](Get-Png $s) }
$ico = Join-Path $env:TEMP 'OknoTune.ico'
$w = New-Object IO.BinaryWriter ([IO.File]::Create($ico))
try {
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $d = [byte]($sizes[$i] % 256)   # 0 значит 256
        $w.Write($d); $w.Write($d); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $w.Write($p) }
} finally { $w.Close() }

# Лаунчер OknoTune.exe: вшитый скрипт + проверка новой версии на GitHub (launcher/OknoTune.cs)
$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
$exe = [IO.Path]::ChangeExtension($Out, '.exe')
if (-not (Test-Path -LiteralPath $csc)) { Write-Warning "Нет $csc, OknoTune.exe не собран"; return }
& $csc /nologo /target:winexe /optimize "/out:$exe" "/win32manifest:$PSScriptRoot\launcher\OknoTune.manifest" "/win32icon:$ico" `
    "/resource:$Out,OknoTune.ps1" /r:System.Windows.Forms.dll "$PSScriptRoot\launcher\OknoTune.cs"
if ($LASTEXITCODE -ne 0) { throw "csc.exe завершился с кодом $LASTEXITCODE" }
Write-Host "Собрано $exe"
