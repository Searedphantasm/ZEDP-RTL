#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Tag,
    [string]$WorkDir = (Join-Path $PSScriptRoot 'build'),
    [string]$OutDir = (Join-Path $PSScriptRoot 'dist'),
    [string]$SourceDir,
    [string]$ReleaseRepository,
    [string]$Iscc = 'iscc.exe',
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$pin = Get-Content -LiteralPath "$PSScriptRoot\upstream.json" -Raw | ConvertFrom-Json
if (!$Tag) { $Tag = $pin.tag }
if ($Tag -notmatch '^v(\d+\.\d+\.\d+)$') { throw "Expected a stable Zed release tag, got $Tag" }
$version = $Matches[1]
$patch = Join-Path $PSScriptRoot 'patches\zedp-rtl.patch'
$null = New-Item -ItemType Directory -Force $WorkDir
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
$OutDir = [IO.Path]::GetFullPath($OutDir, (Get-Location).Path)
if (!$SourceDir) { $SourceDir = Join-Path $WorkDir "zed-$Tag" }
if (!(Test-Path -LiteralPath $SourceDir)) {
    git -c core.longpaths=true -c core.autocrlf=false clone --quiet --depth 1 --branch $Tag https://github.com/zed-industries/zed.git $SourceDir
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone the upstream release' }
}
$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
$upstreamCommit = git -C $SourceDir rev-parse HEAD
$tagCommit = git -C $SourceDir rev-parse --verify "refs/tags/$Tag^{commit}"
if ($LASTEXITCODE -ne 0 -or $upstreamCommit -ne $tagCommit) { throw "Checkout is not at $Tag" }
if ($Tag -eq $pin.tag -and $upstreamCommit -ne $pin.commit) { throw 'Pinned upstream commit mismatch' }
$previousIndex = $env:GIT_INDEX_FILE
$index = Join-Path $WorkDir "source-$([guid]::NewGuid()).index"
try {
    $env:GIT_INDEX_FILE = $index
    git -C $SourceDir read-tree $upstreamCommit
    if ($LASTEXITCODE -ne 0) { throw 'Failed to initialize the source tree' }
    git -C $SourceDir apply --cached $patch
    if ($LASTEXITCODE -ne 0) { throw "RTL port needs review for $Tag" }
    $tree = git -C $SourceDir write-tree
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the patched source tree' }
} finally {
    $env:GIT_INDEX_FILE = $previousIndex
    if (Test-Path -LiteralPath $index) { [IO.File]::Delete($index) }
}
if (git -C $SourceDir status --porcelain --untracked-files=no -- crates) {
    git -C $SourceDir diff --quiet $tree -- crates
    if ($LASTEXITCODE -ne 0) { throw 'The checkout differs from this upstream release plus the project patch' }
} else {
    git -C $SourceDir apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw "RTL port needs review for $Tag" }
    git -C $SourceDir apply $patch
    if ($LASTEXITCODE -ne 0) { throw 'Patch application failed' }
}
if ($PrepareOnly) { Write-Host "Prepared $Tag at $upstreamCommit"; return }

if ($ReleaseRepository -and $ReleaseRepository -notmatch '^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$') { throw 'Expected an owner/repository name' }
$env:ZEDP_RELEASE_REPO = if ($ReleaseRepository) { $ReleaseRepository } else { $null }
$env:ZED_RELEASE_CHANNEL = 'stable'
$env:RELEASE_CHANNEL = 'stable'
$env:RELEASE_VERSION = $version
$env:ZED_COMMIT_SHA = $upstreamCommit
$env:CARGO_PROFILE_RELEASE_DEBUG = '0'
$env:CARGO_PROFILE_RELEASE_LTO = 'false'
$env:CARGO_PROFILE_RELEASE_CODEGEN_UNITS = '16'
if (!$env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR = Join-Path $WorkDir 'target' }
$toolchain = (Select-String -LiteralPath "$SourceDir\rust-toolchain.toml" -Pattern '^channel\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
$env:RUSTUP_TOOLCHAIN = "$toolchain-x86_64-pc-windows-msvc"
if (!(Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$vs) { throw 'Install the x64 MSVC toolchain and Windows SDK, or run in their developer shell.' }
    Import-Module "$vs\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
    Enter-VsDevShell -VsInstallPath $vs -DevCmdArguments '-arch=x64 -host_arch=x64' -SkipAutomaticLocation
}
if (!(Get-Command $Iscc -ErrorAction SilentlyContinue)) {
    $Iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
}
if (!(Get-Command $Iscc -ErrorAction SilentlyContinue)) { throw 'Inno Setup compiler not found. Supply -Iscc with its full path.' }
rustup toolchain install $env:RUSTUP_TOOLCHAIN --profile minimal
if ($LASTEXITCODE -ne 0) { throw 'Could not install the pinned Rust toolchain' }
Push-Location -LiteralPath $SourceDir
try {
    cargo build --locked --release -p zed -p cli
    if ($LASTEXITCODE -ne 0) { throw 'Editor build failed' }
    cargo test --locked --release -p gpui --lib text_system::
    if ($LASTEXITCODE -ne 0) { throw 'Caret tests failed' }
    cargo test --locked --release -p gpui_windows --lib direct_write::tests
    if ($LASTEXITCODE -ne 0) { throw 'DirectWrite tests failed' }
} finally { Pop-Location }

& "$PSScriptRoot\scripts\package.ps1" -Version $version -BinaryDir "$env:CARGO_TARGET_DIR\release" -SourceDir $SourceDir -WorkDir $WorkDir -OutDir $OutDir -Iscc $Iscc
git -C $SourceDir archive --format=zip "--prefix=ZEDP-RTL-$version/" "--output=$OutDir\ZEDP-RTL-$version-source.zip" $tree
if ($LASTEXITCODE -ne 0) { throw 'Source archive failed' }
