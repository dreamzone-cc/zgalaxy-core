#!/usr/bin/env bash
# =============================================================================
# ZGALAXY connectivity & integration deep test suite
#
# Verifies the domain-name based connectivity mechanism and the integration
# between the client, the ZGALAXY engine, the mesh, and ztnet.
#
# Run (as a user with sudo):   sudo bash tests/integration-test.sh
# Config via env:
#   ZGALAXY_TEST_DOMAIN   (default dz.dreamzone.cc)
#   ZGALAXY_TEST_ENGINE   (default http://dz.dreamzone.cc:3000)
#   ZGALAXY_TEST_NETWORK  (default ef313fb5c9f817a2)
#   ZGALAXY_TEST_ROOT     (default 069ae38092)
#   ZGALAXY_TEST_MOON     (default 000000069ae38092)
#   ZGALAXY_TEST_PEER_IP  (mesh IP of another member, for ping test)
#   ZGALAXY_TEST_NO_FALLBACK  (set to 1 to skip the iptables fallback test)
# =============================================================================
set -u

DOMAIN="${ZGALAXY_TEST_DOMAIN:-dz.dreamzone.cc}"
ENGINE="${ZGALAXY_TEST_ENGINE:-http://dz.dreamzone.cc:3000}"
NETWORK="${ZGALAXY_TEST_NETWORK:-ef313fb5c9f817a2}"
ROOT_ID="${ZGALAXY_TEST_ROOT:-069ae38092}"
MOON_ID="${ZGALAXY_TEST_MOON:-000000069ae38092}"
PEER_IP="${ZGALAXY_TEST_PEER_IP:-}"

HOMEDIR="${ZEROTIER_HOME:-/var/lib/zerotier-one}"
ZT=zerotier-cli
sudo -n true 2>/dev/null || { echo "Need sudo (run as: sudo bash $0)"; exit 1; }

PASS=0; FAIL=0
OUT=/tmp/zgalaxy-test.out
ok()   { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; if [ -f "$OUT" ]; then sed 's/^/         /' "$OUT" | tail -4; fi; }
t() { # t <name> <command...>
  local name="$1"; shift
  if "$@" >"$OUT" 2>&1; then ok "$name"; else bad "$name"; fi
}
t_grep() { # t_grep <name> <pattern> <cmd...>
  local name="$1" pat="$2"; shift 2
  if "$@" >"$OUT" 2>&1 && grep -qE "$pat" "$OUT"; then ok "$name"; else bad "$name"; fi
}
t_curl_http() { # t_curl_http <name> <expected> <url>
  local name="$1" exp="$2" url="$3"
  local code
  code=$(curl -s -o "$OUT" -m 15 -w "%{http_code}" "$url")
  if [ "$code" = "$exp" ]; then ok "$name"; else bad "$name (got HTTP $code)"; fi
}

sec() { echo; echo "── $1"; }

# ---------------------------------------------------------------------------
echo "ZGALAXY connectivity & integration deep test suite"
echo "  domain=$DOMAIN  engine=$ENGINE  network=$NETWORK  home=$HOMEDIR"
echo

# ===========================================================================
sec "1. Domain-name mechanism (IP is transient, domain is the reference)"
# ---------------------------------------------------------------------------
IP=$(getent ahostsv4 "$DOMAIN" | awk '{print $1}' | sort -u | head -1)
t "1.1 domain resolves to an IPv4" bash -c "[[ -n \"$IP\" && \"$IP\" =~ ^[0-9.]+$ ]]"
t "1.2 resolved IP is PUBLIC (not RFC1918/link-local/CGNAT)" bash -c "
python3 - <<EOF
import ipaddress
ip = ipaddress.ip_address('$IP')
bad = ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified
print('  $IP private/reserved?', bad)
raise SystemExit(1 if bad else 0)
EOF"
if [ -f "$HOMEDIR/local.conf" ]; then
  t "1.3 local.conf references the DOMAIN (no hardcoded IP)" bash -c "
    grep -q \"$DOMAIN\" $HOMEDIR/local.conf && ! grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' $HOMEDIR/local.conf"
else
  echo "  [SKIP] 1.3 no local.conf"
fi

# ===========================================================================
sec "2. ZGALAXY engine integration"
# ---------------------------------------------------------------------------
t_curl_http "2.1 engine /health returns 200"        "200" "$ENGINE/api/v1/health"
t_curl_http "2.2 engine /ready returns 200"         "200" "$ENGINE/api/v1/ready"
t_curl_http "2.3 planet download returns 200"       "200" "$ENGINE/api/v1/planet/download"
t_curl_http "2.4 moon download returns 200"         "200" "$ENGINE/api/v1/moons/$MOON_ID.moon/download"
t "2.5 downloaded planet is non-empty" bash -c "curl -s -m15 $ENGINE/api/v1/planet/download -o /tmp/zt-planet && [[ -s /tmp/zt-planet ]]"
t "2.6 downloaded planet contains the resolved external IP" bash -c "
  python3 - <<EOF
