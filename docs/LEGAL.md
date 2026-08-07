# Licensing

This fork (zgalaxy-core) redistributes upstream ZeroTierOne code and must
respect its licensing. This document summarizes the obligations and the
specific situation of this project.

## 1. Two licenses in the upstream tree

| Component | Directory | License |
|-----------|-----------|---------|
| Engine / agent | `node/`, `osdep/`, `service/`, `one.cpp`, `version.h` | **MPL-2.0** (`LICENSE-MPL.txt`) |
| Controller | `nonfree/controller/` | **ZeroTier Source-Available License, Non-Commercial Use** (`nonfree/LICENSE.md`) |
| Third-party deps | `ext/` | Various (retained) |

## 2. What this means for zgalaxy-core

* **MPL-2.0 code** (`node/`, `osdep/`, `service/`, `one.cpp`, `version.h`):
  we modified these files and must keep them under MPL-2.0. The license and
  copyright notices are retained. Redistribution is allowed; the modified
  source must be available under MPL-2.0 (which a public fork satisfies).
* **Source-Available controller** (`nonfree/controller/`): this code is kept
  **only** because the embedded controller is required by ztnet (`zerotier-one
  -U`). It is **not** free to use for commercial purposes. Anyone running this
  build for commercial use needs a commercial license from ZeroTier, Inc.

### Practical consequence

The ZGALAXY One build ships both engines: the MPL-2.0 agent and the
source-available controller. The build's help text and license grant
(`one.cpp`) now state this explicitly:

```
ZGALAXY build. Controller component licensed under the ZeroTier
Source-Available License for Non-Commercial Use (nonfree/LICENSE.md).
Node/agent components licensed under Mozilla Public License v2.0.
```

## 3. Obligations kept in this fork

* Copyright notices of ZeroTier, Inc. retained in headers and `COPYRIGHT_NOTICE`.
* `LICENSE-MPL.txt` and `nonfree/LICENSE.md` retained unmodified.
* Modifications are clearly tracked in `docs/PATCHES.md` and by the git
  history of branch `zgalaxy-core`.

## 4. Trademarks

"ZeroTier" is a trademark of ZeroTier, Inc. We renamed the runtime product
(`ZGALAXY One`, `zgalaxy-one`) to avoid implying endorsement, while retaining
the required attribution. This fork does not claim to be the official
ZeroTier product.

## 5. Recommended legal review

This document is a technical summary, not legal advice. Before publishing or
distributing this fork commercially:

1. Review `nonfree/LICENSE.md` in full.
2. Confirm the intended use qualifies as Non-Commercial, or obtain a
   commercial license from ZeroTier, Inc.
3. Decide whether the controller should be excluded from distribution (if the
   deployment uses an external controller instead of the embedded one).
