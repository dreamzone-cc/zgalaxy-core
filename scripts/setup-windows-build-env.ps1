# =============================================================================
# Windows Build Environment Setup for ZGALAXY Core
# =============================================================================

$ErrorActionPreference = "Continue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Setting up Windows Build Environment for ZGALAXY Core   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Enable Long Paths
Write-Host "`n[1/4] Enabling Long Paths Support..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Force
    Write-Host "Long paths enabled successfully." -ForegroundColor Green
} catch {
    Write-Host "Notice: LongPaths registry update skipped ($($_.Exception.Message))" -ForegroundColor Yellow
}

# 2. Package Manager & Tools
Write-Host "`n[2/4] Checking Chocolatey / Tools..." -ForegroundColor Yellow
if (-not (Get-Command "choco" -ErrorAction SilentlyContinue)) {
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        $script = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
        Invoke-Expression $script
        $env:Path = "$env:ALLUSERSPROFILE\chocolatey\bin;" + $env:Path
    } catch {
        Write-Host "Chocolatey auto-install skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (Get-Command "choco" -ErrorAction SilentlyContinue) {
    choco install nsis -y --no-progress
}

# 3. Visual Studio Build Tools
Write-Host "`n[3/4] Downloading Visual Studio Build Tools..." -ForegroundColor Yellow
$vsInstallerUrl = "https://aka.ms/vs/17/release/vs_buildtools.exe"
$vsInstallerPath = "$env:TEMP\vs_buildtools.exe"
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstallerPath -UseBasicParsing
    Write-Host "Running VS Build Tools installer in quiet mode..." -ForegroundColor Green
    $vsArgs = @(
        "--quiet",
        "--wait",
        "--norestart",
        "--nocache",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.VC.v143.MFC.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.VC.v143.ATL.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.Windows11SDK.22621"
    )
    Start-Process -FilePath $vsInstallerPath -ArgumentList $vsArgs -Wait -NoNewWindow
} catch {
    Write-Host "VS Build Tools installer notice: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 4. Rust Toolchain (MSVC)
Write-Host "`n[4/4] Ensuring Rust MSVC toolchain is installed..." -ForegroundColor Yellow
$rustupInitPath = "$env:TEMP\rustup-init.exe"
if (-not (Test-Path $rustupInitPath)) {
    Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupInitPath -UseBasicParsing
}
Start-Process -FilePath $rustupInitPath -ArgumentList "-y", "--default-host", "x86_64-pc-windows-msvc", "--default-toolchain", "stable" -Wait -NoNewWindow
$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   Windows Build Environment setup completed!             " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
