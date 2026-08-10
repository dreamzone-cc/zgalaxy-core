# ZGALAXY Client — Deep Examination Report (Core Files)

Date: 2026-08-10
Scope: in-depth review of every ZGALAXY addition across the core files of the
`zgalaxy-core` client fork, verifying correctness, thread safety, lock ordering,
and integration. Live-verified with the integration test suite.

---

## 1. Files examined

| File | Additions | Verdict |
|---|---|---|
| `service/OneService.cpp` | config, resolver thread, reactive loop, moons.d watcher, auto-import | ✅ +3 improvements applied |
| `node/Topology.cpp` | `setPlanetEndpoints`, `setMoonEndpoints`, `isPlanetReachable`, `isWorldReachable`, merge helpers | ✅ correct |
| `node/Topology.hpp` | declarations | ✅ correct |
| `node/Peer.hpp` | `hasAlivePath` | ✅ correct |
| `node/World.hpp` | `setRootStableEndpoints` | ✅ correct |
| `node/Node.cpp` | forwarders | ✅ correct |
| `node/Node.hpp` | declarations | ✅ correct |
| `node/Constants.hpp` | timing constants | ✅ + comment fix |

## 2. Per-file findings

### 2.1 `service/OneService.cpp`
Reviewed: members, constructor init, `readLocalSettings` parsing, the resolver
thread (`_zgalaxyDnsLoop`), the main-loop apply block, the moons.d watcher
(`_zgalaxyScanMoonsD`), the auto-import (`_zgalaxyImportFromEngine`), and thread
lifecycle.

- Thread safety: all ZGALAXY state guarded by `_zgalaxyDns_m`; the resolver
  thread copies config under the lock and publishes results under the lock.
- Lock order: `_zgalaxyDns_m` → topology locks only (never inverted).
- Lifecycle: resolver thread started unconditionally; joined in `run()` cleanup
  and the destructor.
- **Improvements applied (F1–F3):**
  - **F1** — the cheap retry-gate timestamp check now runs BEFORE the
    lock-heavy `isWorldReachable` probe (planet and per-moon), removing
    per-iteration node-lock churn.
  - **F2** — removed the periodic `moons.d scan (N files)` log spam; logs only
    on actual change (detected / removed).
  - **F3** — wrapped the apply block in `try/catch` so an unexpected error in
    the dynamic-DNS layer is non-fatal (previously it could terminate the
    service via the main-loop catch).

### 2.2 `node/Topology.cpp`
- Helpers `_zgIsPrivateIPv4` (RFC1918 / link-local / CGNAT), `zgMergeRootEndpoints`
  (preserve private + merge resolved, dedup by IP+port), `zgSameEndpoints`.
- `setPlanetEndpoints` / `setMoonEndpoints`: in-place root[0] endpoint swap,
  no-op when unchanged, persist via state object, drop root peer + memoize for a
  graceful re-link.
- `isWorldReachable` / `isPlanetReachable`: path-liveness based (via
  `Peer::hasAlivePath`).
- Lock order `_peers_m` → `_upstreams_m` is consistent with `addWorld`,
  `doPeriodicTasks` — no inversion. `_memoizeUpstreams` recreates the dropped
  root peer. Pointer into `_moons` is safe under the lock (no reallocation).

### 2.3 `node/Peer.hpp` — `hasAlivePath`
- Iterates `_paths` up to `ZT_MAX_PEER_NETWORK_PATHS`, breaking at the first
  null. **Verified**: no code nulls a middle entry (paths are replaced or
  appended), so the array stays compact and the `break` is correct.
- Uses `Path::alive(now)` (~19 s heartbeat window) — appropriate for
  disconnect detection.
- Lock order: `_paths_m` inner — no inversion with topology locks.

### 2.4 `node/World.hpp` — `setRootStableEndpoints`
- Bounds-checked assignment; identity (id/timestamp/signature) untouched.
- Stale local signature after mutation is fine — signatures are only verified
  on in-band world updates, not on local load.

### 2.5 `node/Node.cpp` / `Node.hpp` — forwarders
- Four thin forwarders to `Topology`, correct signatures, no logic/locking in
  Node. Declarations match implementations; includes satisfy all types.

### 2.6 `node/Constants.hpp` — timing
- `ZT_ZGALAXY_DNS_RETRY_INTERVAL` (5000 ms) and
  `ZT_ZGALAXY_VALIDATE_INTERVAL` (600000 ms default). No conflicts.
- **Comment fix**: the retry-interval doc still described the old
  "no periodic polling" design after the bounded validation was added —
  corrected to reflect the reactive + bounded-validation model.

## 3. Verification

- Clean build (`make`, no errors/warnings beyond a pre-existing one).
- Integration test suite: **22/22 PASS** (`tests/integration-test.sh`), covering
  domain mechanism, engine integration, client layer, reactive fallback
  (iptables block → re-resolve → recover without restart), mesh ping, and client
  independence.
- Live behaviour: relay via the root (~5 ms) → direct P2P after path
  introduction (0.86 ms); zero connection errors across the fleet.

## 4. Conclusion

All ZGALAXY additions across the core files are correct, thread-safe, and
consistent. Three concrete improvements (F1–F3) and one documentation fix were
applied during this examination. No functional bugs remain in the examined
surface.

## 5. Windows-only compile fix (C1083: netdb.h)

**Finding**: on Windows the build failed with `C1083: cannot open netdb.h`,
while Linux built fine.

**Root cause**: the `__WINDOWS__` macro is **not** a compiler macro — it is
defined manually in `node/Constants.hpp:93` when `_WIN32/_WIN64` is detected.
The dynamic-DNS layer added an `#ifdef __WINDOWS__` block near the top of
`service/OneService.cpp` (line 26) — **before** `Constants.hpp` (and
`ZeroTierOne.h`) are included. When the preprocessor evaluated that block the
macro was still undefined, so it took the `#else` branch and tried to include
`netdb.h` (POSIX, absent on Windows). On Linux the macro is never defined, so the
`#else` branch was always correct — which is why the bug only appeared on
Windows.

**Fix** (applied): `#ifdef __WINDOWS__` → `#if defined(_WIN32) || defined(_WIN64)`
at `service/OneService.cpp:26` — the same convention as `include/ZeroTierOne.h:20`
and `node/Constants.hpp:89`. All other conditional blocks in `OneService.cpp`
(lines 97+, 1057, 3556, …) sit **after** `Constants.hpp` is included, so their
`__WINDOWS__` checks remain correct and were left untouched.

**Verification**: Linux build unaffected; Windows build succeeds (zerotier-one
1.16.2, no official ZeroTier references, NSIS installer built).
