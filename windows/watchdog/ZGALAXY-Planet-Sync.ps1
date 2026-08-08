# =============================================================================
# ZGALAXY-Planet-Sync.ps1 — reactive dynamic-IP resolver for ZGALAXY One (Windows)
#
# This is an ACTION, not a periodic job. It is invoked by the "ZGALAXY One
# Watchdog" scheduled task (see install-watchdog.ps1) every minute. It does
# nothing while the client is still connected to the ZGALAXY root.
#
# Behaviour:
#   - connected to the ZGALAXY root -> do nothing,
#   - disconnected -> resolve dz.dreamzone.cc to its current IP, fetch the
#     latest planet from the ZGALAXY engine, apply it and restart the client
#     service so it re-links with the network automatically.
#
# Mirrors client/zgalaxy-planet-sync.sh (Linux companion).
# =============================================================================
param(
    [string]$Domain     = $env:ZGALAXY_DOMAIN,
    [string]$RootId     = $env:ZGALAXY_ROOT_ID,
    [string]$PlanetUrl  = $env:ZGALAXY_PLANET_URL,
    [string]$DataDir    = $env:ZGALAXY_DATA_DIR,
    [string]$ServiceName = $env:ZGALAXY_SERVICE_NAME
)

$ErrorActionPreference = "Stop"

if (-not $Domain)      { $Domain      = "dz.dreamzone.cc" }
if (-not $RootId)      { $RootId      = "069ae38092" }
if (-not $DataDir)     { $DataDir     = Join-Path $env:ProgramData "ZeroTier\One" }
if (-not $ServiceName) { $ServiceName = "ZeroTierOneService" }

# --- locate zerotier-cli.exe -------------------------------------------------
$cliPath = $null
$cliCmd = Get-Command zerotier-cli.exe -ErrorAction SilentlyContinue
if ($cliCmd) { $cliPath = $cliCmd.Source }
if (-not $cliPath) {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles "ZGALAXY One\zerotier-cli.exe"),
        (Join-Path $DataDir "zerotier-cli.exe")
    )) {
        if (Test-Path $candidate) { $cliPath = $candidate; break }
    }
}
if (-not $cliPath) { exit 0 }   # client not installed; nothing to do

$logFile = Join-Path $DataDir "zgalaxy-watch.log"
function Log([string]$msg) {
    Add-Content -Path $logFile -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -ErrorAction SilentlyContinue
}

# --- still connected to the root? --------------------------------------------
# listpeers rows: "200 listpeers <addr> <path> <latency> <version> <role>"
$connected = $false
foreach ($row in (& $cliPath listpeers 2>$null)) {
    $f = $row -split '\s+'
    if ($f.Count -ge 7 -and $f[0] -eq "200" -and $f[2] -eq $RootId -and $f[3] -ne "-" -and $f[4] -ne "-1") {
        $connected = $true
        break
    }
}
if ($connected) { exit 0 }   # healthy -> reactive only, no periodic fetching

Log "disconnected from ${RootId} — resolving ${Domain} and re-linking."

# --- resolve current IP -------------------------------------------------------
$ip = $null
try {
    $ip = ([System.Net.Dns]::GetHostAddresses($Domain) |
        Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
        Select-Object -First 1).IPAddressToString
} catch { }
if (-not $ip) { $ip = "unknown" }
Log "resolved ${Domain} -> ${ip}"

# --- fetch the latest planet from the ZGALAXY engine --------------------------
if (-not $PlanetUrl) { $PlanetUrl = "http://${Domain}:3000/api/v1/planet/download" }
$planetFile = Join-Path $DataDir "planet"
$tmpFile    = Join-Path $DataDir "planet.new"

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
try {
    if ($curl) {
        & $curl.Source -fsS -m 20 -o $tmpFile $PlanetUrl 2>$null
    } else {
        Invoke-WebRequest -Uri $PlanetUrl -OutFile $tmpFile -TimeoutSec 20 -UseBasicParsing
    }
    if (-not (Test-Path $tmpFile)) { throw "download failed" }
} catch {
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    Log "planet fetch failed; will retry on next check."
    exit 0
}

Move-Item -Force $tmpFile $planetFile
Log "planet updated from engine."

# --- (re)start the service — including the stopped case ------------------------
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq "Running") { Restart-Service -Name $svc.Name -Force }
    else                           { Start-Service -Name $svc.Name }
    Log "service ${ServiceName} restarted/started."
}
Log "re-linked. resolved IP in use: ${ip}"
