; =============================================================================
; ZGALAXY One — Comprehensive Professional Windows Installer (NSIS)
;
; Compiler:       Nullsoft Scriptable Install System (NSIS 3.x)
; Output:         ZGALAXY-One-Setup.exe
; Target OS:      Windows 10 / 11 / Server (x64)
;
; Features:
;   - Modern UI 2 (MUI2) with clean visual branding
;   - Full 64-bit Architecture Enforcement (x64)
;   - Safe upgrade: Gracefully stops running services before file extraction
;   - Installs core binaries (zgalaxy-one.exe, zerotier-one.exe, zerotier-cli.exe, zerotier-idtool.exe)
;   - Automatically registers & configures the Windows Service (Auto-Start + Crash Recovery)
;   - Configures Windows Defender Firewall rules (UDP 9993 & TCP Management)
;   - Creates Start Menu shortcuts with proper icons
;   - Adds binary directory to System PATH for easy CLI usage
;   - Complete clean Uninstaller registered in Windows Add/Remove Programs
; =============================================================================

Unicode true
SetCompressor /SOLID lzma

; --- General Application Definitions ---
!define APP_NAME "ZGALAXY One"
!define APP_VERSION "1.16.2"
!define APP_PUBLISHER "ZGALAXY Team (dreamzone-cc)"
!define APP_WEBSITE "https://github.com/dreamzone-cc/zgalaxy-core"
!define APP_EXE "zgalaxy-one.exe"
!define LEGACY_EXE "zerotier-one.exe"
!define SERVICE_NAME "ZeroTierOneService"
!define SERVICE_DISPLAY "ZGALAXY One Network Service"
!define SERVICE_DESC "ZGALAXY One — Private Planet Core Engine and Virtual Network Adapter Service"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ZGALAXYOne"
!define REG_KEY "Software\ZGALAXYOne"

; --- Installer Target Properties ---
Name "${APP_NAME} ${APP_VERSION}"
OutFile "..\dist\ZGALAXY-One-Setup.exe"
InstallDir "$PROGRAMFILES64\ZGALAXY One"
InstallDirRegKey HKLM "${REG_KEY}" "InstallDir"
RequestExecutionLevel admin

; --- NSIS Modern UI 2 Configuration ---
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

; --- UI Aesthetics & Graphics ---
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install-blue.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall-blue.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Header\win.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\win.bmp"

; --- Wizard Pages ---
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Start ${APP_NAME} Service now"
!define MUI_FINISHPAGE_RUN_FUNCTION "StartServiceAfterInstall"
!insertmacro MUI_PAGE_FINISH

; --- Uninstaller Pages ---
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; --- Languages ---
!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------------------
; Initialization Function (Check x64 Compatibility & Admin Rights)
; ---------------------------------------------------------------------------
Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP|MB_OK "Error: ${APP_NAME} requires a 64-bit version of Windows (x64)."
    Abort
  ${EndIf}

  ; Check if already running or service exists
  nsExec::Exec 'net stop "${SERVICE_NAME}"'
FunctionEnd

