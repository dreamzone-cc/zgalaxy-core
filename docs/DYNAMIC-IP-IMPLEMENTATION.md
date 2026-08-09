# ZGALAXY One — Native Dynamic-IP Layer: Implementation & Change Documentation

This document is the comprehensive, authoritative record of **every change made**
to the `dreamzone-cc/zgalaxy-core` client fork (and its alignment with the
`dreamzone-cc/ZGALAXY` engine) to solve the dynamic-IP connectivity problem.

Companion docs: `docs/ZGALAXY-DYNAMIC-IP-ANALYSIS.md` (source analysis),
`docs/PLAN-NATIVE-DYNAMIC-IP.md` (plan), `docs/USING-DOMAIN-NAMES-INSTEAD-OF-IPS.md`
(problem→solution), and `docs/PLANET-MOON-ARCHITECTURE.md` (in the engine repo —
planet/moon architecture unification).

---

## 1. What was changed and why

### Problem
The ZGALAXY root's public IP is dynamic. ZeroTier is **IP-only** (the planet's
root `stableEndpoints` are literal IPs; build tools drop hostnames). When the
public IP changes, existing clients keep pinging the old IP and go offline.

### Solution (native, lightweight layer — no redesign)
Keep the IP-based connection mechanism unchanged. Add a thin, **in-binary,
reactive** layer: one reference domain (`dz.dreamzone.cc`) is the only
configuration; the client resolves it at startup and re-resolves it only when
the root becomes unreachable, then updates the planet's root endpoint **in
place** (LAN endpoints preserved, resolved public IPs merged — multi-A) and
re-links **gracefully** (peer reset, no restart).

---

## 2. Detailed source changes (zgalaxy-core)

### 2.1 `node/World.hpp` — in-place endpoint setter
Added public method:
```cpp
void setRootStableEndpoints(unsigned int rootIndex, const std::vector<InetAddress>& eps);
```
Swaps a root's `stableEndpoints` **in place**, leaving world id/timestamp/
signature untouched. Required because `World::shouldBeReplacedBy` demands a newer
timestamp + valid signature (clients do not hold the signing key), so endpoint
updates must not go through `addWorld()`.

### 2.2 `node/Topology.{hpp,cpp}` — apply resolved endpoints + reachability
- `bool setPlanetEndpoints(void* tPtr, const std::vector<InetAddress>& eps);`
  - Locks `_peers_m` then `_upstreams_m` (matches `addWorld` ordering).
  - Operates on the **primary root only (index 0)** — the root the configured
    domain belongs to; other roots in a multi-root planet stay untouched.
  - Merges: keeps the primary root's existing **private/LAN** endpoints
    (RFC1918 / link-local / CGNAT via helper `_zgIsPrivateIPv4`), then merges
    the resolved endpoint(s), deduplicated by IP+port. If a resolved endpoint
    has no port, the current root port is reused (default 9994).
  - **No-op** (returns false) if the primary root's endpoints are unchanged.
  - Persists the updated planet via `stateObjectPut` (`ZT_STATE_OBJECT_PLANET`
    → `<homePath>/planet`).
  - **Graceful re-link**: erases the primary root `Peer` so the next background
    pass re-creates it and sends WHOIS/pings to the new endpoint (via
    `getRootsToContact`); calls `_memoizeUpstreams`.
- `bool isPlanetReachable(int64_t now);`
  - True if at least one upstream (root) peer has an **alive path**
    (`Peer::hasAlivePath`). Used as the fast disconnect signal.

### 2.3 `node/Peer.hpp` — path aliveness
- `bool hasAlivePath(int64_t now) const;`
  - True if any path `alive(now)` — i.e. received within
    `ZT_PATH_HEARTBEAT_PERIOD + 5000` (~19 s). This is the reactive disconnect
    detector (far faster than the node's `online()` flag, which is 500 s in
    non-SDK builds).

### 2.4 `node/Node.{hpp,cpp}` — public API
- `bool setPlanetEndpoints(void* tPtr, const std::vector<InetAddress>& eps);`
  → forwards to `RR->topology->setPlanetEndpoints(...)` (returns changed?).
- `bool isPlanetReachable(int64_t now);` → forwards to `Topology`.

### 2.5 `node/Constants.hpp` — timing
- `#define ZT_ZGALAXY_DNS_RETRY_INTERVAL 5000` — re-resolve cadence while the
  root is unreachable. There is deliberately **no periodic interval**.

