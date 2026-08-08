#!/usr/bin/env bash
# =============================================================================
# zgalaxy-planet-sync — permanent dynamic-IP resolver for ZGALAXY One clients
#
# ZeroTier's engine is IP-only (it cannot resolve hostname endpoints), so this
# helper keeps the client's planet file in sync with the ZGALAXY service:
#
#   1. fetches the latest planet from the ZGALAXY engine (which the DDNS worker
#      rebuilds whenever the public IP of dz.dreamzone.cc changes), and
#   2. if it differs from the current planet, replaces it and restarts
#      zerotier-one so the client re-links with the network automatically.
#
# Install with the systemd timer (see zgalaxy-planet-sync.{service,timer})
# or via `install.sh`.
# =============================================================================
set -euo pipefail

# The ZGALAXY engine's public planet download URL (unauthenticated).
PLANET_URL="${ZGALAXY_PLANET_URL:-http://dz.dreamzone.cc:3000/api/v1/planet/download}"
PLANET_FILE="/var/lib/zerotier-one/planet"
TMP_FILE="/var/lib/zerotier-one/planet.new"

mkdir -p "$(dirname "$PLANET_FILE")"

# Fetch the current planet (non-fatal on transient network errors).
if ! curl -fsS -m 20 -o "$TMP_FILE" "$PLANET_URL" 2>/dev/null; then
  rm -f "$TMP_FILE"
  exit 0
fi

# No change -> nothing to do.
if [ -f "$PLANET_FILE" ] && cmp -s "$TMP_FILE" "$PLANET_FILE"; then
  rm -f "$TMP_FILE"
  exit 0
fi

echo "[zgalaxy-planet-sync] Planet changed — updating and re-linking."
mv -f "$TMP_FILE" "$PLANET_FILE"
chmod 644 "$PLANET_FILE"

# Restart zerotier-one so it reloads the planet (re-links with the network).
if command -v systemctl >/dev/null 2>&1 && systemctl is-active zerotier-one >/dev/null 2>&1; then
  systemctl restart zerotier-one || true
fi
