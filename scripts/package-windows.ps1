param([string]$InnoCompiler = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$package = Join-Path $dist 'GroundSurf-Windows-0.1.0-x64'
New-Item -ItemType Directory -Force $dist | Out-Null
python (Join-Path $root 'Sources/assemble.py')
if ($LASTEXITCODE -ne 0) { throw 'HTML assembly failed' }
dotnet build (Join-Path $root 'Windows/GroundSurf.csproj') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Windows compilation failed' }
if (Test-Path $package) { Remove-Item -Recurse -Force $package }
New-Item -ItemType Directory -Force $package | Out-Null
$compiled = Join-Path $root 'Windows/bin/Release/net48'
Get-ChildItem $compiled -File | Where-Object { $_.Extension -notin '.xml','.pdb' } | Copy-Item -Destination $package
$loader = Join-Path $compiled 'runtimes/win-x64/native'
if (Test-Path $loader) {
    $dest = Join-Path $package 'runtimes/win-x64/native'
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item (Join-Path $loader '*') $dest
}
Copy-Item (Join-Path $root 'Windows/Install.txt') (Join-Path $package 'Read Me.txt')
Copy-Item (Join-Path $root 'Windows/THIRD-PARTY-NOTICES.txt') $package
Copy-Item (Join-Path $root 'Windows/WebView2-SDK-LICENSE.txt') $package
$zip = Join-Path $dist 'GroundSurf-Windows-0.1.0-Portable-x64.zip'
Compress-Archive -Path $package -DestinationPath $zip -Force
if (!$InnoCompiler) {
    $compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($compiler) { $InnoCompiler = $compiler.Source }
    else { $InnoCompiler = '${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe'.Replace('${env:ProgramFiles(x86)}',${env:ProgramFiles(x86)}) }
}
if (!(Test-Path $InnoCompiler)) { throw 'Set -InnoCompiler to your Inno Setup ISCC.exe path.' }
& $InnoCompiler (Join-Path $root 'Windows/installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
$files = @($zip, (Join-Path $dist 'GroundSurf-Windows-0.1.0-Setup-x64.exe'))
$lines = foreach ($file in $files) { $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower(); "$hash  $(Split-Path $file -Leaf)" }
[IO.File]::WriteAllLines((Join-Path $dist 'WINDOWS-SHA256SUMS'),$lines,[Text.UTF8Encoding]::new($false))
$size = ($files | ForEach-Object { [PSCustomObject]@{ name=(Split-Path $_ -Leaf); bytes=(Get-Item $_).Length } })
$size | ConvertTo-Json | Set-Content (Join-Path $dist 'windows-package-sizes.json')
