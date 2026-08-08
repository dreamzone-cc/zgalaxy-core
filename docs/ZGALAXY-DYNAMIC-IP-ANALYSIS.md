# ZGALAXY Native Dynamic-IP Reconnection — Analysis & Proposed Solution

Status: analysis complete — ready to implement
Scope: Linux client first, Windows client second (same source)
Companion: `docs/PLAN-NATIVE-DYNAMIC-IP.md` (condensed execution plan)

---

## 1. Objective

Replace the external companion watchdog (`client/zgalaxy-planet-sync.sh` +
`zgalaxy-watch.{sh,service}`, and the Windows PowerShell scheduled task) with a
**native, in-binary** mechanism so that a ZGALAXY One client:

- depends on a **domain name** (`dz.dreamzone.cc`), not on a fixed IP;
- resolves the domain **periodically and on demand** to obtain the current IPv4
  of the ZGALAXY root;
- uses that address for its connection to the root;
- on **connection loss**, automatically re-queries the domain, applies the
  updated address and **re-links without manual intervention and without a
  process restart**.

The same source compiles for Linux and Windows.

---

## 2. What was analyzed

All findings below are grounded in the actual fork source
(`zgalaxy-core` branch, ZeroTier 1.16.2).

### 2.1 Planet (World) lifecycle

- The planet is a `World` object. At startup `Topology` loads it from the state
  object `ZT_STATE_OBJECT_PLANET` (`node/Topology.cpp:45`) and adds it via
  `addWorld(...)`.
- `OneService` maps that state object to the **planet file**:
  - read/write path: `<homePath>/planet` (`service/OneService.cpp:3791` /
    `:3944`, `stateObjectGet`/`stateObjectPut` callbacks).
- The current build ships **without a baked default world**
  (`node/Topology.cpp:36` `ZT_DEFAULT_WORLD_LENGTH 0`), so the client is
  IP-agnostic and relies on a `planet` file supplied by the companion module or
  operator.

### 2.2 Where the root endpoint is used (the 3 readers)

| Reader | File:Line | Consequence |
|---|---|---|
| `Topology::isProhibitedEndpoint` | `node/Topology.cpp:213` | Incoming packets from a root are **dropped** unless the source IP is in the planet's `stableEndpoints`. When the root's public IP changes, the client silently rejects it. **This is the core failure.** |
| `Topology::getRootsToContact` | `node/Topology.cpp:252` | Supplies the endpoints used for WHOIS / keep-alive pings of roots. Built from `_planet.roots()` (+ moons). |
| `Topology::_memoizeUpstreams` | `node/Topology.cpp:451` | Maintains `_upstreamAddresses` (the set of root addresses) and pre-creates root `Peer` objects. |

### 2.3 Connectivity monitoring (the hook for "online / offline")

- `Node::processBackgroundTasks` (`node/Node.cpp:318`) runs every
  `ZT_PING_CHECK_INTERVAL` (5000 ms, `node/Constants.hpp:364`):
  - calls `getRootsToContact` (`Node.cpp:341`),
  - computes `lastReceivedFromUpstream` over those roots (`Node.cpp:353`),
  - sets `_online = ((now - lastReceivedFromUpstream) < ZT_PEER_ACTIVITY_TIMEOUT)`
    (`Node.cpp:421`), where `ZT_PEER_ACTIVITY_TIMEOUT` = 30000 ms
    (`Constants.hpp:510`),
  - posts `ZT_EVENT_ONLINE` / `ZT_EVENT_OFFLINE` (`Node.cpp:422`).
- `OneService` main loop queries `_node->online()` directly
  (`service/OneService.cpp:1350`) — a ready-made reactive trigger.

### 2.4 Why a client-side endpoint swap cannot go through `addWorld`

- `World::shouldBeReplacedBy` (`node/World.hpp:162`) accepts an update only if:
  `same id AND newer timestamp AND ECC-valid signature` (verified against
  `_updatesMustBeSignedBy`).
- Clients do not hold the ZGALAXY signing key → they **cannot** produce a
  re-signed world.
- **Conclusion:** endpoint changes must mutate `_planet._roots[].stableEndpoints`
  **in place** and persist. This is safe because the signature is only verified
  for in-band world updates, **not** on local load from the state object
  (a NULL current world is always accepted, `World.hpp:164`).

### 2.5 World data model (relevant details)

