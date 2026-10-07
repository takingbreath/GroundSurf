param([string]$Exe)
$ErrorActionPreference = 'Stop'
$folder = Join-Path $env:RUNNER_TEMP 'groundsurf-windows-checks'
New-Item -ItemType Directory -Force $folder | Out-Null
$report = Join-Path $folder 'renderer-check.json'
$p = Start-Process $Exe -ArgumentList @('--smoke-test',('"'+$report+'"')) -PassThru
if (!$p.WaitForExit(65000)) { $p.Kill(); throw 'Renderer test timed out' }
if ($p.ExitCode -ne 0) { if (Test-Path $report) { Get-Content $report }; throw "Renderer test exit $($p.ExitCode)" }
if (!(Test-Path $report)) { throw 'Renderer test did not write its report' }
$result = Get-Content $report -Raw | ConvertFrom-Json
if ($result.result -ne 'PASS') { Get-Content $report; throw 'Renderer/lifecycle validation failed' }
Get-Content $report
Copy-Item $report (Join-Path $PSScriptRoot '../dist/windows-validation.json')
Copy-Item (Join-Path $folder 'renderer-check.png') (Join-Path $PSScriptRoot '../dist/windows-renderer.png')
$setup = Join-Path $PSScriptRoot '../dist/GroundSurf-Windows-0.1.0-Setup-x64.exe'
$install = Join-Path $folder 'installed'
$installer = Start-Process $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$install+'"'),('/LOG="'+(Join-Path $folder 'setup.log')+'"')) -Wait -PassThru
if ($installer.ExitCode -ne 0) { Get-Content (Join-Path $folder 'setup.log') -ErrorAction SilentlyContinue; throw 'Installer failed' }
if (!(Test-Path (Join-Path $install 'GroundSurf.exe'))) { throw 'Installed EXE missing' }
$uninstall = Start-Process (Join-Path $install 'unins000.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -Wait -PassThru
if ($uninstall.ExitCode -ne 0 -or (Test-Path (Join-Path $install 'GroundSurf.exe'))) { throw 'Uninstaller failed' }
Write-Host 'PASS: Windows generation, scrolling, pause/sleep rules, setup and uninstall'
