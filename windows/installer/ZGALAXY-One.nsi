; =============================================================================
; ZGALAXY One — Windows installer (NSIS)
;
; Build with:  makensis ZGALAXY-One.nsi
; Requires the binaries from `windows\build-windows.ps1` (dist\ folder).
;
; Installs the ZGALAXY One client (ZeroTier 1.16.2 fork wired exclusively to
; the ZGALAXY private planet) and registers it as a Windows service.
; =============================================================================

!define APP_NAME "ZGALAXY One"
!define APP_VERSION "1.16.2"
!define APP_EXE "zerotier-one.exe"
!define SERVICE_NAME "ZeroTierOneService"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ZGALAXYOne"
!define REG_KEY "Software\ZeroTierOne"

Name "${APP_NAME}"
OutFile "ZGALAXY-One-Setup.exe"
InstallDir "$PROGRAMFILES64\ZGALAXY One"
RequestExecutionLevel admin
Unicode true
SetCompressor /SOLID lzma

; Branding
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install-blue.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall-blue.ico"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------------------
Section "Install" SecMain
  SetOutPath "$INSTDIR"

  ; Core binaries (zerotier-one.exe dispatches cli/idtool via argv[0])
  File "..\dist\zerotier-one.exe"
  File "..\dist\zerotier-cli.exe"
  File "..\dist\zerotier-idtool.exe"

  ; Register the Windows service (ZeroTier One / ZGALAXY)
  nsExec::ExecToLog 'sc create "${SERVICE_NAME}" binPath= "$INSTDIR\${APP_EXE}" start= auto DisplayName= "ZGALAXY One (ZeroTier engine)"'
  nsExec::ExecToLog 'sc description "${SERVICE_NAME}" "ZGALAXY One — private ZeroTier planet client"'
  nsExec::ExecToLog 'sc start "${SERVICE_NAME}"'

  ; Firewall: UDP 9993 inbound + binary
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One UDP 9993"'
  nsExec::ExecToLog 'netsh advfirewall firewall add rule name="ZGALAXY One UDP 9993" dir=in action=allow protocol=UDP localport=9993'
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One (TCP)"'
  nsExec::ExecToLog 'netsh advfirewall firewall add rule name="ZGALAXY One (TCP)" dir=in action=allow program="$INSTDIR\${APP_EXE}"'

  ; Registry (uninstall info + service token hint)
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "ZGALAXY (dreamzone-cc)"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1

  ; Uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

; ---------------------------------------------------------------------------
Section "Uninstall"
  ; Stop + remove service
  nsExec::ExecToLog 'sc stop "${SERVICE_NAME}"'
  Sleep 1000
  nsExec::ExecToLog 'sc delete "${SERVICE_NAME}"'
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One UDP 9993"'
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One (TCP)"'

  ; Remove files (keep user data in \ProgramData\ZeroTier\One)
  Delete "$INSTDIR\zerotier-one.exe"
  Delete "$INSTDIR\zerotier-cli.exe"
  Delete "$INSTDIR\zerotier-idtool.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd
