# OknoTune launcher (ASCII only: irm | iex chokes on the UTF-8 BOM that OknoTune.ps1 needs)
#   irm https://raw.githubusercontent.com/equ1pt/OknoTune/main/run.ps1 | iex
# Downloads OknoTune.ps1 to %TEMP%\OknoTune and starts it as administrator in its own window.
& {
    $url = 'https://raw.githubusercontent.com/equ1pt/OknoTune/main/OknoTune.ps1'
    $dir = Join-Path $env:TEMP 'OknoTune'
    $file = Join-Path $dir 'OknoTune.ps1'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Force $dir | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $file -ErrorAction Stop
        Start-Process powershell.exe -Verb RunAs -ErrorAction Stop -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$file`""
    } catch {
        Write-Host "OknoTune: $($_.Exception.Message)" -ForegroundColor Red
    }
}