- `World::Root { Identity identity; std::vector<InetAddress> stableEndpoints; }`
  (`node/World.hpp:83`).
- Limits: `ZT_WORLD_MAX_ROOTS` = 4,
  `ZT_WORLD_MAX_STABLE_ENDPOINTS_PER_ROOT` = 32
  (`node/World.hpp:29,34`).
- `ZT_WORLD_ID_ZGALAXY` = 149604618 (`node/World.hpp:48`).
- Serialized layout (`World::serialize`, `World.hpp:183`):
  `type(1) id(8) ts(8) updatesMustBeSignedBy(pub) signature(ECC)
  numRoots(1) { identity, numEps(1), eps... }`.

### 2.6 API surface available to the service layer

- `Node::planet()` / `Node::moons()` getters only (`node/Node.hpp:180-181`).
- **No public `Node::setWorld`.** The `setworld` control-plane command exists
  in `one.cpp:1620` (`genmoon`/planet JSON → world file) but is an offline
  tool, not a live API.
- `Topology::addWorld` is public but unusable for us (see 2.4).
- Pattern to follow: `Node::setPhysicalPathConfiguration`
  (`node/Node.cpp:767`) — a thin public `Node` method forwarding to
  `RR->topology->...`.

### 2.7 Service main loop (where to hook)

`OneService::run` (`service/OneService.cpp:1299` onward):
- `for(;;)` loop with `Phy::poll(delay)` (`:1441`);
- periodic blocks already present:
  - `local.conf` reload every `ZT_LOCAL_CONF_FILE_CHECK_INTERVAL` (`:1332`),
  - bind refresh / interface sync (`:1345`),
  - `_node->processBackgroundTasks(...)` when due (`:1402`);
- `readLocalSettings()` (`:1520`) parses `local.conf` into
  `nlohmann::json _localConfig` (`:1560`) and can be extended with a custom key.

### 2.8 Networking / DNS facts

- **No `getaddrinfo`/`gethostbyname` usage anywhere** in the codebase
  (ZeroTier deliberately avoids system DNS). The resolver must be added in the
  platform/service layer.
- `InetAddress` supports `InetAddress(const char* ipSlashPort)`,
  `InetAddress(const uint32_t ipv4, unsigned int port)`, `ipsEqual()`
  (`node/InetAddress.hpp:127,123,452`).
- The engine's planet builder resolves `dz.dreamzone.cc` → IPv4 and bakes the
  current IP + port **9994** into `stableEndpoints` at build time
  (`planetService` in the ZGALAXY engine repo).

### 2.9 Timing constants available

| Constant | Value | Used for |
|---|---|---|
| `ZT_CORE_TIMER_TASK_GRANULARITY` | 60 ms | minimal tick granularity |
| `ZT_PING_CHECK_INTERVAL` | 5000 ms | ping/WHOIS loop |
| `ZT_PEER_PING_PERIOD` | 60000 ms | peer keep-alive |
| `ZT_PEER_ACTIVITY_TIMEOUT` | 30000 ms | online/offline判定 |
| `ZT_HOUSEKEEPING_PERIOD` | 30000 ms | periodic cleanup |

---

## 3. Root-cause summary

A dynamic-IP outage on the ZGALAXY root manifests as:

1. The root's packets now arrive from a **new source IP**.
2. `isProhibitedEndpoint` (**2.2**) drops them because the IP is not in the
   planet's `stableEndpoints`.
3. `lastReceivedFromUpstream` goes stale → client goes OFFLINE after 30 s.
4. The client keeps pinging/WHOIS at the **old** IP (from `getRootsToContact`)
   and never recovers on its own.

Today this is repaired externally by re-supplying a whole new `planet` file and
restarting the client. The proposed solution fixes it **internally and
gracefully**.

---

## 4. Design principles

1. **Domain-driven, not IP-driven:** the only config is the domain name.
2. **Reactive + periodic:** periodic cheap resolution; immediate action on loss.
3. **Graceful:** reset the affected root `Peer` (fresh WHOIS/ping to the new
   endpoint) — no service restart, no network flapping for peers.
4. **Optional:** no domain configured → behaviour identical to stock ZeroTier
   (fully compatible with other planets).
5. **Single source, two platforms:** resolver isolated behind
   `#ifdef _WIN32` (winsock) vs POSIX (`netdb.h`).

---

