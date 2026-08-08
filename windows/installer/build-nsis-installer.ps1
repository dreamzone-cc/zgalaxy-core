<#
.SYNOPSIS
    تجميع وبناء ملف التنصيب ZGALAXY-One-Setup.exe لنظام Windows باستخدام NSIS.
.DESCRIPTION
    يقوم السكريبت بـ:
    1. البحث التلقائي عن مترجم NSIS (makensis.exe).
    2. التحقق من وجود الملفات التنفيذية في مجلد dist (zerotier-one.exe / zgalaxy-one.exe).
    3. تجميع ملف ZGALAXY-One.nsi بتقنية الضغط الفائق LZMA.
    4. إنتاج ZGALAXY-One-Setup.exe داخل مجلد windows\dist\ جاهزًا للتوزيع والرفع كـ Release.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     بناء ملف التنصيب ZGALAXY-One-Setup.exe (NSIS)       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$InstallerDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent (Split-Path -Parent $InstallerDir)
$DistDir = Join-Path (Split-Path -Parent $InstallerDir) "dist"
$NsiScript = Join-Path $InstallerDir "ZGALAXY-One.nsi"

# 1. البحث عن makensis.exe
$makensis = foreach ($path in @("C:\Program Files (x86)\NSIS\makensis.exe", "C:\Program Files\NSIS\makensis.exe", "C:\ProgramData\chocolatey\bin\makensis.exe", "makensis")) {
    if (Test-Path $path -ErrorAction SilentlyContinue) { $path; break }
}

if (-not $makensis -and (Get-Command "makensis" -ErrorAction SilentlyContinue)) {
    $makensis = "makensis"
}

if (-not $makensis) {
    Write-Host "لم يتم العثور على NSIS على هذا الجهاز. جاري البحث عن خيار التثبيت عبر winget أو chocolatey..." -ForegroundColor Yellow
    if (Get-Command "choco" -ErrorAction SilentlyContinue) {
        choco install nsis -y --no-progress
    } elseif (Get-Command "winget" -ErrorAction SilentlyContinue) {
        winget install --id NSIS.NSIS -e --source winget --accept-source-agreements --accept-package-agreements --silent
    } else {
        Write-Error "يرجى تثبيت NSIS من الموقع الرسمي: https://nsis.sourceforge.io/Download"
        Exit 1
    }
    $makensis = (Get-ChildItem -Path "$env:ProgramFiles\NSIS\makensis.exe", "$env:ProgramFiles(x86)\NSIS\makensis.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

Write-Host "تم العثور على مترجم NSIS: $makensis" -ForegroundColor Green

# 2. التحقق من وجود الملفات التنفيذية
if (-not (Test-Path "$DistDir\zerotier-one.exe") -and -not (Test-Path "$DistDir\zgalaxy-one.exe")) {
    Write-Host "تحذير: الملفات التنفيذية غير موجودة في $DistDir! قم بتشغيل سكريبت build-windows.ps1 أولاً." -ForegroundColor Yellow
}

# 3. تجميع ملف .nsi
Write-Host "`nبدء تجميع $NsiScript بواسطة makensis..." -ForegroundColor Cyan
Set-Location $InstallerDir
& $makensis "/V4" "$NsiScript"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "       تم إنشاء برنامج التثبيت بنجاح تام!                 " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    $setupExe = Join-Path $DistDir "ZGALAXY-One-Setup.exe"
    if (Test-Path $setupExe) {
        $item = Get-Item $setupExe
        Write-Host "المسار: $($item.FullName)" -ForegroundColor Cyan
        Write-Host "الحجم: $([math]::Round($item.Length / 1MB, 2)) MB" -ForegroundColor Cyan
    }
} else {
    Write-Error "حدث خطأ أثناء تجميع ملف NSIS (رمز الخطأ: $LASTEXITCODE)"
}
