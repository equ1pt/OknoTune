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
