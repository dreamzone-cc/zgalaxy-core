# =============================================================================
# Build ZGALAXY One for Windows (Local Compilation & Packaging)
# =============================================================================
param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Building ZGALAXY One for Windows (x64) from Source     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

# 1. Locate MSBuild via vswhere
Write-Host "`n[1/5] Locating Visual Studio 2022 / MSBuild..." -ForegroundColor Yellow
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "Visual Studio 2022 installer (vswhere.exe) not found."
}

$vsPath = & $vswhere -latest -products * -property installationPath
if (-not $vsPath) {
    throw "Visual Studio 2022 installation path not found."
}

$msbuild = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
if (-not (Test-Path $msbuild)) {
    $msbuild = (Get-ChildItem -Path $vsPath -Filter "MSBuild.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
if (-not $msbuild -or -not (Test-Path $msbuild)) {
    throw "MSBuild.exe not found under $vsPath"
}
Write-Host "Found MSBuild: $msbuild" -ForegroundColor Green

# 2. Rust Toolchain check
Write-Host "`n[2/5] Checking Rust MSVC toolchain..." -ForegroundColor Yellow
$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "Cargo/Rust not found in PATH."
}
rustup target add x86_64-pc-windows-msvc
Write-Host "Rust toolchain is ready." -ForegroundColor Green

# 3. Build rustybits (zeroidc)
Write-Host "`n[3/5] Compiling rustybits/zeroidc..." -ForegroundColor Yellow
Push-Location "$RepoRoot\rustybits"
try {
    cargo build -p zeroidc --target x86_64-pc-windows-msvc --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build zeroidc failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
Write-Host "rustybits built successfully!" -ForegroundColor Green

# 4. Build Engine via MSBuild
Write-Host "`n[4/5] Compiling ZeroTierOne.vcxproj ($Platform/$Configuration)..." -ForegroundColor Yellow
& $msbuild "$RepoRoot\windows\ZeroTierOne\ZeroTierOne.vcxproj" /m `
    /p:Configuration=$Configuration /p:Platform=$Platform `
    /p:SolutionDir="$RepoRoot\windows\"

if ($LASTEXITCODE -ne 0) {
    throw "MSBuild failed with exit code $LASTEXITCODE"
}

# 5. Collect Output Binaries into windows\dist
Write-Host "`n[5/5] Packaging binaries and installer into windows\dist..." -ForegroundColor Yellow
$arch = if ($Platform -eq "x64") { "x64" } elseif ($Platform -eq "Win32") { "x86" } else { $Platform }
$outDir = "$RepoRoot\windows\Build\$Platform\$Configuration"
$distDir = "$RepoRoot\windows\dist"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$oneExe = "$outDir\zerotier-one_$arch.exe"
if (-not (Test-Path $oneExe)) {
    $oneExe = (Get-ChildItem -Path "$RepoRoot\windows\Build" -Filter "*zerotier-one*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

if (-not (Test-Path $oneExe)) {
    throw "Expected binary not found in $outDir"
}

Copy-Item $oneExe "$distDir\zerotier-one.exe" -Force
Copy-Item $oneExe "$distDir\zerotier-cli.exe" -Force
Copy-Item $oneExe "$distDir\zerotier-idtool.exe" -Force
Copy-Item $oneExe "$distDir\zgalaxy-one.exe" -Force

# Build NSIS Setup Installer
$makensisPath = foreach ($p in @("C:\Program Files (x86)\NSIS\makensis.exe", "C:\Program Files\NSIS\makensis.exe", "C:\ProgramData\chocolatey\bin\makensis.exe", "makensis")) {
    if (Test-Path $p -ErrorAction SilentlyContinue) { $p; break }
}
$makensis = $makensisPath

if ($makensis -and (Test-Path "$RepoRoot\windows\installer\ZGALAXY-One.nsi")) {
    Write-Host "Building installer ZGALAXY-One-Setup.exe with NSIS..." -ForegroundColor Cyan
    Push-Location "$RepoRoot\windows\installer"
    try {
        & $makensis "/V3" "ZGALAXY-One.nsi"
    } finally {
        Pop-Location
    }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   ZGALAXY One build and packaging completed successfully! " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Generated binaries located in: $distDir" -ForegroundColor Cyan
Get-ChildItem $distDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
