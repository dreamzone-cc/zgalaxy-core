# Architecture

This document explains how the ZGALAXY ecosystem is structured and where
`zgalaxy-core` fits in.

## 1. Responsibilities split

The ZGALAXY ecosystem is composed of **two independent services** that never
overlap:

| Layer | Service | Host | Role |
|-------|---------|------|------|
| **Control plane** | [ztnet](https://github.com/sinamics/ztnet) | `192.168.1.161` | Network **controller** (membership, rules, network config). Manages the embedded controller. **Kept unmodified.** |
| **Infrastructure plane** | [ZGALAXY](https://github.com/dreamzone-cc/ZGALAXY) | `192.168.1.171` | **Planet / bootstrap / root topology** that clients connect to. |
| **Core** | **zgalaxy-core** (this repo) | — | The patched ZeroTier **engine** binary that both planes run. |

Key point: **ztnet is not modified at all.** It consumes the ZeroTier engine
and its embedded controller through the standard ZeroTier API. The only change
the whole project introduces is *where the engine connects* — which is the
ZGALAXY planet instead of the official ZeroTier infrastructure.

## 2. Current infrastructure layout (as inspected)

```
┌─────────────────────────────── 192.168.1.171 (ZGALAXY) ─────────────────────────────┐
│  zgalaxy/zerotier-one v1.14.2  →  Planet root                                       │
│  identity: 069ae38092          →  listens on UDP 9994                               │
│  planet: root 069ae38092 @ 192.168.1.171/9994 (world id 149604618)                  │
│  moon broadcast: dz.dreamzone.cc/9994, 154.253.231.164/9994                     │
└──────────────────────────────────────────────────────────────────────────────────────┘
        ▲ PLANET peer (069ae38092 @ 192.168.1.171/9994)
┌─────────────────────────────── 192.168.1.161 (ztnet) ───────────────────────────────┐
│  docker compose:                                                                     │
│    sinamics/ztnet:latest     (UI/API on :3000)                                       │
│    postgres:15.2-alpine      (ztnet DB)                                              │
│    zyclonite/zerotier:1.16.2 (zerotier-one -U = embedded controller)                │
│  planet file in volume ztnet_zerotier = copy of the ZGALAXY planet                  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Notes from the live inspection:

* The `zerotier` container inside ztnet was already showing the ZGALAXY planet
  as its PLANET peer: `069ae38092 ... PLANET ... 192.168.1.171/9994`.
* The `planet` file used on both servers is 271 bytes and reuses world id
  `149604618` (the numeric identifier also used by the official Earth world —
  see [PATCHES.md](PATCHES.md) for why that is acceptable).
* The ztnet container runs the embedded controller (`-U`), so the
  `nonfree/controller` sources **must remain in the build**. This is what
  provides the network controller functionality that ztnet drives.

## 3. What the fork changes vs. what it does not change

### Changed (infrastructure plane only)

1. The **default world** baked into the binary (`ZT_DEFAULT_WORLD`) is the
   ZGALAXY planet, not the official Earth planet.
2. The official **TCP fallback relay** (`204.80.128.1/443`) is removed.
3. World identifier constants and program branding now carry the ZGALAXY
   identity.

### Unchanged (engine plane)

* VL1 peer-to-peer networking engine (`node/`)
* Protocol and packet formats
* End-to-end encryption / cryptography
* NAT traversal (`osdep/`, miniupnpc/libnatpmp)
* Planet/Moon architecture (roots, worlds, moons)
* Embedded network controller (`nonfree/controller/` — FileDB)

## 4. Dependency analysis summary

From [ANALYSIS.md](ANALYSIS.md), the modern ZeroTier codebase (1.16.2) already
removed most official cloud references from the core code:

* No `my.zerotier.com`, `central.zerotier.com`, or `updates.zerotier.com` in
  the core.
* Software update mechanism defaults to `"disable"` and updates are instead
  signed by the planet's `updatesMustBeSignedBy` key.
* The full "Central" controller (BigTable/PubSub/Redis/PostgreSQL) is isolated
  behind the `ZT1_CENTRAL_CONTROLLER` build flag and is not built.

The remaining hard dependencies on the official service were:

| # | Dependency | Where | Impact |
|---|------------|-------|--------|
| 1 | Default Earth planet (root servers) | `node/Topology.cpp` | **Critical** — silent fallback to official roots if no `planet` file exists |
| 2 | TCP fallback relay | `service/OneService.cpp` | Connects to `204.80.128.1/443` run by ZeroTier, Inc. |
| 3 | World id constants | `node/World.hpp` | Identity of the "Earth" world |
| 4 | Branding | `one.cpp`, `version.h` | Product name / notices |
