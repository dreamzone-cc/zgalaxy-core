#!/usr/bin/env bash
# =============================================================================
# zgalaxy-planet-sync — autonomous dynamic-IP resolver for ZGALAXY One clients
#
# Runs in parallel with the ZeroTier client. It:
#
#   1. RESOLVES the ZGALAXY service domain (dz.dreamzone.cc) to its current IP
#      via DNS, every cycle — so it always knows the service's live address.
#   2. FETCHES the latest planet from the ZGALAXY engine (which the DDNS worker
#      rebuilds whenever the public IP changes).
#   3. MONITORS connectivity: if the client is disconnected from the ZGALAXY
#      root, OR the planet/address changed, it APPLIES the updated planet and
#      RESTARTS the client, re-establishing the link automatically and
#      seamlessly — no manual intervention, no client rebuild.
#
# ZeroTier's engine is IP-only (it cannot resolve hostname endpoints), so this
# module performs the DNS resolution on the client's behalf.
# =============================================================================
set -euo pipefail

# --- config -------------------------------------------------------------
DOMAIN="${ZGALAXY_DOMAIN:-dz.dreamzone.cc}"
ROOT_ID="${ZGALAXY_ROOT_ID:-069ae38092}"           # ZGALAXY root node address
PLANET_URL="${ZGALAXY_PLANET_URL:-http://${DOMAIN}:3000/api/v1/planet/download}"
PLANET_FILE="/var/lib/zerotier-one/planet"
TMP_FILE="/var/lib/zerotier-one/planet.new"
PORT="${ZT_PORT:-9993}"
CURL="${CURL:-curl}"

log() { echo "[zgalaxy-planet-sync] $*"; }

# --- 1. DNS resolution: current IP of the service domain --------------------
resolve_domain_ip() {
  local ip
  if command -v getent >/dev/null 2>&1; then
    ip="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)"
  fi
  if [ -z "$ip" ] && command -v dig >/dev/null 2>&1; then
    ip="$(dig +short A "$DOMAIN" 2>/dev/null | grep -E '^[0-9.]+$' | head -1)"
  fi
  if [ -z "$ip" ]; then
    ip="$("${CURL}" -fsS -m 10 "https://dns.google/resolve?name=${DOMAIN}&type=A" 2>/dev/null \
        | grep -oE '"data":"[0-9.]+"' | head -1 | sed 's/.*":"//;s/"//')"
  fi
  [ -n "$ip" ] && echo "$ip" || true
}

# --- 2. Is the client currently connected to the ZGALAXY root? ---------------
is_connected() {
  command -v zerotier-cli >/dev/null 2>&1 || return 1
  # listpeers rows are: "200 listpeers <addr> <path> <latency> <version> <role>".
  # A connected root has a real path and a numeric (non -1) latency.
  zerotier-cli listpeers 2>/dev/null | awk -v r="$ROOT_ID" '$3==r && $4!="-" && $5!="-1" {found=1} END {exit !found}'
}

# --- 3. Fetch the latest planet (non-fatal) -----------------------------------
fetch_planet() {
  "${CURL}" -fsS -m 20 -o "$TMP_FILE" "$PLANET_URL" 2>/dev/null || { rm -f "$TMP_FILE"; return 1; }
  return 0
}

# --- main ---------------------------------------------------------------------
mkdir -p "$(dirname "$PLANET_FILE")"

IP="$(resolve_domain_ip || true)"
log "resolved ${DOMAIN} -> ${IP:-unknown}"

if ! fetch_planet; then
  log "planet fetch failed (engine unreachable); leaving client as-is."
  exit 0
fi

changed=no
if [ ! -f "$PLANET_FILE" ] || ! cmp -s "$TMP_FILE" "$PLANET_FILE"; then
  changed=yes
fi

if [ "$changed" = "yes" ] || ! is_connected; then
  log "applying updated planet and re-linking (changed=${changed})."
  mv -f "$TMP_FILE" "$PLANET_FILE"
  chmod 644 "$PLANET_FILE"
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active zerotier-one >/dev/null 2>&1; then
    systemctl restart zerotier-one || true
  fi
  log "done. resolved IP in use: ${IP:-unknown}"
else
  rm -f "$TMP_FILE"
  log "in sync, connected to ${ROOT_ID} via ${IP}."
fi
