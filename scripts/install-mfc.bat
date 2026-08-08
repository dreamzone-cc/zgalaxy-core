@echo off
set "INSTALL_DIR=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
echo Modifying Visual Studio installation at %INSTALL_DIR%
"%TEMP%\vs_buildtools.exe" modify --installPath "%INSTALL_DIR%" --quiet --norestart --nocache --add Microsoft.VisualStudio.Component.VC.ATL --add Microsoft.VisualStudio.Component.VC.v143.ATL.x86.x64 --add Microsoft.VisualStudio.Component.VC.ATLMFC --add Microsoft.VisualStudio.Component.VC.v143.MFC.x86.x64
echo Exit code: %errorlevel%
