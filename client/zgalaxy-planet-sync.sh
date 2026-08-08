#!/usr/bin/env bash
# =============================================================================
# zgalaxy-planet-sync — reactive dynamic-IP resolver for ZGALAXY One clients
#
# This is an ACTION, not a periodic job. It is invoked by the watchdog
# (zgalaxy-watch.sh / zgalaxy-watch.service) ONLY when the client loses its
# connection to the ZGALAXY root.
#
# Behaviour:
#   - if the client is still connected to the ZGALAXY root -> do nothing,
#   - if disconnected -> resolve dz.dreamzone.cc to its current IP, fetch the
#     latest planet from the ZGALAXY engine, apply it and restart the client
#     so it re-links with the network automatically.
# =============================================================================
set -euo pipefail

DOMAIN="${ZGALAXY_DOMAIN:-dz.dreamzone.cc}"
ROOT_ID="${ZGALAXY_ROOT_ID:-069ae38092}"
PLANET_URL="${ZGALAXY_PLANET_URL:-http://${DOMAIN}:3000/api/v1/planet/download}"
PLANET_FILE="/var/lib/zerotier-one/planet"
TMP_FILE="/var/lib/zerotier-one/planet.new"
CURL="${CURL:-curl}"

log() { echo "[zgalaxy-planet-sync] $*"; }

is_connected() {
  command -v zerotier-cli >/dev/null 2>&1 || return 1
  # listpeers rows: "200 listpeers <addr> <path> <latency> <version> <role>"
  zerotier-cli listpeers 2>/dev/null | awk -v r="$ROOT_ID" '$3==r && $4!="-" && $5!="-1" {found=1} END {exit !found}'
}

resolve_domain_ip() {
  local ip
  if command -v getent >/dev/null 2>&1; then
    ip="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)"
  fi
  if [ -z "$ip" ] && command -v dig >/dev/null 2>&1; then
    ip="$(dig +short A "$DOMAIN" 2>/dev/null | grep -E '^[0-9.]+$' | head -1)"
  fi
  [ -n "$ip" ] && echo "$ip" || true
}

# Connected → nothing to do (reactive only; no periodic fetching).
if is_connected; then
  exit 0
fi

log "disconnected from ${ROOT_ID} — resolving ${DOMAIN} and re-linking."

IP="$(resolve_domain_ip || true)"
log "resolved ${DOMAIN} -> ${IP:-unknown}"

if ! "${CURL}" -fsS -m 20 -o "$TMP_FILE" "$PLANET_URL" 2>/dev/null; then
  rm -f "$TMP_FILE"
  log "planet fetch failed; will retry on next check."
  exit 0
fi

mv -f "$TMP_FILE" "$PLANET_FILE"
chmod 644 "$PLANET_FILE"

if command -v systemctl >/dev/null 2>&1 && systemctl is-active zerotier-one >/dev/null 2>&1; then
  systemctl restart zerotier-one || true
fi
log "re-linked. resolved IP in use: ${IP:-unknown}"
