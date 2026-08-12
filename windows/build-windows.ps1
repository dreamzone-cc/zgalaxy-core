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

$ErrorActionPreference = "Continue"

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
rustup target add x86_64-pc-windows-msvc 2>&1 | Out-Null
$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path

# ---- 3. Build rustybits (zeroidc.lib used by the engine) ---------------------
Write-Host "Building rustybits/zeroidc..." -ForegroundColor Cyan
Push-Location "$SrcDir\rustybits"
try {
    cargo build -p zeroidc --target x86_64-pc-windows-msvc --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}
# vcxproj Release/x64 links against the release lib under
# rustybits\target\x86_64-pc-windows-msvc\release\zeroidc.lib (see vcxproj).
$zeroidcLib = Join-Path $SrcDir "rustybits\target\x86_64-pc-windows-msvc\release\zeroidc.lib"
if (-not (Test-Path $zeroidcLib)) { throw "zeroidc.lib not found: $zeroidcLib" }
Write-Host "zeroidc.lib: $zeroidcLib" -ForegroundColor Green

# ---- 4. Build the engine project (exe only, not the tap driver/SDK) ----------
Write-Host "Building ZeroTierOne.vcxproj ($Platform/$Configuration)..." -ForegroundColor Cyan
# SolutionDir must END in a single backslash (the vcxproj uses
# $(SolutionDir)..\rustybits\...). Passing it through a fully-quoted argument
# string with a doubled trailing backslash keeps the closing quote intact even
# when the repo path contains spaces (e.g. "Default Project").
$solutionDirArg = "/p:SolutionDir=$SrcDir\windows\\"
& $msbuild "$SrcDir\windows\ZeroTierOne\ZeroTierOne.vcxproj" /m `
    /p:Configuration=$Configuration /p:Platform=$Platform `
    $solutionDirArg
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed (exit $LASTEXITCODE)" }

# ---- 5. Build the Desktop UI (zgalaxy_desktop_ui.exe) -------------------------
# DesktopUI/ is a Rust app with a libui-ng (Meson/Ninja) + tray (GCC/make) part.
# Requirements: meson, ninja, MinGW gcc + GNU make, Rust x86_64-pc-windows-msvc.
Write-Host "Building DesktopUI (zgalaxy_desktop_ui.exe)..." -ForegroundColor Cyan
$desk = Join-Path $SrcDir "DesktopUI"
$deskExe = Join-Path $desk "target\x86_64-pc-windows-msvc\release\zgalaxy_desktop_ui.exe"
if (Test-Path (Join-Path $desk "Makefile")) {
    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (Test-Path $vcvars) {
        # Build libui-ng via Meson/Ninja under the MSVC environment.
        cmd /c "cd /d `"$desk\libui-ng`" && `"$vcvars`" && meson setup build --buildtype=release -Db_vscrt=mt --default-library=static --backend=ninja"
        if ($LASTEXITCODE -ne 0) { throw "meson setup failed (exit $LASTEXITCODE)" }
        cmd /c "cd /d `"$desk\libui-ng`" && `"$vcvars`" && ninja -C build -j 8"
        if ($LASTEXITCODE -ne 0) { throw "ninja build failed (exit $LASTEXITCODE)" }
        $mesonOut = Join-Path $desk "libui-ng\build\meson-out"
        if (-not (Test-Path (Join-Path $mesonOut "ui.lib"))) {
            Copy-Item (Join-Path $mesonOut "libui.a") (Join-Path $mesonOut "ui.lib") -Force
        }
    }
    # Build the tray helper (GCC/make) and the Rust app.
    Push-Location $desk
    try {
        make -C tray zt_lib
        if ($LASTEXITCODE -ne 0) { throw "tray build failed (exit $LASTEXITCODE)" }
        $env:RUSTFLAGS = "-C target-feature=+crt-static"
        cargo build --release --target=x86_64-pc-windows-msvc
        if ($LASTEXITCODE -ne 0) { throw "cargo (DesktopUI) build failed (exit $LASTEXITCODE)" }
    } finally {
        Remove-Item Env:RUSTFLAGS -ErrorAction SilentlyContinue
        Pop-Location
    }
    if (Test-Path $deskExe) {
        Write-Host "DesktopUI built: $deskExe" -ForegroundColor Green
    } else {
        Write-Warning "DesktopUI build did not produce $deskExe"
    }
} else {
    Write-Host "DesktopUI/Makefile not found; skipping Desktop UI build." -ForegroundColor Yellow
}

# ---- 6. Collect outputs -------------------------------------------------------
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

# Copy the Desktop UI (as both legacy and ZGALAXY names; the NSIS installer
# references them, and it aliases zerotier_desktop_ui -> zgalaxy_desktop_ui).
if (Test-Path $deskExe) {
    Copy-Item $deskExe "$dist\zerotier_desktop_ui.exe" -Force
    Copy-Item $deskExe "$dist\zgalaxy_desktop_ui.exe" -Force
    Write-Host "Desktop UI copied to dist" -ForegroundColor Green
} else {
    Write-Warning "Desktop UI binary missing; installer will skip it."
}

# Copy NDIS6 TAP virtual network adapter driver
$driverSrc = Join-Path $SrcDir "ext\bin\tap-windows-ndis6\x64"
if (Test-Path $driverSrc) {
    $driverDst = Join-Path $dist "driver"
    New-Item -ItemType Directory -Force -Path $driverDst | Out-Null
    Copy-Item "$driverSrc\*" $driverDst -Force
    Write-Host "Driver assets bundled: $driverDst" -ForegroundColor Green
}

# ---- 7. Build NSIS Installer if makensis is present ---------------------------
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