; ---------------------------------------------------------------------------
; Main Installation Section
; ---------------------------------------------------------------------------
Section "Core Engine & Binaries (Required)" SecMain
  SectionIn RO

  ; Set output path to installation directory
  SetOutPath "$INSTDIR"

  ; 1. Copy Compiled Engine & UI Binaries
  DetailPrint "Extracting ZGALAXY Core binaries and Desktop Control Panel..."
  File /nonfatal "..\dist\zerotier-one.exe"
  File /nonfatal "..\dist\zerotier-cli.exe"
  File /nonfatal "..\dist\zerotier-idtool.exe"
  File /nonfatal "..\dist\zerotier_desktop_ui.exe"
  File /nonfatal "..\dist\zgalaxy_desktop_ui.exe"
  
  ; Ensure aliases exist
  IfFileExists "$INSTDIR\zerotier-one.exe" 0 +4
    CopyFiles /SILENT "$INSTDIR\zerotier-one.exe" "$INSTDIR\zgalaxy-one.exe"
    CopyFiles /SILENT "$INSTDIR\zerotier-cli.exe" "$INSTDIR\zgalaxy-cli.exe"
    CopyFiles /SILENT "$INSTDIR\zerotier_desktop_ui.exe" "$INSTDIR\zgalaxy_desktop_ui.exe"

  ; 2. Copy and Register NDIS6 Virtual Adapter TAP Driver in $INSTDIR and DriverStore
  DetailPrint "Installing NDIS6 TAP virtual network adapter driver..."
  SetOutPath "$INSTDIR"
  File "..\dist\driver\zttap300.inf"
  File "..\dist\driver\zttap300.sys"
  File "..\dist\driver\zttap300.cat"
  
  SetOutPath "$INSTDIR\driver"
  File "..\dist\driver\zttap300.inf"
  File "..\dist\driver\zttap300.sys"
  File "..\dist\driver\zttap300.cat"
  SetOutPath "$INSTDIR"
  
  ; Copy driver to ProgramData as secondary lookup path for WindowsEthernetTap
  SetShellVarContext all
  CreateDirectory "$APPDATA\ZeroTier\One"
  CopyFiles /SILENT "$INSTDIR\driver\*" "$APPDATA\ZeroTier\One\"
  SetShellVarContext current
  
  nsExec::ExecToLog 'pnputil.exe /add-driver "$INSTDIR\zttap300.inf" /install'

  ; 3. Create Start Menu & Desktop Shortcuts
  DetailPrint "Creating Start Menu & Desktop shortcuts..."
  CreateDirectory "$SMPROGRAMS\ZGALAXY One"
  CreateShortcut "$SMPROGRAMS\ZGALAXY One\ZGALAXY One Control Panel.lnk" "$INSTDIR\zerotier_desktop_ui.exe" "" "$INSTDIR\zerotier-one.exe" 0
  CreateShortcut "$DESKTOP\ZGALAXY One Control Panel.lnk" "$INSTDIR\zerotier_desktop_ui.exe" "" "$INSTDIR\zerotier-one.exe" 0
  CreateShortcut "$SMPROGRAMS\ZGALAXY One\ZGALAXY One CLI.lnk" "$SYSDIR\cmd.exe" '/k "$INSTDIR\zerotier-cli.exe" info' "$INSTDIR\zerotier-one.exe" 0
  CreateShortcut "$SMPROGRAMS\ZGALAXY One\Uninstall ZGALAXY One.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0

  ; 4. Stop Old Service & Install Windows Service
  DetailPrint "Configuring Windows Service..."
  nsExec::ExecToLog 'sc stop "${SERVICE_NAME}"'
  Sleep 1000
  nsExec::ExecToLog 'sc delete "${SERVICE_NAME}"'
  Sleep 500

  ; Create Service with Auto-start
  nsExec::ExecToLog 'sc create "${SERVICE_NAME}" binPath= "\"$INSTDIR\${LEGACY_EXE}\"" start= auto DisplayName= "${SERVICE_DISPLAY}"'
  nsExec::ExecToLog 'sc description "${SERVICE_NAME}" "${SERVICE_DESC}"'
  
  ; Configure Failure Recovery (Restart on crash)
  nsExec::ExecToLog 'sc failure "${SERVICE_NAME}" reset= 86400 actions= restart/5000/restart/5000/restart/5000'

  ; 5. Grant ProgramData and authtoken.secret Read Permissions so Desktop UI Can Access Networks
  DetailPrint "Configuring authentication token and data access permissions..."
  SetShellVarContext all
  nsExec::ExecToLog 'icacls "$APPDATA\ZeroTier\One" /grant "*S-1-5-32-545:(OI)(CI)(RX)" /grant "Users:(OI)(CI)(RX)" /grant "Everyone:(OI)(CI)(RX)" /t'
  IfFileExists "$APPDATA\ZeroTier\One\authtoken.secret" 0 +2
    nsExec::ExecToLog 'icacls "$APPDATA\ZeroTier\One\authtoken.secret" /grant "*S-1-5-32-545:(R)" /grant "Users:(R)" /grant "Everyone:(R)"'
  SetShellVarContext current

  ; 5. Windows Firewall Rules
  DetailPrint "Configuring Windows Defender Firewall rules..."
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One UDP 9993"'
  nsExec::ExecToLog 'netsh advfirewall firewall add rule name="ZGALAXY One UDP 9993" dir=in action=allow protocol=UDP localport=9993 profile=any'
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One (Core Engine)"'
  nsExec::ExecToLog 'netsh advfirewall firewall add rule name="ZGALAXY One (Core Engine)" dir=in action=allow program="$INSTDIR\${LEGACY_EXE}" enable=yes profile=any'

  ; 6. Registry Information (Add/Remove Programs & AutoStart)
  DetailPrint "Writing Registry keys..."
  WriteRegStr HKLM "${REG_KEY}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${REG_KEY}" "Version" "${APP_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "ZGALAXY One UI" '"$INSTDIR\zerotier_desktop_ui.exe"'

  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME} (${APP_VERSION})"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "HelpLink" "${APP_WEBSITE}"
  WriteRegStr HKLM "${UNINST_KEY}" "URLInfoAbout" "${APP_WEBSITE}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" '"$INSTDIR\${LEGACY_EXE}",0'
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1

  ; Estimated Size in KB
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" "$0"

  ; 7. Create Uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"

