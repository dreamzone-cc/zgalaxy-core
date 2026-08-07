# Dependency Analysis

This document records how the official ZeroTier service dependencies were
located and classified. It is the reference for *why* each patch exists.

## 1. Methodology

1. Clone `https://github.com/zerotier/ZeroTierOne`.
2. Grep the whole tree for official domains and endpoints
   (`my.zerotier.com`, `central.zerotier.com`, `updates.zerotier.com`,
   `*.zerotier.com`, `204.80.128.1`, ...) excluding `attic/`, `ext/`,
   `windows/`, `osdep/`.
3. Inspect the planet loading path (`node/Topology.cpp`) and the world
   update logic (`node/World.hpp`) to understand **runtime** behavior.
4. Classify every finding as **external** (replaceable by files) or
   **compiled-in** (requires a source patch + rebuild).

## 2. Findings

### 2.1 Official cloud URLs — already gone upstream

The modern codebase no longer contains these in the core:

| Reference | Result |
|-----------|--------|
| `my.zerotier.com` | not present |
| `central.zerotier.com` | not present |
| `updates.zerotier.com` | not present |
| `ZT_SOFTWARE_UPDATE_DEFAULT` | `"disable"` (`service/OneService.cpp:134`) |

Software updates are driven by the planet itself via
`updatesMustBeSignedBy` (`node/World.hpp`) — a world signed by the same key
that signed the planet, **not** by a ZeroTier cloud endpoint.

The full "Central" controller (BigTable/PubSub/Redis/PostgreSQL status
writers, `CentralDB.cpp`, etc.) only compiles when
`ZT1_CENTRAL_CONTROLLER=ON`. It is off by default and requires Google Cloud /
Redis / Postgres dependencies, so a stock build never includes it.

### 2.2 Compiled-in dependencies that required patches

| # | Location | What | Classification |
|---|----------|------|----------------|
| 1 | `node/Topology.cpp:20-37` | `ZT_DEFAULT_WORLD` — the official Earth planet baked into the binary | **Compiled-in (critical)** |
| 2 | `service/OneService.cpp:151` | `ZT_TCP_FALLBACK_RELAY "204.80.128.1/443"` | **Compiled-in** |
| 3 | `node/World.hpp:48-53` | `ZT_WORLD_ID_EARTH`, `ZT_WORLD_ID_MARS` | Compiled-in (constants) |
| 4 | `one.cpp:102-108` | `PROGRAM_NAME`, `COPYRIGHT_NOTICE`, `LICENSE_GRANT` | Compiled-in (branding) |
| 5 | `version.h:34` | `ZEROTIER_ONE_NAME` | Compiled-in (branding) |

### 2.3 External (replaceable at runtime, no rebuild needed)

| Element | File path | Behavior |
|---------|-----------|----------|
| Planet | `planet` in the ZeroTier home dir | Loaded first via `stateObjectGet(ZT_STATE_OBJECT_PLANET)` in `Topology`'s constructor, *before* the compiled default is considered |
| Moons | `moons.d/*.moon` | Loaded from disk |
| Network configs | `controller.d/network/` | Managed by the embedded controller (FileDB) |
| TCP fallback toggle | `local.conf` → `"allowTcpFallbackRelay"` | Runtime switch (`service/OneService.cpp:2750`) |
| Identity | `identity.public` / `identity.secret` | Generated locally per node |

## 3. Why the runtime setup worked (the subtle part)

In `Topology::addWorld` (`node/Topology.cpp`) and `World::shouldBeReplacedBy`
(`node/World.hpp:167`), a planet read from disk replaces the compiled-in
default only when it has **the same world id, a newer timestamp, and a valid
signature**.

The ZGALAXY planet on the servers reuses world id `149604618` with a newer
timestamp, so it "wins" over the compiled-in official planet at runtime. That
is why the existing deployment worked — but it was **fragile**:

* If the `planet` file were deleted, the binary would fall back to the
  **official** planet and connect to official ZeroTier roots.
* Any deeper change to the world id would break the substitution logic.

`zgalaxy-core` eliminates the fragility by baking the ZGALAXY planet into the
binary itself, so there is **no official fallback at all**.

## 4. Classifications → patch mapping

| Classification | Patch |
|----------------|-------|
| Compiled-in critical | [PATCHES.md](PATCHES.md#p1-default-world) (P1) |
| Compiled-in | PATCHES.md#p2-tcp-fallback-relay (P2) |
| Constants | PATCHES.md#p3-world-identity (P3) |
| Branding | PATCHES.md#p4-branding (P4) |

## 5. Remaining non-code references (left intentionally)

These appear only in packaging/documentation, never in the built binary:

* `Dockerfile.release` — pulls upstream packages during image build
* `zerotier-one.spec` — RPM packaging metadata
* `one.cpp:6`, headers — upstream copyright/license URLs (kept for legal
  compliance)

Verification that none of these leak into the runtime binary is documented in
[VERIFICATION.md](VERIFICATION.md).
