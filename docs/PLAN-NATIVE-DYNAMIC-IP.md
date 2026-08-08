# Native Dynamic-IP Reconnection — Implementation Plan

> Companion: `docs/ZGALAXY-DYNAMIC-IP-ANALYSIS.md` contains the complete source
> analysis and every proposed solution in detail (with file:line index).

## Problem

The ZGALAXY root server's public IP changes over time (dynamic ISP address).
ZeroTier is **IP-only**: the planet's root `stableEndpoints` contain literal IPs,
and `genmoon`/`mkmoonworld` drop hostnames. Today a companion script/watchdog
(`client/zgalaxy-planet-sync.sh`, Windows PowerShell task) watches the client and
re-supplies a fresh planet when the connection is lost.

This plan replaces the external scripts with a **native, in-binary lightweight
layer**: the client keeps the existing **IP-based** connection mechanism
unchanged and simply resolves the ZGALAXY domain itself to keep the planet's
root endpoint up to date, automatically re-linking when connectivity is lost —
no service restart, no external process, on both Linux and Windows from the same
source.

**Design principle — lightweight layer, not a redesign:** we deliberately do NOT
re-architect the client to be "domain-native". The core connection path stays
100% IP-based (that is ZeroTier's protocol). The only addition is a thin resolver
layer that maps one reference domain (`dz.dreamzone.cc`) → current IPv4 and
feeds that address into the existing mechanism. Impact on the current system is
minimal and reversible.

**Integration & packaging requirements (explicit):**
1. **Native only** — the whole mechanism lives in the application's source code
   and ships inside the compiled binary. No external program/script is required.
2. **Planet is an external, importable file** — the `planet` file stays a
   standalone, runtime-imported artifact read from `<homePath>/planet`. It is
   **never compiled into the binary** (the build keeps `ZT_DEFAULT_WORLD_LENGTH
   0`; no IPs and no planet are baked in).
3. **Modifiable after compilation** — after the binary is built, an operator can
   swap in a different `planet` file or change `zgalaxyDomain` in `local.conf`
   and the client honors it at the next resolution/apply cycle — no rebuild.
4. **Future expansion** — because the planet is data, not code, adding roots,
   planets or domains later requires no source changes.

## Goals

1. Configure the planet domain once (no rebuild when the IP changes).
2. **Reactive-only, no polling**: resolve `dz.dreamzone.cc` → current IPv4 at
   startup, then re-resolve **only when the root becomes unreachable** and apply
   it to the in-memory + persisted planet. While the connection is stable the
   address is deliberately left untouched.
3. Automatic re-link after a disconnect: re-resolve, re-apply, reconnect.
4. Graceful re-link (peer reset), not a process restart.
5. Lightweight + self-healing: if the existing `planet` file is stale, rebuild
   the root endpoint from the domain at startup.
6. Fully optional: if no domain is configured, the client behaves exactly like
   stock ZeroTier (compatible with official / other planets).

## Architecture findings (source analysis)

- The planet is a `World` loaded at startup from the state object
  `ZT_STATE_OBJECT_PLANET` (`Topology` ctor, `node/Topology.cpp:45`), which
  `OneService` maps to `<homePath>/planet` (`service/OneService.cpp:3791`).
- The in-memory planet lives in `Topology::_planet`; roots and their
  `stableEndpoints` are read by:
  - `Topology::isProhibitedEndpoint` (`Topology.cpp:213`) — incoming root
    packets are DROPPED unless the source IP is in the planet's stableEndpoints.
  - `Topology::getRootsToContact` (`Topology.cpp:252`) — the endpoints used for
    WHOIS/pings (this is what `Node::processBackgroundTasks` uses to stay
    connected, `node/Node.cpp:341`).
  - `Topology::_memoizeUpstreams` (`Topology.cpp:451`) — builds `_upstreamAddresses`.
- `World::shouldBeReplacedBy` (`node/World.hpp:162`) requires a NEWER timestamp
  AND a valid ECC signature. Clients do not hold the signing key, so we must NOT
  route endpoint changes through `addWorld()`. Instead we mutate
  `_planet._roots[].stableEndpoints` **in place** and persist. This is safe:
  the signature is only verified for in-band world updates, not on local load.
- The client's main loop (`OneService::run`, `service/OneService.cpp:1309`)
  already ticks: `local.conf` reload, bind refresh, and
  `_node->processBackgroundTasks()` (`:1402`). It also queries
  `_node->online()` (`:1350`), which reflects root reachability
  (`lastReceivedFromUpstream`, `Node.cpp:421`, timeout `ZT_PEER_ACTIVITY_TIMEOUT`
  = 30 s).
- There is no existing `getaddrinfo`/DNS use in the codebase; the resolver must
  be added in the platform/service layer (blocking DNS must not stall the event
  loop).

## Implementation

### 0. Bootstrap (startup self-healing)

The lightweight layer also makes the client self-sufficient at startup:

- If `zgalaxyDomain` is configured and the loaded `_planet` has no root
  endpoints that match the domain's current resolution, the layer resolves the
  domain and applies the endpoints immediately after the node starts.
- Root identity source (never an IP): current `planet` file → optional
  `local.conf` key `zgalaxyRootIdentity` → bundled constant
  `ZT_ZGALAXY_ROOT_IDENTITY` in `node/Topology.cpp` (identity public string).
- This covers the "planet file missing or stale" case with the same
  `setPlanetEndpoints` path; the connection mechanism itself is untouched.

### 1. `node/World.hpp` — endpoint replacement setter

Add a public method so `Topology` can swap a root's endpoints without re-signing:

```cpp
/** Replace the stable endpoints of a root in place (local-only; no re-sign). */
void setRootStableEndpoints(unsigned int rootIndex, const std::vector<InetAddress>& eps)
{
    if (rootIndex < _roots.size())
        _roots[rootIndex].stableEndpoints = eps;
}
```

### 2. `node/Topology.{hpp,cpp}` — apply resolved endpoints + force re-link

Add:

```cpp
/**
 * Replace the planet root(s) stable endpoint(s) with the resolved address(es).
 * Returns true if the planet actually changed and the root peer was reset.
 */
bool setPlanetEndpoints(void* tPtr, const std::vector<InetAddress>& eps);
```

Implementation (under `_peers_m` + `_upstreams_m`):

1. If `_planet` is null/empty or has no roots → return false.
2. **Merge, do not replace** (IPv4 only): keep the **primary root's** existing
   private/LAN endpoints (RFC1918, link-local, CGNAT) so LAN peers keep working,
   then merge the freshly resolved endpoint(s), deduplicated by IP+port. If a
   resolved endpoint has no port, reuse the current root port (default 9994).
   *(Live-fix note: an earlier "replace-only" version removed the LAN endpoint,
   breaking LAN clients via NAT hairpin — the merge semantics fix this.)*
3. If the primary root's merged set is `ipsEqual` (IP+port) to the current one →
   return false (no-op, avoids needless churn).
4. Apply to the **primary root only (index 0)** — the root the configured
   domain belongs to. Other roots (multi-root planets) keep their own endpoints
   untouched.
5. Persist: `serialize()` → `RR->node->stateObjectPut(tPtr,
   ZT_STATE_OBJECT_PLANET, ...)` (same as `addWorld` does at `Topology.cpp:354`).
6. **Force re-link**: erase the primary root's `Peer` so the next background
   tick re-creates it and sends WHOIS/pings to the NEW endpoint (via the
   updated `getRootsToContact`). No process restart.
7. Call `_memoizeUpstreams(tPtr)` to refresh `_upstreamAddresses`.
8. Return true.

*Timing note:* in non-SDK builds `ZT_PEER_ACTIVITY_TIMEOUT` is 500000 ms, so the
node's `online()` flag reacts slowly. Disconnect is instead detected reactively
via `Peer::hasAlivePath(now)` (~19 s, path-heartbeat based) surfaced through
`Topology/Node::isPlanetReachable`. Recovery is re-resolution on that signal —
**not** periodic polling.

### 3. `node/Node.{hpp,cpp}` — public entry point

Add and forward (mirrors `Node::setPhysicalPathConfiguration`):

```cpp
void Node::setPlanetEndpoints(void* tPtr, const std::vector<InetAddress>& eps)
{
    RR->topology->setPlanetEndpoints(tPtr, eps);
}
```

### 4. `node/Constants.hpp` — timing

```cpp
#define ZT_ZGALAXY_DNS_RETRY_INTERVAL  5000   // re-resolve cadence while the root is unreachable (ms)
```

(There is deliberately no periodic interval — the layer is reactive only.)

### 5. `service/OneService.{hpp,cpp}` — configuration + resolver + reactive hook

**Configuration** (optional, stock-compatible):
- Read `_localConfig["zgalaxyDomain"]` (string) in `readLocalSettings()`
  (`OneService.cpp:1520`); environment variable `ZGALAXY_DOMAIN` overrides it.
- Store in a new member `std::string _zgalaxyDomain;`.

**Disconnect detection** (fast, path-based — not the slow online flag):
- `Peer::hasAlivePath(now)` — true if at least one path received within
  `ZT_PATH_HEARTBEAT_PERIOD + 5000` (~19 s).
- `Topology::isPlanetReachable(now)` — true if any upstream (root) peer has an
  alive path.
- `Node::isPlanetReachable(now)` — public forwarding used by OneService.

**Resolver** (non-blocking for the event loop, purely reactive):
- A small `std::thread` (started in `OneService::run()` only when the domain is
  configured, stopped on shutdown) **blocks on a condition variable** — it makes
  **zero DNS queries while the root is reachable**. It resolves only when woken:
  once at startup and whenever a disconnect is detected. On failure it keeps the
  last known IP and records the attempt time so retries happen at a sane cadence
  (every `ZT_ZGALAXY_DNS_RETRY_INTERVAL` while the outage lasts).
- `getaddrinfo` portability: `#ifdef __WINDOWS__` → `winsock2.h` +
  `ws2tcpip.h`; otherwise `<netdb.h>` + `<sys/socket.h>`.

**Apply in main loop** (`for(;;)` at `OneService.cpp:1309`), after the
`processBackgroundTasks` block:
- If `_zgalaxyDomain` is empty → skip (stock behaviour).
- If the root is unreachable (`! _node->isPlanetReachable(now)`) and at least
  `ZT_ZGALAXY_DNS_RETRY_INTERVAL` passed since the last attempt → wake the
  resolver (it re-resolves the domain).
- Whenever a resolved IP is cached, call `_node->setPlanetEndpoints(...)`
  (cheap no-op when unchanged). On a real IP change this drops the root peer so
  the client re-links to the new endpoint — graceful, no restart.

### 6. Docs & packaging

- Update `docs/BUILD.md`, `docs/BUILD-WINDOWS.md`, `README.md`: document
  `local.conf` / `ZGALAXY_DOMAIN`, native behaviour, and mark the companion
  watchdog as optional/legacy.
- Ship a `local.conf` sample in the Windows installer and the Linux install
  script (only if the user opts in; default keeps stock-compatible behaviour).

## Verification (performed on the local Linux client)

1. Build the Linux client; set `zgalaxyDomain` in `local.conf`; confirm
   `zerotier-cli listpeers` shows the ZGALAXY root DIRECT at the current public
   IP (resolved via the domain). ✅
2. Startup: journal shows `resolved dz.dreamzone.cc -> <IP>` then DIRECT
   connection — the domain IP was fetched and used to start the connection. ✅
3. Stability: during 60 s of stable connection, **zero** DNS resolutions were
   performed (reactive only). ✅
4. Disconnect: blocking UDP 9993/9994 to the root made the layer log
   `root unreachable, re-resolving` and re-resolve every
   `ZT_ZGALAXY_DNS_RETRY_INTERVAL`; after unblocking the client re-linked DIRECT
   to the root — **no service restart**. ✅
5. Regression: without `zgalaxyDomain` the client behaves exactly as stock; the
   no-IP binary still embeds zero IPs. ✅
6. Repeat on Windows after building via `windows/build-windows.ps1` (pending).

## Rollout order (per user directive)

1. Linux client first (implement → build → verify on 192.168.1.20 / local box).
2. Windows client second (same source compiles for Windows; build + installer).
3. Keep companion watchdog files in-tree but mark them optional/legacy.
