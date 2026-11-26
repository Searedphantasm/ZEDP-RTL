#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$BinaryDir,
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Iscc = 'iscc.exe'
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a stable version' }
$project = Split-Path $PSScriptRoot
$cache = Join-Path $WorkDir "package-$Version"
$null = New-Item -ItemType Directory -Force $cache, $OutDir
$cache = (Resolve-Path -LiteralPath $cache).Path
$out = (Resolve-Path -LiteralPath $OutDir).Path
$payload = Join-Path $cache 'payload'
$null = New-Item -ItemType Directory -Force $payload, "$payload\bin", "$payload\x64", "$payload\licenses"

function Get-VerifiedFile($Url, $Hash, $Destination) {
    if ($Hash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Missing SHA-256 from release metadata' }
    if ((Test-Path -LiteralPath $Destination) -and (Get-FileHash -LiteralPath $Destination).Hash -eq $Hash) { return }
    $partial = "$Destination.$([guid]::NewGuid().ToString('N')).part"
    curl.exe --fail --location --silent --show-error --retry 2 --output $partial $Url
    if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $partial).Hash -ne $Hash) { throw "Download or hash check failed for $Url" }
    [IO.File]::Move($partial, $Destination, $true)
}

# Use the exact console host and graphics runtimes shipped with this upstream version.
$release = Invoke-RestMethod "https://api.github.com/repos/zed-industries/zed/releases/tags/v$Version"
$asset = @($release.assets | Where-Object name -eq 'Zed-x86_64.exe')
if ($asset.Count -ne 1 -or $asset[0].digest -notlike 'sha256:*') { throw 'Official x64 installer missing' }
$setup = Join-Path $cache 'upstream.exe'
Get-VerifiedFile $asset[0].browser_download_url $asset[0].digest.Substring(7) $setup
$unpackerZip = Join-Path $cache 'unpacker.zip'
Get-VerifiedFile 'https://raw.githubusercontent.com/jrathlev/InnoUnpacker-Windows-GUI/5410e03e6ad409ac982ca9cb2365db815a8b53fb/innounp-2/bin/innounp-2.zip' '078ddb005aa17e669f0b5545980bff92200f7401418174172dca0d75f9e5d8f0' $unpackerZip
Expand-Archive -LiteralPath $unpackerZip -DestinationPath "$cache\unpacker" -Force
$unpacker = (Get-ChildItem -LiteralPath "$cache\unpacker" -Recurse -File -Filter innounp.exe).FullName
$unpacked = Join-Path $cache 'runtime'
& $unpacker -x -b -q -y "-d$unpacked" $setup '*conpty.dll' '*OpenConsole.exe' '*amd_ags_x64.dll'
if ($LASTEXITCODE -ne 0) { throw 'Could not extract upstream runtimes' }
foreach ($name in @('conpty.dll', 'amd_ags_x64.dll', 'OpenConsole.exe')) {
    $files = @(Get-ChildItem -LiteralPath $unpacked -Recurse -File -Filter $name | Where-Object { $name -ne 'OpenConsole.exe' -or $_.Directory.Name -eq 'x64' })
    if ($files.Count -ne 1) { throw "Expected one x64 $name" }
    $folder = if ($name -eq 'OpenConsole.exe') { "$payload\x64" } else { $payload }
    Copy-Item -LiteralPath $files[0].FullName -Destination $folder -Force
}
Copy-Item -LiteralPath "$BinaryDir\zedp-rtl.exe" -Destination "$payload\ZEDP-RTL.exe" -Force
Copy-Item -LiteralPath "$BinaryDir\cli.exe" -Destination "$payload\bin\zedp.exe" -Force
Copy-Item -LiteralPath "$project\LICENSE", "$project\LICENSE-APACHE", "$project\NOTICE.md" -Destination "$payload\licenses" -Force
Copy-Item -LiteralPath "$SourceDir\assets\themes\LICENSES" -Destination "$payload\licenses\themes.txt" -Force
Copy-Item -LiteralPath "$SourceDir\assets\icons\LICENSES" -Destination "$payload\licenses\icons.txt" -Force
& $Iscc "/DProductVersion=$Version" "/DPayload=$payload" "/O$out" "$PSScriptRoot\windows.iss"
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
$installer = Get-Item -LiteralPath "$out\ZEDP-RTL-$Version-x64.exe"
$sha = (Get-FileHash -LiteralPath $installer.FullName).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$($installer.FullName).sha256", "$sha  $($installer.Name)`n")
Write-Output $installer.FullName
