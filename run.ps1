# OknoTune launcher (ASCII only: irm | iex chokes on the UTF-8 BOM that OknoTune.ps1 needs)
#   irm https://raw.githubusercontent.com/equ1pt/OknoTune/main/run.ps1 | iex
# Downloads OknoTune.ps1 from the latest release to %TEMP%\OknoTune and starts it as administrator.
# Latest release, not main: users get a released version, and GitHub counts each launch as an asset download.
& {
    $url = 'https://github.com/equ1pt/OknoTune/releases/latest/download/OknoTune.ps1'
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
