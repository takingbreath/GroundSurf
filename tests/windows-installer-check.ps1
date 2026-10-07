$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '../docs/install.ps1'
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$source = Get-Content $script -Raw
$script:executed = $false
function Start-Process {
    param([string]$FilePath,[string[]]$ArgumentList,[switch]$Wait,[switch]$PassThru)
    if ($FilePath.EndsWith('.exe')) {
        if ((Get-FileHash $FilePath -Algorithm SHA256).Hash -ne 'e543dcf9bd0bc2bcd130f9a7588c43fb34cf39a20cfe10d75b4ed0934f009dbe') { throw 'Setup payload changed' }
        if ((Get-Content -LiteralPath $FilePath -Stream Zone.Identifier) -notcontains 'ZoneId=3') { throw 'Internet origin marker missing' }
        if ('/NORESTART' -notin $ArgumentList -or '/SILENT' -notin $ArgumentList) { throw 'Wrong installer arguments' }
        $script:executed = $true
        return [PSCustomObject]@{ExitCode=0}
    }
}
Invoke-Expression $source
if (!$script:executed) { throw 'Installer was not invoked after verification' }
# Corrupted download must abort before any setup execution.
$script:executed = $false
function Invoke-WebRequest { param([switch]$UseBasicParsing,[string]$Uri,[string]$OutFile); Set-Content $OutFile 'wrong payload' }
$failed = $false
try { Invoke-Expression $source } catch { if ($_.Exception.Message -match 'verification failed') { $failed = $true } else { throw } }
if (!$failed -or $script:executed) { throw 'Checksum failure did not stop installation' }
Write-Host 'PASS: public download, pinned checksum, Windows origin marker, installer flags and corrupt-download rejection'
