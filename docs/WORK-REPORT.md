# ZGALAXY — Comprehensive Work Report

Scope: full body of work performed across the ZGALAXY project — the engine
(`dreamzone-cc/ZGALAXY`), the client fork (`dreamzone-cc/zgalaxy-core`), the
private mesh, and the dynamic-IP solution.
Date of report: 2026-08-08.

---

## 1. Executive summary

- **Engine (ZGALAXY v1.3.0)**: completed a security audit and remediation plan
  (P0–P4), hardening all 59 API routes, authentication, secrets, storage and
  the control plane; added performance and observability work; runs on Bun.
- **Client (zgalaxy-core, ZeroTier 1.16.2 fork)**: rewired exclusively to the
  ZGALAXY private planet, removed the official Earth world and the official TCP
  fallback relay, and produced **IP-agnostic** binaries (zero embedded IPs).
- **Dynamic-IP problem**: root cause identified in the fork source, and a
  **native, in-binary, reactive dynamic-DNS layer** was designed, implemented,
  built and **live-verified** — including surviving three real IP changes
  during testing — without external scripts or service restarts.
- **Architecture unification**: a deep examination of the engine's unified
  planet/moon pipeline confirmed the client layer shares the same
  "domain is the reference, IPs are dynamic data" model; the client now mirrors
  the engine's multi-A endpoint handling.
- **Git state**: all work committed and pushed to both repositories
  (GitHub reachability restored).

---

## 2. Phase 1 — Engine security audit & hardening (P0–P4)

All of the following is in the ZGALAXY engine (repo `dreamzone-cc/ZGALAXY`,
branch `main`, v1.3.0, Bun runtime):

- **RBAC** across all 59 route handlers (roles, ownership checks).
- **Authentication & secrets**: PBKDF2 (210k iterations), 24 h session TTL +
  logout + session GC, secret-key generation, `timingSafeEqual` comparisons.
- **Transport & abuse controls**: rate limits, CORS allowlist, trust-proxy
  handling, central error handler, path-traversal and SSRF protections.
- **Storage**: SQLite default store with auto-migration and legacy JSON
  fallback; in-memory session cache; encrypted AES-256-GCM backups;
  streaming backups.
- **Operations**: `/ready` and `/metrics` (Prometheus), graceful SIGTERM
  shutdown, cluster health, planet validate/delete/import, file locks.
- **Performance**: IPv4-first endpoint ordering, parallel federation, external
  IP cache (see `docs/PERFORMANCE-REVIEW.md`).
- **Testing/CI**: 15 security tests + regression suite; CI on Node and Bun.
- **Known items to rotate**: a Cloudflare token (`cfat_…`) referenced in
  `config/cloudflare_config.json`.

## 3. Phase 2 — zgalaxy-core client fork (ZeroTier → ZGALAXY)

Repo `dreamzone-cc/zgalaxy-core`, branch `zgalaxy-core` (ZeroTier 1.16.2):

- **Planet wiring**: the client connects only to the ZGALAXY planet
  (root `069ae38092`, world `149604618`); official Earth world removed.
- **No official relay**: the ZeroTier TCP fallback relay was removed.
- **IP-agnostic builds**: no default world baked into the binary
  (`ZT_DEFAULT_WORLD_LENGTH 0`); the planet is an **external, importable file**
  loaded at runtime — swappable after compilation. Verified the binaries embed
  zero IPs.
- **Prebuilt binaries** shipped for Linux (`-arch`, `-glibc2.39`, `-ubuntu26`)
  and the Release `v1.16.2-zgalaxy`; Windows assets present.
- **Companion module (now legacy)**: `client/zgalaxy-planet-sync.sh` +
  `zgalaxy-watch.{sh,service}` and `windows/watchdog/*.ps1` — a reactive
  watchdog that resolved the domain and re-supplied the planet on disconnect.
  Superseded by the native layer (Phase 4) and marked optional/legacy.
- **Integration**: embedded in `ztnet` (192.168.1.161, controller working,
  network `shared-whale`), deployed to the Ubuntu client (192.168.1.20) and the
  local CachyOS box; the mesh is fully self-hosted.

## 4. Phase 3 — The dynamic-IP problem

### 4.1 Problem & root cause (source analysis)

- The ZGALAXY root's public IP is dynamic. ZeroTier is **IP-only**: the
  planet's root `stableEndpoints` are literal IPs, and `genmoon`/`mkmoonworld`
  silently drop hostname endpoints.
