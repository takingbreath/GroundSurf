# GroundSurf Windows installer. Source: https://github.com/takingbreath/GroundSurf
# Downloads the published release and verifies its pinned SHA-256.
& {
    $ErrorActionPreference = 'Stop'
    if ($env:OS -ne 'Windows_NT') { throw 'GroundSurf for Windows requires Windows.' }
    $gsArchitecture = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $gsArchitecture = $env:PROCESSOR_ARCHITEW6432 }
    if ($gsArchitecture -ne 'AMD64') { throw 'This preview supports x64 Windows PCs.' }

    $gsUrl = 'https://github.com/takingbreath/GroundSurf/releases/download/windows-v0.1.0/GroundSurf-Windows-0.1.0-Setup-x64.exe'
    $gsExpected = 'e543dcf9bd0bc2bcd130f9a7588c43fb34cf39a20cfe10d75b4ed0934f009dbe'
    $gsSetup = Join-Path $env:TEMP ('GroundSurf-' + [guid]::NewGuid() + '.exe')
    try {
        Write-Host 'Downloading GroundSurf for Windows...'
        Invoke-WebRequest -UseBasicParsing -Uri $gsUrl -OutFile $gsSetup
        if ((Get-FileHash -LiteralPath $gsSetup -Algorithm SHA256).Hash -ne $gsExpected) {
            throw 'Download verification failed. Nothing was installed.'
        }
        # Retain Windows assessment of this internet download; do not unblock it.
        Set-Content -LiteralPath $gsSetup -Stream Zone.Identifier -Value @('[ZoneTransfer]', 'ZoneId=3', ('HostUrl=' + $gsUrl))
        Write-Host 'Download verified. Installing GroundSurf...'
        $gsInstall = Start-Process -FilePath $gsSetup -ArgumentList @('/SILENT','/SP-','/NORESTART') -Wait -PassThru
        if ($gsInstall.ExitCode -ne 0) {
            throw ('Installation did not complete (code ' + $gsInstall.ExitCode + '). Follow any setup or WebView2 prompt, then retry.')
        }
        Write-Host 'GroundSurf is installed.'
        $gsShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'GroundSurf.lnk'
        if (Test-Path -LiteralPath $gsShortcut) { Start-Process -FilePath $gsShortcut }
        else { Write-Host 'Open GroundSurf from your Start menu.' }
    }
    finally {
        if (Test-Path -LiteralPath $gsSetup) { Remove-Item -LiteralPath $gsSetup -Force }
    }
}