## 5. Proposed solution (detailed)

### 5.1 `node/World.hpp` — in-place endpoint setter

```cpp
/** Replace the stable endpoints of a root in place (local-only; no re-sign). */
void setRootStableEndpoints(unsigned int rootIndex, const std::vector<InetAddress>& eps)
{
    if (rootIndex < _roots.size())
        _roots[rootIndex].stableEndpoints = eps;
}
```

### 5.2 `node/Topology.{hpp,cpp}` — apply resolved endpoints + force re-link

New public method (declared in `Topology.hpp`, implemented in `Topology.cpp`):

```cpp
/**
 * Replace the planet root(s) stable endpoint(s) with the resolved address(es).
 * Returns true if the planet actually changed and the root peer was reset.
 */
bool setPlanetEndpoints(void* tPtr, const std::vector<InetAddress>& eps);
```

Implementation steps (locking `_peers_m` + `_upstreams_m`, matching
`addWorld` at `Topology.cpp:290`):

1. If `_planet` is null/empty or has no roots → return false.
2. Normalize: keep IPv4 entries only; if none supplied, reuse the current
   endpoint's port (default 9994) for each resolved IP.
3. If the new set is `ipsEqual` to the current root endpoints → return false
   (no-op to avoid churn).
4. Apply to **every** root of the planet via `setRootStableEndpoints(i, eps)`
   (multi-root consistency).
5. Persist: `serialize()` → `RR->node->stateObjectPut(tPtr,
   ZT_STATE_OBJECT_PLANET, ...)` (same call `addWorld` uses, `Topology.cpp:354`).
6. **Force re-link:** erase the root `Peer` objects from `_peers` so the next
   background tick re-creates them and sends WHOIS/pings to the new endpoint
   (fresh values from `getRootsToContact`).
7. `_memoizeUpstreams(tPtr)` to refresh `_upstreamAddresses`.
8. Return true.

### 5.3 `node/Node.{hpp,cpp}` — public entry point

```cpp
void Node::setPlanetEndpoints(void* tPtr, const std::vector<InetAddress>& eps)
{
    RR->topology->setPlanetEndpoints(tPtr, eps);
}
```

### 5.4 `node/Constants.hpp` — timing

```cpp
#define ZT_ZGALAXY_DNS_INTERVAL       30000   // periodic resolve (ms)
#define ZT_ZGALAXY_DNS_RETRY_INTERVAL  5000   // retry when offline (ms)
```

### 5.5 `service/OneService.{hpp,cpp}` — config + resolver + reactive hook

**Configuration** (optional, stock-compatible):
- Read `_localConfig["zgalaxyDomain"]` (string) inside `readLocalSettings()`
  (`OneService.cpp:1520`); environment variable `ZGALAXY_DOMAIN` overrides.
- Store in a new member `std::string _zgalaxyDomain;`.

**Resolver** (non-blocking for the event loop, purely reactive):
- Members: cached `std::vector<InetAddress> _zgalaxyResolvedIps` (all resolved
  A records — multi-A, mirrors the engine's `buildPlanet`), `int64_t
  _zgalaxyLastDnsCheck`.
- A dedicated `std::thread` (started in `OneService::run()` only when the domain
  is set, joined on shutdown) **blocks on a condition variable** — it makes zero
  DNS queries while the root is reachable. It resolves only when woken: at
  startup and on a detected disconnect. On failure it keeps the last known IPs
  and records the attempt time so retries happen at a sane cadence
  (`ZT_ZGALAXY_DNS_RETRY_INTERVAL`) while the outage lasts.
- Portability guard:
  `#ifdef __WINDOWS__` → `#include <winsock2.h>` + `<ws2tcpip.h>` (ws2_32 already
  linked); else `<netdb.h>` + `<sys/socket.h>`.

**Apply in main loop** (`for(;;)` at `OneService.cpp:1309`, next to the
`processBackgroundTasks` block):
- If `_zgalaxyDomain` empty → skip (stock behaviour).
- **Reactive (auto-retry):** if the root is unreachable
  (`!_node->isPlanetReachable(now)`, path-alive based ~19 s) and
  `now - _zgalaxyLastDnsCheck >= ZT_ZGALAXY_DNS_RETRY_INTERVAL` → wake the
  resolver (it re-resolves immediately), then apply + re-link.
  This reproduces the watchdog's "on disconnect" behaviour **gracefully**
  (peer reset, no restart) and is deliberately **not periodic** — the address is
  never refreshed while the connection is stable.
  (peer reset, no restart).

