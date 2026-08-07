# Patches

Every source change applied to upstream ZeroTierOne v1.16.2, file by file, on
branch `zgalaxy-core`.

## Summary

```
node/Topology.cpp      | P1 — default world replaced (official → ZGALAXY planet)
service/OneService.cpp | P2 — official TCP fallback relay removed
node/World.hpp         | P3 — world identity constants
one.cpp                | P4 — program name / copyright / license grant
version.h              | P4 — binary name
zgalaxy/planet.bin     | binary asset — the ZGALAXY planet used by P1
```

## P1 — Default world (`node/Topology.cpp`)

**File:** `node/Topology.cpp` (lines 20-37)

**Before:** `ZT_DEFAULT_WORLD_LENGTH 570` with 570 bytes of the official
ZeroTier Earth planet (world id `149604618`).

**After:** `ZT_DEFAULT_WORLD_LENGTH 271` with the ZGALAXY planet:

* **World id:** `149604618` (kept for compatibility with the existing
  deployment — see note below)
* **Root identity:** `069ae38092`
* **Stable endpoints:** `192.168.1.171/9994` (LAN), `dz.dreamzone.cc/9994`, `154.253.231.164/9994` (WAN)
* **Size:** 271 bytes

The raw bytes live in `zgalaxy/planet.bin` (regenerated via `mkmoonworld` on
the ZGALAXY server). Regenerate the C array from any new planet file with:

```bash
xxd -i zgalaxy/planet.bin
```

**Why the world id is kept at `149604618`:**

The world id is a numeric identifier, not a connection endpoint. Nodes accept
whatever world is presented in the (signed) planet file they load. Keeping the
existing id means:

* The current ZGALAXY deployment (both servers) keeps working unchanged.
* No client needs a new planet pushed.

The roots — the actual endpoints the nodes connect to — point at the ZGALAXY
server, which is what removes the dependency on the official service.

If a fully unique world id is ever desired, a new planet must be generated via
ZGALAXY's planet builder (`mkmoonworld`) and pushed to all nodes, and this
array regenerated.

## P2 — TCP fallback relay removed (`service/OneService.cpp`)

**File:** `service/OneService.cpp` (line 149-152)

**Before:**

```cpp
// TCP fallback relay (run by ZeroTier, Inc. -- this will eventually go away)
#ifndef ZT_SDK
#define ZT_TCP_FALLBACK_RELAY "204.80.128.1/443"
#endif
```

**After:**

```cpp
// TCP fallback relay (official ZeroTier relay removed for ZGALAXY).
// The fallback TCP relay feature is disabled entirely; ZGALAXY nodes
// rely on the ZGALAXY planet roots for connectivity.
```

**Effect:** every use of `ZT_TCP_FALLBACK_RELAY` in the file is wrapped in
`#ifdef ZT_TCP_FALLBACK_RELAY` blocks (lines 896, 969, 2889, 3982). With the
define gone, none of that code compiles — the relay field, its address, and
the connection handling are all removed from the binary.

## P3 — World identity (`node/World.hpp`)

**File:** `node/World.hpp` (lines 41-53)

**Before:** `ZT_WORLD_ID_EARTH 149604618` and `ZT_WORLD_ID_MARS 227883110`.

**After:** `ZT_WORLD_ID_ZGALAXY 149604618` (the MARS constant removed).

These constants are documentation-only (not used in any control flow), but
carried the official "Earth world" naming.

## P4 — Branding (`one.cpp`, `version.h`)

**File:** `one.cpp`

```diff
-#define PROGRAM_NAME	 "ZeroTier One"
-#define COPYRIGHT_NOTICE "Copyright (c) ZeroTier, Inc."
+#define PROGRAM_NAME	 "ZGALAXY One"
+#define COPYRIGHT_NOTICE "Copyright (c) ZeroTier, Inc. / ZGALAXY (dreamzone-cc)"
```

License grant text rewritten to describe the ZGALAXY build:

```
ZGALAXY build. Controller component licensed under the ZeroTier
Source-Available License for Non-Commercial Use (nonfree/LICENSE.md).
Node/agent components licensed under Mozilla Public License v2.0.
This build connects exclusively to the ZGALAXY planet infrastructure.
```

**File:** `version.h`

```diff
-#define ZEROTIER_ONE_NAME		 "zerotier-one"
+#define ZEROTIER_ONE_NAME		 "zgalaxy-one"
```

## What was deliberately NOT changed

* `nonfree/controller/` — the embedded network controller (FileDB-based).
  **Required** by ztnet, which drives it with `zerotier-one -U`.
* The engine, protocol, cryptography, and NAT traversal code.
* Upstream copyright/license headers (required for legal compliance when
  redistributing).

## Generating the diff

```bash
git diff origin/1.16.2 > zgalaxy-core.patch
```
