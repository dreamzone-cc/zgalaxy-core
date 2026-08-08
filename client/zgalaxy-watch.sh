#!/usr/bin/env bash
# =============================================================================
# zgalaxy-watch — connectivity watchdog for ZGALAXY One
#
# Runs continuously alongside the client. Every CHECK_INTERVAL seconds it
# checks whether the client is still connected to the ZGALAXY root. When
# connected it does nothing. When a disconnection is detected it calls
# zgalaxy-planet-sync.sh, which resolves dz.dreamzone.cc, fetches the updated
# planet (with the current IP) and re-links the client.
#
# This is event-driven (reactive to connection loss) — there is no periodic
# planet fetching while the connection is healthy.
# =============================================================================
set -euo pipefail

CHECK_INTERVAL="${ZGALAXY_CHECK_INTERVAL:-10}"   # seconds between checks
SYNC="/usr/local/sbin/zgalaxy-planet-sync.sh"

log() { echo "[zgalaxy-watch] $*"; }

log "watchdog started (check every ${CHECK_INTERVAL}s)."

while true; do
  "$SYNC"        # connected → no-op; disconnected → resolve + re-link
  sleep "$CHECK_INTERVAL"
done
