# Using Domain Names Instead of IPs — Client Connectivity

This document lays out, end to end:

1. the **problems** we face in the ZGALAXY One client,
2. the **source-code evidence** that pinpoints the cause of each problem,
3. the **proposed solutions**, and
4. **how the connection flow will use a domain name instead of a fixed IP**.

All findings reference the `zgalaxy-core` fork (ZeroTier 1.16.2).
Companion docs: `docs/ZGALAXY-DYNAMIC-IP-ANALYSIS.md` (full analysis) and
`docs/PLAN-NATIVE-DYNAMIC-IP.md` (execution plan).

---

## 1. The problems we face in the client

| # | Problem | Symptom observed |
|---|---|---|
| P1 | The planet file stores **literal IP addresses** as root endpoints. | Rebuilding the client each time the public IP changes. |
| P2 | When the root's public IP changes, the client **silently drops** the root. | Peer stays at `-1 RELAY` / OFFLINE; `listpeers` never recovers. |
| P3 | The client keeps pinging the **old** IP forever and cannot re-learn the new one by itself. | Permanent outage until manual intervention. |
| P4 | Recovery currently depends on **external scripts** (`zgalaxy-planet-sync.sh`, PowerShell task) that rewrite the `planet` file and **restart the service**. | Extra process, per-OS duplication, brief network drop, manual install steps. |
| P5 | ZeroTier's core is **IP-only**: domain names are silently discarded when a planet/moon is generated. | `genmoon` / `mkmoonworld` drop hostname endpoints (verified). |
| P6 | No DNS resolution exists anywhere in the client code. | Nothing can translate `dz.dreamzone.cc` → current IP at run time. |
| P7 | The fix must behave identically on **Linux and Windows**. | Two separate watchdog implementations to keep in sync. |

---

## 2. Source-code evidence (what in the code causes each problem)

### P1 — IPs are baked into the planet
- The planet is a `World` whose roots carry `std::vector<InetAddress> stableEndpoints`
  (`node/World.hpp:83`). `InetAddress` holds an IP + port, **not** a hostname.
- The engine side builds it from DNS-resolved IPs; the client loads it verbatim
  from the state object `ZT_STATE_OBJECT_PLANET` (`node/Topology.cpp:45`) which
  `OneService` maps to `<homePath>/planet` (`service/OneService.cpp:3791`).
- There is **no baked default world** in our builds
  (`node/Topology.cpp:36`, `ZT_DEFAULT_WORLD_LENGTH 0`), so the client is
  entirely at the mercy of whatever `planet` file is supplied.

### P2 — the client drops the root after an IP change
- `Topology::isProhibitedEndpoint` (`node/Topology.cpp:213`) rejects **incoming**
  packets from a root whose source IP is not among the planet's `stableEndpoints`:

  > For roots the only permitted addresses are those defined. This adds just a
  > little bit of extra security against spoofing, replaying, etc.

  After the root's IP changes, its HELLO/OK packets come from the new IP → the
  client discards them.

### P3 — no self-healing to the new IP
- `Topology::getRootsToContact` (`node/Topology.cpp:252`) builds the WHOIS/ping
  endpoint list **only** from the current `_planet.roots()` (stale IPs).
- `Node::processBackgroundTasks` (`node/Node.cpp:341`) uses exactly that list for
  keep-alive; the root peer is only deemed dead after
  `ZT_PEER_ACTIVITY_TIMEOUT` (30000 ms, `node/Constants.hpp:510`).
- Because the peer's paths point at the old IP, nothing in the core ever
  queries the domain.

### P4 — recovery is external today
- The companion module rewrites `<homePath>/planet` and restarts the service
  (`client/zgalaxy-planet-sync.sh`, `client/zgalaxy-watch.{sh,service}`,
  `windows/watchdog/*.ps1`). It works, but it is a **process-level workaround**.

### P5 — hostnames are dropped at generation time
- `World::Root` and `World::serialize` (`node/World.hpp:83,183`) only encode IP
  endpoints; `genmoon`/`mkmoonworld` parse `stableEndpoints` as IPs.
  ZeroTier's protocol (packets, `HELLO`, path finding) is IP-only by design.

### P6 — no DNS anywhere
- A repo-wide search finds **zero** `getaddrinfo` / `gethostbyname` call sites.
  The core is deliberately DNS-free; the system resolver is never used.

### P7 — platform split of the workaround
- The Linux fix (`systemd`) and the Windows fix (Task Scheduler) are distinct
  code paths that must be maintained together.