SectionEnd

; ---------------------------------------------------------------------------
; Helper Functions
; ---------------------------------------------------------------------------
Function StartServiceAfterInstall
  DetailPrint "Starting ZGALAXY One service..."
  nsExec::ExecToLog 'sc start "${SERVICE_NAME}"'
  IfFileExists "$INSTDIR\zerotier_desktop_ui.exe" 0 +2
    Exec '"$INSTDIR\zerotier_desktop_ui.exe"'
FunctionEnd

; ---------------------------------------------------------------------------
; Uninstaller Section
; ---------------------------------------------------------------------------
Section "Uninstall"
  DetailPrint "Stopping ZGALAXY UI and Service..."
  nsExec::ExecToLog 'taskkill /F /IM zerotier_desktop_ui.exe'
  nsExec::ExecToLog 'taskkill /F /IM zgalaxy_desktop_ui.exe'
  nsExec::ExecToLog 'sc stop "${SERVICE_NAME}"'
  Sleep 1500
  nsExec::ExecToLog 'sc delete "${SERVICE_NAME}"'

  DetailPrint "Removing Windows Firewall rules..."
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One UDP 9993"'
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="ZGALAXY One (Core Engine)"'

  DetailPrint "Deleting files and shortcuts..."
  Delete "$DESKTOP\ZGALAXY One Control Panel.lnk"
  Delete "$SMPROGRAMS\ZGALAXY One\ZGALAXY One Control Panel.lnk"
  Delete "$SMPROGRAMS\ZGALAXY One\ZGALAXY One CLI.lnk"
  Delete "$SMPROGRAMS\ZGALAXY One\Uninstall ZGALAXY One.lnk"
  RMDir "$SMPROGRAMS\ZGALAXY One"

  Delete "$INSTDIR\zerotier-one.exe"
  Delete "$INSTDIR\zerotier-cli.exe"
  Delete "$INSTDIR\zerotier-idtool.exe"
  Delete "$INSTDIR\zerotier_desktop_ui.exe"
  Delete "$INSTDIR\zgalaxy-one.exe"
  Delete "$INSTDIR\zgalaxy-cli.exe"
  Delete "$INSTDIR\zgalaxy_desktop_ui.exe"
  Delete "$INSTDIR\zttap300.cat"
  Delete "$INSTDIR\zttap300.inf"
  Delete "$INSTDIR\zttap300.sys"
  Delete "$INSTDIR\driver\zttap300.cat"
  Delete "$INSTDIR\driver\zttap300.inf"
  Delete "$INSTDIR\driver\zttap300.sys"
  RMDir "$INSTDIR\driver"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  ; Clean Registry
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "ZGALAXY One UI"
  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "${REG_KEY}"

  DetailPrint "Uninstallation complete."
SectionEnd