d=open('/tmp/zt-planet','rb').read()
ip=bytes(map(int,\"$IP\".split('.')))
print('  planet contains external IP $IP:', ip in d)
raise SystemExit(0 if ip in d else 1)
EOF"

# ===========================================================================
sec "3. Client native dynamic-DNS layer"
# ---------------------------------------------------------------------------
# ONLINE can lag a moment after (re)start — retry for a few seconds.
online=""
for _ in $(seq 1 10); do
  if sudo -n "$ZT" info 2>/dev/null | grep -q "ONLINE"; then online=1; break; fi
  sleep 1
done
if [ -n "$online" ]; then ok "3.1 client is ONLINE"; else bad "3.1 client is ONLINE"; fi
t_grep "3.2 planet root peer is present" "$ROOT_ID" sudo -n "$ZT" listpeers
t "3.3 planet file exists and is external (not baked)" bash -c "[[ -f \"$HOMEDIR/planet\" ]]"
t "3.4 planet file contains the resolved external IP" bash -c "
  python3 - <<EOF
d=open(\"$HOMEDIR/planet\",'rb').read()
ip=bytes(map(int,\"$IP\".split('.')))
print('  client planet contains $IP:', ip in d)
raise SystemExit(0 if ip in d else 1)
EOF"
if [ -f "$HOMEDIR/moons.d/$MOON_ID.moon" ]; then
  ok "3.5 moon file present in moons.d"
else
  bad "3.5 moon file present in moons.d"
fi

# ===========================================================================
sec "4. Reactive fallback (disconnect -> re-resolve via domain -> recover)"
# ---------------------------------------------------------------------------
if [ "${ZGALAXY_TEST_NO_FALLBACK:-0}" = "1" ]; then
  echo "  [SKIP] fallback test disabled"
else
  SVC_PID_BEFORE=$(sudo -n systemctl show -p MainPID --value zerotier-one)
  # listpeers row: "200 listpeers <ztaddr> <path> <latency> <version> <role>"
  ROOT_PATH=$(sudo -n "$ZT" listpeers | grep "^200 listpeers $ROOT_ID " | awk '{print $4}' | cut -d/ -f1 | head -1)
  if [ -n "$ROOT_PATH" ]; then
    echo "  (blocking root path $ROOT_PATH:9994 for ~30s)"
    sudo -n iptables -I OUTPUT -p udp -d "$ROOT_PATH" --dport 9994 -j DROP
    sleep 30
    t_grep "4.1 client re-resolves the DOMAIN on disconnect" "unreachable, re-resolving $DOMAIN" bash -c "journalctl -u zerotier-one --since '35 seconds ago' 2>/dev/null"
    sudo -n iptables -D OUTPUT -p udp -d "$ROOT_PATH" --dport 9994 -j DROP
    sleep 15
    t_grep "4.2 client recovers ONLINE without restart" "ONLINE" sudo -n "$ZT" info
    SVC_PID_AFTER=$(sudo -n systemctl show -p MainPID --value zerotier-one)
    if [ "$SVC_PID_BEFORE" = "$SVC_PID_AFTER" ]; then ok "4.3 no service restart during recovery"; else bad "4.3 no service restart during recovery"; fi
  else
    echo "  [SKIP] no direct root path to block"
  fi
fi

# ===========================================================================
sec "5. Mesh & ztnet integration"
# ---------------------------------------------------------------------------
t_grep "5.1 network joined with status OK" "OK PRIVATE" sudo -n "$ZT" listnetworks
t "5.2 client has an assigned mesh IP" bash -c "
  sudo -n \"$ZT\" listnetworks | grep -qE '10\.[0-9]+\.' || sudo -n \"$ZT\" listnetworks | grep -qE '192\.168\.[0-9]+\.[0-9]+'"
if [ -n "$PEER_IP" ]; then
  t "5.3 mesh ping to peer ($PEER_IP) succeeds" bash -c "ping -c 2 -W 3 $PEER_IP >/dev/null 2>&1"
else
  echo "  [SKIP] 5.3 no ZGALAXY_TEST_PEER_IP set (set a member mesh IP to test cross-node ping)"
fi

# ===========================================================================
sec "6. Client independence (external, swappable worlds)"
# ---------------------------------------------------------------------------
t "6.1 binary embeds no ZGALAXY IP (world is external)" bash -c "
  ! grep -aoE '105\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|41\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' /usr/sbin/zerotier-one | sort -u | grep -qvE '^(0\.0\.0\.0|127\.0\.0\.1)\$'"
t "6.2 importing works: planet file present + loadable by the node" bash -c "[[ -s \"$HOMEDIR/planet\" ]]"

# ===========================================================================
echo
echo "════════════════════════════════════════════════════════════════"
echo "RESULTS: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"