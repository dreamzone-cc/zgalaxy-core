[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "رابط المستودع في GitHub")]
    [string]$RepoUrl = "https://github.com/dreamzone-cc/zgalaxy-core",

    [Parameter(Mandatory = $true, HelpMessage = "رمز التسجيل من GitHub (Runner Registration Token)")]
    [string]$RunnerToken,

    [Parameter(Mandatory = $false)]
    [string]$RunnerName = "ZGalaxy-Win-Runner-01",

    [Parameter(Mandatory = $false)]
    [string]$InstallDir = "C:\actions-runner",

    [Parameter(Mandatory = $false)]
    [string]$RunnerVersion = "2.322.0"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     تثبيت GitHub Self-hosted Runner كخدمة Windows      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "يجب تشغيل هذا السكريبت بصلاحيات المسؤول (Run as Administrator) لتثبيت الخدمة!"
    Exit 1
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Set-Location $InstallDir

$zipFileName = "actions-runner-win-x64-$RunnerVersion.zip"
$downloadUrl = "https://github.com/actions/runner/releases/download/v$RunnerVersion/$zipFileName"

if (-not (Test-Path $zipFileName)) {
    Write-Host "`n[1/4] تحميل GitHub Actions Runner v$RunnerVersion لنظام Windows x64..." -ForegroundColor Yellow
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-WebRequest -Uri $downloadUrl -OutFile "$InstallDir\$zipFileName"
    Write-Host "تم التحميل بنجاح." -ForegroundColor Green
}

Write-Host "فك ضغط حزمة الـ Runner..." -ForegroundColor Gray
Expand-Archive -Path "$InstallDir\$zipFileName" -DestinationPath $InstallDir -Force

Write-Host "`n[2/4] تسجيل الـ Runner في المستودع: $RepoUrl ..." -ForegroundColor Yellow
Write-Host "الوسوم (Labels): self-hosted, windows, x64, zgalaxy-builder" -ForegroundColor Cyan

$configArgs = @(
    "--url", $RepoUrl,
    "--token", $RunnerToken,
    "--name", $RunnerName,
    "--labels", "self-hosted,windows,x64,zgalaxy-builder",
    "--work", "_work",
    "--runasservice",
    "--unattended",
    "--replace"
)
& "$InstallDir\config.cmd" @configArgs

Write-Host "`n[3/4] تثبيت وتشغيل خدمة Windows (runsvc.cmd)..." -ForegroundColor Yellow
& "$InstallDir\runsvc.cmd" install
& "$InstallDir\runsvc.cmd" start

Write-Host "`n[4/4] فحص حالة الخدمة على النظام..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$services = Get-Service -Name "actions.runner.*" -ErrorAction SilentlyContinue

if ($services -and $services.Status -eq "Running") {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "       تم تثبيت وتشغيل خدمة الـ Runner بنجاح تام!         " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "اسم الخدمة: $($services.Name)" -ForegroundColor Cyan
    Write-Host "الحالة الحالية: $($services.Status)" -ForegroundColor Green
    Write-Host "نوع البدء: تلقائي (Automatic - starts on boot)" -ForegroundColor Cyan
    Write-Host "`nاذهب الآن إلى مستودعك على GitHub -> Settings -> Actions -> Runners ستجده Idle." -ForegroundColor Green
} else {
    Write-Host "حالة الخدمة الحالية: $($services.Status)" -ForegroundColor Yellow
}