### 2.6 `service/OneService.cpp` — configuration, resolver, reactive loop
- **Config**: `"zgalaxyDomain"` in `local.conf` (parsed in `readLocalSettings`,
  reloaded at runtime when `local.conf` changes), overridable by env
  `ZGALAXY_DOMAIN`. Empty = feature disabled (stock behaviour).
- **State members**: `_zgalaxyDomain`, `_zgalaxyResolvedIps` (all A records),
  `_zgalaxyLastDnsCheck`, `Mutex _zgalaxyDns_m`, `std::mutex _zgalaxyDnsMutex`,
  `std::condition_variable _zgalaxyDnsCv`, `std::thread _zgalaxyDnsThread`,
  `std::atomic<bool> _zgalaxyDnsRun`.
- **Resolver thread** (`_zgalaxyDnsLoop`, started unconditionally in `run()`):
  blocks on the condition variable — **zero DNS queries while the root is
  reachable**. Woken once at startup and on each detected disconnect. Resolves
  **all** IPv4 A records (`_resolveDomainIPv4s`, `getaddrinfo`, guarded for
  `__WINDOWS__` vs POSIX). On failure keeps last known IPs.
- **Main loop hook** (after `processBackgroundTasks`): if the domain is set and
  the root is unreachable for ≥ `ZT_ZGALAXY_DNS_RETRY_INTERVAL`, wake the
  resolver; whenever resolved IPs exist, call `setPlanetEndpoints` (cheap
  no-op when unchanged). Logs to stderr (`zgalaxy: ...`) for observability.
- **Thread lifecycle**: started before the main I/O loop; stopped+joined in
  `run()` cleanup (before `delete _node`) and as a safety net in the destructor.
- **Thread safety**: `_zgalaxyDomain`, `_zgalaxyResolvedIps`,
  `_zgalaxyLastDnsCheck` are always accessed under `_zgalaxyDns_m` (readers in
  both the main loop and the resolver thread; the writer in `readLocalSettings`).

### 2.7 `docs/` (zgalaxy-core) — new/updated
- `docs/ZGALAXY-DYNAMIC-IP-ANALYSIS.md` — full source analysis (file:line).
- `docs/PLAN-NATIVE-DYNAMIC-IP.md` — execution plan + verification.
- `docs/USING-DOMAIN-NAMES-INSTEAD-OF-IPS.md` — problem→solution + flow.

### 2.8 ZGALAXY engine repo
- `docs/PLANET-MOON-ARCHITECTURE.md` — deep examination of the unified
  planet/moon pipeline (`moon.json` + `zerotier-idtool` + `mkmoonworld`) and the
  unification matrix with the client layer.

---

## 3. Behaviour contract

| Case | Behaviour |
|---|---|
| No `zgalaxyDomain` configured | Exactly stock ZeroTier; feature fully disabled. |
| First run / startup (domain set) | Resolve once → merge IPs into planet → connect. |
| Stable connection | **No** DNS queries, no endpoint changes (stability). |
| Disconnect detected (no alive root path ≥ 5 s) | Re-resolve → merge new IPs → graceful re-link. |
| Root's public IP changed | Client self-heals automatically (proven live through 3 real IP changes). |
| LAN peers | Local endpoint preserved; unaffected by public IP changes (no hairpin dependency). |
| DNS failure during re-resolve | Keep last known IPs; retry every 5 s while unreachable. |
| Multi-root planet | Only the primary root (index 0) is refreshed; others untouched. |
| Runtime `local.conf` change | Domain re-read under lock; thread is always running, so the feature activates/deactivates without restart. |

---

## 4. Integration verification (performed, live)

| # | Check | Result |
|---|---|---|
| 1 | Build (`make`, Linux) — no errors | ✅ `zerotier-one` 1.16.2 |
| 2 | Binary embeds no IPs (only 0.0.0.0/127.0.0.1) | ✅ |
| 3 | Start with `zgalaxyDomain` → `info` ONLINE, root DIRECT, network `shared-whale` OK (IP assigned) | ✅ |
| 4 | Real dynamic-IP changes during testing: `105.97.148.187 → 41.200.151.128 → 105.105.114.137` — planet re-merged (LAN + new public) each time | ✅ |
| 5 | Stability: 40–60 s of stable connection → **zero** DNS resolutions | ✅ |
| 6 | Disconnect (UDP 9993/9994 blocked both directions) → `root unreachable, re-resolving` every 5 s; after unblock → auto re-link DIRECT | ✅ |
| 7 | No service restart during any recovery (same session) | ✅ |
| 8 | Legacy external watchdog disabled → native layer handles everything alone | ✅ |
| 9 | CPU during idle: 0.2% (no busy loop; `_phy.poll` not skipped) | ✅ |
| 10 | Stock behaviour (no domain): connects normally, no `zgalaxy` logs | ✅ |

