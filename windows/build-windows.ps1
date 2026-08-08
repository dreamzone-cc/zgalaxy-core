# =============================================================================
# Build ZGALAXY One for Windows (from source)
#
#   powershell -ExecutionPolicy Bypass -File build-windows.ps1
#
# Builds rustybits (Rust OIDC helper) then the ZeroTier engine project, and
# collects zerotier-one.exe / zerotier-cli.exe / zerotier-idtool.exe into
# windows\dist\. The ZGALAXY planet is baked into the binary.
#
# Requirements (on this Windows machine):
#   - Visual Studio 2022 with "Desktop development with C++" workload
#   - Rust toolchain (rustup) — auto-installed if missing
#
# NOTE: the NDIS6 tap driver (TapDriver6) is built separately and requires the
# Windows Driver Kit + driver signing; see docs/BUILD-WINDOWS.md.
# =============================================================================
param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64",
    [string]$SrcDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

Write-Host "== ZGALAXY One Windows build ==" -ForegroundColor Cyan
Write-Host "  Config : $Configuration"
Write-Host "  Platform: $Platform"
Write-Host "  Source : $SrcDir"

# ---- 1. Locate MSBuild via vswhere (VS 2022) -------------------------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "Visual Studio 2022 not found (vswhere missing). Install VS2022 with the C++ workload."
}
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) {
    throw "VS2022 C++ workload not found."
}
$msbuild = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
if (-not (Test-Path $msbuild)) {
    throw "MSBuild.exe not found under $vsPath"
}
Write-Host "MSBuild: $msbuild" -ForegroundColor Green

# ---- 2. Rust toolchain + windows-msvc target --------------------------------
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Rust via rustup..."
    Invoke-WebRequest -Uri "https://sh.rustup.rs" -OutFile "$env:TEMP\rustup-init.exe"
    & "$env:TEMP\rustup-init.exe" -y --profile minimal
    $env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
}
rustup target add x86_64-pc-windows-msvc
$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path

# ---- 3. Build rustybits (zeroidc.lib used by the engine) ---------------------
Write-Host "Building rustybits/zeroidc..." -ForegroundColor Cyan
Push-Location "$SrcDir\rustybits"
try {
    cargo build -p zeroidc --target x86_64-pc-windows-msvc
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# ---- 4. Build the engine project (exe only, not the tap driver/SDK) ----------
Write-Host "Building ZeroTierOne.vcxproj ($Platform/$Configuration)..." -ForegroundColor Cyan
& $msbuild "$SrcDir\windows\ZeroTierOne\ZeroTierOne.vcxproj" /m `
    /p:Configuration=$Configuration /p:Platform=$Platform `
    /p:SolutionDir="$SrcDir\windows\"
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed (exit $LASTEXITCODE)" }

# ---- 5. Collect outputs -------------------------------------------------------
$arch = if ($Platform -eq "x64") { "x64" } elseif ($Platform -eq "Win32") { "x86" } else { $Platform }
$outDir = "$SrcDir\windows\Build\$Platform\$Configuration"
$dist = "$SrcDir\windows\dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$oneExe = "$outDir\zerotier-one_$($arch).exe"
if (-not (Test-Path $oneExe)) { throw "Expected binary not found: $oneExe" }

Copy-Item $oneExe "$dist\zerotier-one.exe" -Force
Copy-Item $oneExe "$dist\zerotier-cli.exe" -Force
Copy-Item $oneExe "$dist\zerotier-idtool.exe" -Force
Copy-Item $oneExe "$dist\zgalaxy-one.exe" -Force
Copy-Item $oneExe "$dist\zgalaxy-cli.exe" -Force

# Copy NDIS6 TAP virtual network adapter driver
$driverSrc = Join-Path $SrcDir "ext\bin\tap-windows-ndis6\x64"
if (Test-Path $driverSrc) {
    $driverDst = Join-Path $dist "driver"
    New-Item -ItemType Directory -Force -Path $driverDst | Out-Null
    Copy-Item "$driverSrc\*" $driverDst -Force
    Write-Host "Driver assets bundled: $driverDst" -ForegroundColor Green
}

# ---- 6. Build NSIS Installer if makensis is present ---------------------------
$makensis = "C:\Program Files (x86)\NSIS\makensis.exe"
if (-not (Test-Path $makensis)) {
    $makensisCmd = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($makensisCmd) { $makensis = $makensisCmd.Source }
}

if (Test-Path $makensis) {
    Write-Host "Building NSIS installer..." -ForegroundColor Cyan
    & $makensis "$SrcDir\windows\installer\ZGALAXY-One.nsi"
    if ($LASTEXITCODE -ne 0) { Write-Warning "NSIS build returned exit code $LASTEXITCODE" }
} else {
    Write-Host "makensis not found; skipping installer creation." -ForegroundColor Yellow
}

Write-Host "== Build complete. Outputs in: $dist ==" -ForegroundColor Green
Get-ChildItem -Recurse $dist | Select-Object FullName, Length
