param([string]$Exe)
$ErrorActionPreference = 'Stop'
$folder = Join-Path $env:RUNNER_TEMP 'groundsurf-windows-checks'
New-Item -ItemType Directory -Force $folder | Out-Null
$report = Join-Path $folder 'renderer-check.json'
$p = Start-Process $Exe -ArgumentList @('--smoke-test',('"'+$report+'"')) -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(65)
$memory = [System.Collections.Generic.List[object]]::new()
while (!$p.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    $tree = Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId
    $ids = [System.Collections.Generic.HashSet[int]]::new(); [void]$ids.Add($p.Id)
    do {
        $added = $false
        foreach ($entry in $tree) {
            if ($ids.Contains([int]$entry.ParentProcessId) -and $ids.Add([int]$entry.ProcessId)) { $added = $true }
        }
    } while ($added)
    $private = 0L; $working = 0L; $count = 0
    foreach ($id in $ids) {
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc) { $private += $proc.PrivateMemorySize64; $working += $proc.WorkingSet64; $count++ }
    }
    if ($count) { $memory.Add([PSCustomObject]@{processes=$count; privateBytesMiB=[Math]::Round($private/1MB,1); summedWorkingSetMiB=[Math]::Round($working/1MB,1)}) }
    Start-Sleep -Milliseconds 250
}
if (!$p.HasExited) { $p.Kill(); throw 'Renderer test timed out' }
if ($p.ExitCode -ne 0) { if (Test-Path $report) { Get-Content $report }; throw "Renderer test exit $($p.ExitCode)" }
if (!(Test-Path $report)) { throw 'Renderer test did not write its report' }
$result = Get-Content $report -Raw | ConvertFrom-Json
if ($result.result -ne 'PASS') { Get-Content $report; throw 'Renderer/lifecycle validation failed' }
$result | Add-Member -NotePropertyName memorySamples -NotePropertyValue @($memory.ToArray())
$result | Add-Member -NotePropertyName memoryNote -NotePropertyValue 'Brief startup/renderer-check samples of the app process tree. Private Bytes is committed private memory, not physical footprint; summed working sets can double-count shared pages. GPU device memory is excluded. Not a steady-state or overnight benchmark.'
$result | ConvertTo-Json -Depth 8 | Set-Content $report
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