---

## 5. Configuration & usage

Linux service (data dir `/var/lib/zerotier-one`):

```json
// /var/lib/zerotier-one/local.conf
{
  "zgalaxyDomain": "dz.dreamzone.cc"
}
```

Or environment: `ZGALAXY_DOMAIN=dz.dreamzone.cc` (overrides local.conf).

Observe activity:
```sh
journalctl -u zerotier-one | grep zgalaxy
```

---

## 6. Known limitations & future work

1. **Fresh install with no planet file**: the layer needs an imported planet
   (it carries the root identity). Bootstrapping a world purely from the domain
   requires bundling the root identity constant — documented in the plan
   (section 0), not yet implemented.
2. **Moons on the client**: the layer refreshes the planet root only. Moons use
   the same IP-only model; extending the reactive layer to moons is future work
   (mirrors the engine's unified moon pipeline).
3. **Feature is for leaf clients**: don't set `zgalaxyDomain` on the root /
   controller node itself.
4. **Server-side DDNS** (engine, periodic 5 min) and the **client-side reactive
   layer** are complementary by design: the server keeps the canonical planet
   fresh for new joiners; the client self-heals existing nodes.

---

## 7. File index (zgalaxy-core)

| File | Lines added | Change |
|---|---|---|
| `node/World.hpp` | +16 | `setRootStableEndpoints` |
| `node/Topology.hpp` | +27 | `setPlanetEndpoints`, `isPlanetReachable` |
| `node/Topology.cpp` | +~135 | implementations + `_zgIsPrivateIPv4` |
| `node/Node.hpp` | +21 | `setPlanetEndpoints`, `isPlanetReachable` |
| `node/Node.cpp` | +10 | forwarders |
| `node/Peer.hpp` | +26 | `hasAlivePath` |
| `node/Constants.hpp` | +10 | `ZT_ZGALAXY_DNS_RETRY_INTERVAL` |
| `service/OneService.cpp` | +~165 | config, resolver thread, reactive loop, lifecycle |
| `docs/*.md` | new | 3 analysis/plan docs |

---

## 8. Full planet/moon independence & domain-based connectivity (v2)

The client is now **fully independent** of any specific planet/moon set — worlds
are external, swappable files, and the domain-name mechanism covers **both
planets and moons**:

### 8.1 Auto-import from ZGALAXY (no manual file handling)
- Config `"zgalaxyEngineUrl"` (e.g. `http://dz.dreamzone.cc:3000`). At startup
  the client downloads the current `planet` (`GET /api/v1/planet/download`) and
  every configured moon (`GET /api/v1/moons/<id>.moon/download`) using the
  engine's public endpoints, and writes them into the home directory before the
  node starts. Worlds update automatically; no recompilation, no manual
  intervention.

### 8.2 Reactive domain resolution for planets AND moons
- Config `"zgalaxyMoons": [{ "id": "<16-hex world id>", "domain": "…" }]`.
- The resolver thread resolves the planet domain and every moon domain (all A
  records). `Topology::setMoonEndpoints` merges private/LAN + resolved
  endpoints into the moon's root in place, persists the moon, and re-links its
  root peer. Disconnect fallback is per-world (`Topology::isWorldReachable`).

### 8.3 Bounded validation (address verification)
- Config `"zgalaxyValidateIntervalMinutes"` (default 10; 0 = pure reactive).
  At the configured cadence the client re-resolves all worlds and applies
  changes (no-op when unchanged) — deliberate and gentle to avoid excessive DNS
  load. The disconnect fallback re-resolves immediately when needed.

### 8.4 Runtime moons.d watcher (no restart)
- The client scans `moons.d` every 10 s and **orbits newly added** `.moon`
  files and **deorbits removed** ones — planets/moons can be dropped in or
  taken out without restarting.

### 8.5 Independence guarantees
- No baked world; planet/moon files fully external.
- One planet + any number of moons (ZeroTier's model).
- Adding/removing/swapping moons = placing/removing `.moon` files in `moons.d`
  (auto-detected) or configuring `zgalaxyMoons` + restart for auto-import.