### 5.6 Docs & packaging

- Update `docs/BUILD.md`, `docs/BUILD-WINDOWS.md`, `README.md`: document
  `zgalaxyDomain` in `local.conf` / `ZGALAXY_DOMAIN`, native behaviour, and mark
  the companion watchdog as optional/legacy.
- Ship a `local.conf` sample via the Windows installer and the Linux install
  script (opt-in; default remains stock-compatible).

---

## 6. Alternatives considered (and why rejected)

| Alternative | Why rejected |
|---|---|
| Keep external watchdog (status quo) | External process; restarts the service; per-OS duplication; not "native" per requirement. |
| Client fetches planet over HTTP from the engine (`/api/v1/planet/download`) | Adds an HTTP client into the daemon; heavier than DNS; more attack surface; DNS is sufficient because only the root IP changes. |
| In-band world updates pushed by the root | Requires the root to sign & push updated worlds; the planet world is already signed by the engine — possible long-term, but DNS covers clients immediately and needs no root changes. |
| Re-sign the planet client-side | Impossible: clients lack the signing key. |

---

## 7. Verification plan

1. **Build** the Linux client; set `zgalaxyDomain` in `local.conf` on a test box;
   confirm `zerotier-cli listpeers` shows the ZGALAXY root DIRECT at the current
   public IP.
2. **Unit (loopback):** call `setPlanetEndpoints` with a different IP; confirm
   `getRootsToContact` / `isProhibitedEndpoint` reflect it immediately and the
   root peer re-establishes to the new endpoint.
3. **Offline test:** firewall-block the root's UDP port on the client; expect
   OFFLINE → auto re-resolve + re-link within `ZT_ZGALAXY_DNS_RETRY_INTERVAL`
   once the path is restored — no service restart, no companion scripts.
4. **Regression:** no `zgalaxyDomain` configured → behaviour identical to stock;
   no-IP binary still embeds zero IPs.
5. **Windows:** repeat 1–4 after building via `windows/build-windows.ps1`.

---

## 8. Rollout order (per project directive)

1. **Linux client first** — implement → build → verify (192.168.1.20 / local box).
2. **Windows client second** — same source, build + installer.
3. Keep companion watchdog files in-tree, marked optional/legacy.

---

## 9. Key file:line index

| File | Line(s) | Content |
|---|---|---|
| `node/Topology.cpp` | 36–37 | no baked default world |
| `node/Topology.cpp` | 45 | load planet from state object |
| `node/Topology.cpp` | 213 | `isProhibitedEndpoint` (root IP whitelist) |
| `node/Topology.cpp` | 252 | `getRootsToContact` |
| `node/Topology.cpp` | 290 | `addWorld` locking pattern |
| `node/Topology.cpp` | 354 | persist planet via `stateObjectPut` |
| `node/Topology.cpp` | 422 | `doPeriodicTasks` |
| `node/Topology.cpp` | 451 | `_memoizeUpstreams` |
| `node/Topology.hpp` | 144,151,189,219 | prohibited / roots / planet / addWorld APIs |
| `node/World.hpp` | 83,162,183,287 | Root struct / shouldBeReplacedBy / serialize / make |
| `node/Node.cpp` | 318,341,353,421 | background tasks, online detection |
| `node/Node.cpp` | 767 | `setPhysicalPathConfiguration` (forwarding pattern) |
| `node/Node.cpp` | 773 | `Node::planet()` |
| `node/Node.hpp` | 180–181 | planet/moons getters |
| `node/InetAddress.hpp` | 123,127,452 | constructors, ipsEqual |
| `node/Constants.hpp` | 310,315,364,384,510 | timers |
| `service/OneService.cpp` | 1299–1441 | main loop |
| `service/OneService.cpp` | 1332 | local.conf reload tick |
| `service/OneService.cpp` | 1350 | `_node->online()` |
| `service/OneService.cpp` | 1402 | `processBackgroundTasks` |
| `service/OneService.cpp` | 1520–1567 | `readLocalSettings` / `_localConfig` |
| `service/OneService.cpp` | 3791,3944 | planet file mapping |
| `one.cpp` | 1620 | `setworld`/genmoon (offline tool) |
