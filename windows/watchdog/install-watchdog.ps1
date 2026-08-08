# =============================================================================
# install-watchdog.ps1 — register the "ZGALAXY One Watchdog" scheduled task
#
#   powershell -ExecutionPolicy Bypass -File install-watchdog.ps1
#
# Creates a SYSTEM-level scheduled task that runs ZGALAXY-Planet-Sync.ps1 every
# minute. The sync is reactive-only: it exits immediately while the client is
# connected, and only acts (resolve + fetch planet + restart service) when the
# client loses its connection to the ZGALAXY root.
#
# This is the Windows equivalent of client/zgalaxy-watch.service.
# =============================================================================
$ErrorActionPreference = "Stop"

$taskName = "ZGALAXY One Watchdog"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$syncPath  = Join-Path $scriptDir "ZGALAXY-Planet-Sync.ps1"

if (-not (Test-Path $syncPath)) { throw "Not found: $syncPath" }

# remove any previous registration
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$syncPath`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Force | Out-Null

Write-Host "ZGALAXY One Watchdog registered (every 1 minute, SYSTEM)." -ForegroundColor Green
Write-Host "Reactive only: no-op while connected; acts only on disconnect." -ForegroundColor Cyan

# run once immediately to confirm it works
& $syncPath
Write-Host "Initial sync run completed. Log: $env:ProgramData\ZeroTier\One\zgalaxy-watch.log" -ForegroundColor Cyan