---

## 3. Proposed solutions

### S1 — Make the client resolve the domain itself (native, primary)
Add a small DNS resolver inside the client (service layer, non-blocking thread)
that maps the configured domain to the current IPv4 and **applies it to the
planet in place**, without a re-signed world and without a restart:

- `World::setRootStableEndpoints(...)` — in-place endpoint swap (`node/World.hpp`).
- `Topology::setPlanetEndpoints(tPtr, eps)` — update `_planet` root endpoints,
  persist to `<homePath>/planet`, then **drop the root `Peer`** so the core
  re-runs WHOIS/ping against the new endpoint (graceful re-link).
- `Node::setPlanetEndpoints(...)` — thin public API forwarding to `Topology`
  (mirrors the existing `Node::setPhysicalPathConfiguration` pattern,
  `node/Node.cpp:767`).
- Config: `"zgalaxyDomain"` in `local.conf` (parsed in `readLocalSettings`,
  `service/OneService.cpp:1520`), overridable by env `ZGALAXY_DOMAIN`.

### S2 — Periodic + reactive resolution (replaces the watchdog)
- **Periodic:** resolve every `ZT_ZGALAXY_DNS_INTERVAL` (30 s) in the service
  main loop (`service/OneService.cpp:1309`); apply when the IP differs.
- **Reactive:** when `_node->online()` is false
  (`service/OneService.cpp:1350`) and the last DNS check is older than
  `ZT_ZGALAXY_DNS_RETRY_INTERVAL` (5 s), force an immediate resolve + apply +
  re-link. Same behaviour as the watchdog, but graceful (peer reset, no restart).

### S3 — Keep an optional, signed in-band world update path (future)
Longer term the engine can push a signed planet update to clients in-band; not
needed for the DNS fix (S1/S2 cover the live-IP case immediately).

### S4 — Retire / mark the companion watchdog as legacy
Keep the scripts in-tree for fallback, but they are no longer required for
normal operation.

---

## 4. How the connection will use a domain name instead of an IP

**Framing — a lightweight layer, not a redesign.** We keep the existing
IP-based connection mechanism exactly as is (that is ZeroTier's protocol). The
only addition is a thin resolver layer: one reference domain
(`dz.dreamzone.cc`) is queried at startup and again on disconnect, and the
resulting current IPv4 is fed into the existing mechanism. No IP is ever
configured, baked, or managed by the operator — the domain is the only reference
source, and the layer is **reactive only**: the address is never refreshed while
the connection is stable.

Config (one time):
```
local.conf:  { "zgalaxyDomain": "dz.dreamzone.cc" }
or env:      ZGALAXY_DOMAIN=dz.dreamzone.cc
```

Runtime flow (reactive — no periodic polling):
```
  FIRST RUN / STARTUP
        |  resolver thread (getaddrinfo) — resolves ONCE
        v
   resolved IPv4 (e.g. 41.200.151.128)   -> Node::setPlanetEndpoints(ip:9994)
        v
   client connects DIRECT to the root

  STABLE CONNECTION  (root path alive ~every 19 s)
        |  resolver thread BLOCKS — zero DNS queries, zero updates

  DISCONNECT  (root path dead -> isPlanetReachable(now) == false)
        |  after ZT_ZGALAXY_DNS_RETRY_INTERVAL (5 s)
        v
   re-resolve dz.dreamzone.cc -> current IPv4
        v
   Node::setPlanetEndpoints(ip:9994)
        |
        v
   Topology::setPlanetEndpoints
        |  update _planet.roots[].stableEndpoints in place
        |  persist -> <homePath>/planet
        |  drop root Peer -> fresh WHOIS/ping to NEW IP
        v
   Client re-links with the root automatically (no restart)
```

Key guarantees:
- **No fixed IP in the client** — only the domain name is configured.
- **No service restart** — only the affected root peer is reset.
- **Stable while connected** — zero DNS queries and zero updates during a
  healthy connection; re-resolution happens only at startup and on disconnect.
- **Self-healing** — works across IP changes with zero manual intervention.
- **Stock-compatible** — with no domain configured the client behaves exactly
  like unmodified ZeroTier.
- **Cross-platform** — the same source compiles for Linux and Windows
  (resolver guarded by `#ifdef __WINDOWS__`).

---

## 5. Rollout order

1. Linux client (implement → build → verify on 192.168.1.20 / local box).
2. Windows client (same source → build via `windows/build-windows.ps1`).
3. Update docs/install scripts; mark companion watchdog as optional.