- The engine resolved this at build time (`dns.resolve4`) — but existing
  clients keep the old IP and break when the public IP changes.
- Source-level cause found in the fork:
  - `Topology::isProhibitedEndpoint` (`node/Topology.cpp:213`) drops packets
    from a root whose source IP is not in the planet's `stableEndpoints`;
  - `getRootsToContact` / `_memoizeUpstreams` only know the stale endpoints;
  - `World::shouldBeReplacedBy` requires a newer timestamp + valid signature,
    so a client (without the signing key) cannot push a re-signed world;
  - there was no DNS use anywhere in the client.

### 4.2 Solution — native reactive dynamic-DNS layer

A thin, **in-binary** layer (no redesign, no external scripts):

- **Config**: `"zgalaxyDomain"` in `local.conf` (or env `ZGALAXY_DOMAIN`);
  empty = stock behaviour.
- **Reactive only**: the resolver thread blocks on a condition variable — zero
  DNS queries while the root is reachable. It resolves at startup and again on
  disconnect (detected via `Peer::hasAlivePath`, ~19 s).
- **Apply**: `setPlanetEndpoints` merges the resolved A records (multi-A,
  mirroring the engine) with the primary root's existing private/LAN endpoints,
  updates the planet **in place** (no re-signing), persists it, and re-links
  gracefully (peer reset, no restart).

### 4.3 Files changed (zgalaxy-core)

| File | Change |
|---|---|
| `node/World.hpp` | `setRootStableEndpoints` (in-place endpoint swap) |
| `node/Topology.{hpp,cpp}` | `setPlanetEndpoints` (merge+persist+re-link), `isPlanetReachable`, `_zgIsPrivateIPv4` |
| `node/Node.{hpp,cpp}` | public `setPlanetEndpoints` / `isPlanetReachable` |
| `node/Peer.hpp` | `hasAlivePath` (disconnect signal) |
| `node/Constants.hpp` | `ZT_ZGALAXY_DNS_RETRY_INTERVAL` (5 s) |
| `service/OneService.cpp` | config, resolver thread, reactive loop, lifecycle, logging |

### 4.4 Live verification (all passed)

- ONLINE, root DIRECT, network `shared-whale` OK, IP assigned.
- **Three real IP changes** during testing (`105.97.148.187 →
  41.200.151.128 → 105.105.114.137`) — each auto-recovered.
- Stability: zero DNS queries during stable connection.
- Disconnect/recovery without restart; legacy watchdog disabled and proven
  redundant; CPU 0.2% (no busy loop); stock behaviour when disabled.

### 4.5 Deep review fixes applied before finalizing

Four integration issues found during the deep examination and fixed:
1. data race on `_zgalaxyDomain` between the resolver thread and the
   `local.conf` reload (now mutex-guarded);
2. resolver thread only started when a domain existed at boot (now started
   unconditionally, enabling runtime local.conf changes);
3. a `continue` that could skip `_phy.poll` (busy loop) — replaced with an
   `if` guard;
4. `setPlanetEndpoints` applied one endpoint set to every root (wrong for
   multi-root planets) — now applies to the primary root only.

## 5. Architecture unification with the engine

Deep examination produced `docs/PLANET-MOON-ARCHITECTURE.md` (engine repo):

- The engine builds **both** planets and moons through one unified pipeline:
  `identity.public → initmoon → moon.json → genmoon/mkmoonworld` (World model,
  same signing semantics).
- The client layer uses the **same model**: domain = reference, IPs = dynamic
  data injected into a signed World; the client now also mirrors the engine's
  multi-A endpoint injection.
- Server-side DDNS (periodic 5 min, engine) and client-side reactive layer are
  complementary by design.
- Remaining future items: moons on the client, no-planet bootstrap identity,
  optional planet-download fallback.

## 6. Documentation deliverables

- Client (`zgalaxy-core/docs/`): `DYNAMIC-IP-IMPLEMENTATION.md` (authoritative),
  `ZGALAXY-DYNAMIC-IP-ANALYSIS.md`, `PLAN-NATIVE-DYNAMIC-IP.md`,
  `USING-DOMAIN-NAMES-INSTEAD-OF-IPS.md`.
- Engine (`ZGALAXY/docs/`): `PLANET-MOON-ARCHITECTURE.md`.
- Existing engine docs: `AUDIT-REPORT.md`, `REMEDIATION-PLAN.md`,
  `PERFORMANCE-REVIEW.md`, `openapi.yaml`.

