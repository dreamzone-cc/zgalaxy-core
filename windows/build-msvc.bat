@echo off
setlocal
cd /d "%~dp0\.."

set "SOL_DIR=%~dp0"
set "RUST_LIB=rustybits\target\x86_64-pc-windows-msvc\release\zeroidc.lib"

if exist "%RUST_LIB%" (
    if not exist "rustybits\target\release" mkdir "rustybits\target\release"
    copy /y "%RUST_LIB%" "rustybits\target\release\zeroidc.lib" >nul
    copy /y "%RUST_LIB%" "windows\ZeroTierOne\zeroidc.lib" >nul
    copy /y "%RUST_LIB%" "windows\Build\x64\Release\zeroidc.lib" >nul
    copy /y "%RUST_LIB%" "windows\zeroidc.lib" >nul
)

echo == Building ZeroTierOne.vcxproj via MSBuild ==
"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" "windows\ZeroTierOne\ZeroTierOne.vcxproj" /m /p:Configuration=Release /p:Platform=x64 /p:SolutionDir="%SOL_DIR%."
if errorlevel 1 (
    echo MSBuild failed with error %errorlevel%
    exit /b %errorlevel%
)

echo == Collecting outputs ==
if not exist "windows\dist" mkdir "windows\dist"
copy /y "windows\Build\x64\Release\zerotier-one_x64.exe" "windows\dist\zerotier-one.exe"
copy /y "windows\Build\x64\Release\zerotier-one_x64.exe" "windows\dist\zerotier-cli.exe"
copy /y "windows\Build\x64\Release\zerotier-one_x64.exe" "windows\dist\zerotier-idtool.exe"
copy /y "windows\Build\x64\Release\zerotier-one_x64.exe" "windows\dist\zgalaxy-one.exe"

echo == Building NSIS Installer ==
"C:\Program Files (x86)\NSIS\makensis.exe" /V3 "windows\installer\ZGALAXY-One.nsi"
if errorlevel 1 (
    echo NSIS failed with error %errorlevel%
    exit /b %errorlevel%
)

echo == Build finished successfully ==
dir "windows\dist"
