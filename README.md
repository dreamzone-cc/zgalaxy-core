<p align="center">
  <img src="assets/zgalaxy-logo.svg" alt="ZGALAXY Logo" width="220" />
</p>

# ZGALAXY One — zgalaxy-core

**ZGALAXY Core** is a fork of [ZeroTierOne](https://github.com/zerotier/ZeroTierOne) (v1.16.2) that removes every dependency on the official ZeroTier cloud infrastructure and hard-codes the **ZGALAXY** private planet instead.

The ZeroTier networking **engine, protocol, cryptography, NAT traversal, and Planet/Moon architecture are unchanged**. Only the *infrastructure the binary connects to* was replaced.

```
┌─────────────────────────────────────────────────────────────────────┐
│                      ZGALAXY CORE (this fork)                       │
│                                                                     │
│   ZeroTier engine (node/, osdep/, service/)   ── untouched engine   │
│                                                                     │
│   ZT_DEFAULT_WORLD (node/Topology.cpp)        ── ZGALAXY planet     │
│   TCP fallback relay (service/OneService.cpp) ── removed            │
│   World IDs (node/World.hpp)                  ── ZGALAXY identity   │
│   Branding (one.cpp, version.h)               ── ZGALAXY            │
│   Embedded controller (nonfree/controller/)   ── kept (used by ztnet)│
└─────────────────────────────────────────────────────────────────────┘
```

## Documentation

| Document | Purpose |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Full architecture: ZGALAXY + ztnet split of responsibilities |
| [docs/ANALYSIS.md](docs/ANALYSIS.md) | What depends on the official service and how it was found |
| [docs/PATCHES.md](docs/PATCHES.md) | Every source change applied, file by file |
| [docs/BUILD.md](docs/BUILD.md) | How to build from source |
| [docs/VERIFICATION.md](docs/VERIFICATION.md) | How independence from the official service is verified |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Deploying onto the ZGALAXY and ztnet servers |
| [docs/LEGAL.md](docs/LEGAL.md) | Licensing notes (MPL-2.0 vs ZeroTier Source-Available) |
| [docs/SECURITY.md](docs/SECURITY.md) | Secret-handling policy and pre-push verification |

## Quick summary of changes

| File | Change |
|------|--------|
| `node/Topology.cpp` | Replaced the baked-in official Earth planet (570 bytes) with the ZGALAXY planet (271 bytes, root `069ae38092` @ `192.168.1.171/9994`, `dz.dreamzone.cc/9994`) |
| `service/OneService.cpp` | Removed the official `ZT_TCP_FALLBACK_RELAY "204.80.128.1/443"` define — the entire TCP fallback feature is compiled out |
| `node/World.hpp` | `ZT_WORLD_ID_EARTH` → `ZT_WORLD_ID_ZGALAXY` |
| `one.cpp` | `PROGRAM_NAME "ZGALAXY One"`, updated license grant text |
| `version.h` | `ZEROTIER_ONE_NAME "zgalaxy-one"` |

## License

This fork retains the upstream licenses:

* **Engine code** (`node/`, `osdep/`, `service/`): [MPL-2.0](LICENSE-MPL.txt)
* **Controller code** (`nonfree/`): [ZeroTier Source-Available License (Non-Commercial)](nonfree/LICENSE.md) — see [docs/LEGAL.md](docs/LEGAL.md)

## Trademark

The ZGALAXY logo (`assets/zgalaxy-logo.svg`) is the property of the
[ZGALAXY](https://github.com/dreamzone-cc/ZGALAXY) project
([source](https://github.com/dreamzone-cc/ZGALAXY/blob/main/assets/logo.svg)),
used here to identify this ZGALAXY-core build.