## 7. Releases & git state (final, pushed)

| Repo | Branch | Head | Contents |
|---|---|---|---|
| `dreamzone-cc/ZGALAXY` | `main` | `09e9fb0` | +architecture doc, +gitignore fix, +domain→IP resolver, v1.3.0 |
| `dreamzone-cc/zgalaxy-core` | `zgalaxy-core` | `b32c1ba` | +native dynamic-DNS layer, +watchdog docs, +Windows build scripts |

Release `v1.16.2-zgalaxy` hosts the prebuilt binaries.

## 8. Current state & next steps

- **Done**: engine hardened (v1.3.0); client IP-agnostic; native reactive
  dynamic-DNS layer implemented, built, verified and pushed; architecture
  unified with the engine; documentation complete.
- **Next**: deploy the new client binary + `local.conf` (`zgalaxyDomain`) to the
  servers (192.168.1.20, 171, 161) and disable their legacy watchdogs; then the
  **Windows** client (deferred by decision).
- **Security reminders**: rotate the GitHub tokens shown in the chat, the
  Cloudflare token, and treat the API token as ephemeral.

## 9. Latest additions — planet/moon independence (v2) & deep checks

### 9.1 Client v2 — full independence & domain-based connectivity for moons
- **Auto-import from ZGALAXY** at startup (`zgalaxyEngineUrl`): the client
  downloads the current `planet` and configured moons from the engine's public
  endpoints before the node starts — no manual file handling, no recompilation.
- **Reactive domain resolution covers moons** (`zgalaxyMoons` config): the
  resolver resolves the planet domain AND every moon domain; `setMoonEndpoints`
  merges LAN + resolved endpoints and re-links the moon's root peer.
- **Bounded validation** (`zgalaxyValidateIntervalMinutes`, default 10):
  gentle periodic address verification; 0 = pure reactive.
- **Runtime `moons.d` watcher**: new `.moon` files are orbited and removed ones
  deorbited every 10 s without a restart.
- **Per-world disconnect fallback** (`isWorldReachable`) re-resolves the domain
  of the affected world only.

### 9.2 Engine
- Moon create accepts ZeroTier `host/port` endpoints (and `host:port`).

### 9.3 Deployment & integration (no ztnet changes)
- dz20, local, and the ztnet controller all run the latest v2 client (the
  ztnet image was rebuilt to `6557361cd0f`, identity `ef313fb5c9` preserved).
- `tests/integration-test.sh` — 22/22 deep connectivity & integration tests
  (domain mechanism, engine, client layer, reactive fallback, mesh ping,
  client independence) all pass.
- Deep protocol investigation: `docs/CONNECTION-PROTOCOLS-REPORT.md` — relay
  via the root (~5 ms) vs direct P2P formed via path introduction (0.86 ms);
  zero errors across the fleet.

### 9.4 Windows client — built, fixed & released (2026-08-11)

- **Windows x64 build** produced locally (VS2022 + MSVC, Release/x64) from the
  latest `zgalaxy-core` HEAD (`1aa333dd`): `rustybits/zeroidc` (Rust lib) then
  `ZeroTierOne.vcxproj`, outputs collected into `windows\dist\`.
- **Compile fix required**: `service/OneService.cpp` failed with
  `error C1083: cannot open include file: 'netdb.h'` because the dynamic-DNS
  layer used `#ifdef __WINDOWS__` before `node/Constants.hpp` (which defines the
  macro) is included. Changed to `#if defined(_WIN32) || defined(_WIN64)`.
  Documented in `docs/FIX-ONESERVICE-WINDOWS-INCLUDE.md`.
- **Artifacts shipped** in `dist/windows/`:
  - `zgalaxy-one-windows-x86_64.exe` (also usable as `zerotier-cli`/`zerotier-idtool`)
  - `ZGALAXY-One-Setup.exe` (NSIS installer: service + firewall + bundled NDIS6 driver)
  - `driver/` — `zttap300.{cat,inf,sys}` NDIS6 tap driver
- **Verified**: `-v` → `1.16.2`; no official ZeroTier references
  (`my.zerotier.com`, `central.zerotier.com`, `204.80.128`) in the binary;
  planet world `149604618` from `zgalaxy/planet.bin`.
- **Release `v1.16.2-zgalaxy`** updated with the Windows assets alongside the
  Linux binaries.
- Docs updated: `dist/README.md` (Windows install section), `docs/BUILD-WINDOWS.md`
  (compile-fix note), this report.
