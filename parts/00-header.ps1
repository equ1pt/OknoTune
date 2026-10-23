<#
  OknoTune — настройка Windows с откатом.
  Запуск: OknoTune.cmd (или powershell -ExecutionPolicy Bypass -File OknoTune.ps1)
  -Selftest                проверить состояние без окна и без изменений
  -Snapshot a.png [-View]  отрисовать экран в PNG и выйти (home|wizard|review|list|history|clean|startup|drivers|apps|fixes|welcome), без изменений
#>
param([switch]$Selftest, [string]$Snapshot, [string]$View = 'home')

$script:Version = '0.1.5'   # меняется при каждом релизе (тег vX.Y.Z)
$ErrorActionPreference = 'Continue'
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin -and -not $Selftest -and -not $Snapshot) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    exit
}

$script:DataDir = Join-Path $env:LOCALAPPDATA 'OknoTune'
New-Item -ItemType Directory -Force $script:DataDir | Out-Null
$script:LogFile = Join-Path $script:DataDir 'log.txt'
$script:RebootFile = Join-Path $script:DataDir 'reboot-pending.txt'
