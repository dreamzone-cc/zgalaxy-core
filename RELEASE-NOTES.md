# ZGALAXY One — Release Notes

## v1.16.2-zgalaxy — 2026-08-11 (IP-Agnostic Build)

The latest ZGALAXY One client, built from a single source tree for **Linux and
Windows x64**. This release centers on a **native, domain-based dynamic-IP
layer** and full **planet/moon independence**, with a fully integrated Windows
Desktop Control Panel.

---

### Highlights

| # | Change | Scope |
|---|--------|-------|
| 1 | Native reactive dynamic-DNS layer (no fixed IP ever baked) | All platforms |
| 2 | Full planet/moon independence (worlds are importable files) | All platforms |
| 3 | Desktop Control Panel bundled in the Windows installer | Windows only |
| 4 | Windows build fixes (compile error, installer, build pipeline) | Windows only |
| 5 | IP-agnostic Linux binaries with embedded controller | Linux only |

---

### 1. Native reactive dynamic-DNS layer — *All platforms*

- Connects via a reference domain name (`dz.dreamzone.cc`); the client resolves
  it at startup and re-resolves it on disconnect — **no fixed IP is ever baked
  or configured**.
- **Bounded validation** (`zgalaxyValidateIntervalMinutes`) plus automatic
  re-resolution of the affected world on connection loss — no service restart.
- Multi-A record support with graceful re-link (peer reset).

### 2. Full planet/moon independence — *All platforms*

- The planet and moons are **external, importable world files** — swap or add
  them without recompilation.
- **Auto-import from the ZGALAXY engine** at startup (`zgalaxyEngineUrl`):
  downloads the current `planet` and configured moons over public endpoints.
- **Moons use the domain mechanism too** (`zgalaxyMoons`) — endpoints are
  resolved and refreshed dynamically.
- **Runtime `moons.d` watcher**: adding/removing a `.moon` file is picked up in
  seconds — no restart.

### 3. Desktop Control Panel bundled — *Windows only*

- **New**: `DesktopUI/` (Rust + libui-ng + tray) is now built automatically by
  `windows/build-windows.ps1` and shipped as `zgalaxy_desktop_ui.exe` /
  `zerotier_desktop_ui.exe`.
- Fixes the previous installer issue where the Control Panel was referenced but
  never built, leaving its shortcuts pointing at a missing binary.
- Installed with Start Menu + Desktop shortcuts by `ZGALAXY-One-Setup.exe`.

### 4. Windows build & runtime fixes — *Windows only*

- **Fixed Windows-only compile error `C1083 (netdb.h)`** in
  `service/OneService.cpp`: the dynamic-DNS include block now tests
  `#if defined(_WIN32) || defined(_WIN64)` instead of `__WINDOWS__` (which is
  only defined after `node/Constants.hpp` is included).
- **Fixed `rustybits/zeroidc` linking**: built in `release` mode to match the
  path expected by `ZeroTierOne.vcxproj` (Release/x64).
- **Fixed MSBuild `SolutionDir` handling** so the engine links correctly even
  when the checkout path contains spaces.
- **Fixed the NSIS installer** to actually package the binaries it references
  (no more `File: ... no files found` warnings).

### 5. IP-agnostic Linux binaries — *Linux only*

- Three prebuilt x86_64 binaries: `-arch`, `-glibc2.39`, `-ubuntu26`.
- All **IP-agnostic** (zero embedded IPs) and built with the embedded
  controller enabled (`ZT_NONFREE=1`).

---

### Verification

- Deep integration test suite (`tests/integration-test.sh`) — **22/22 passing**
  (domain mechanism, engine integration, client layer, reactive fallback, mesh
  ping, client independence).
- Binaries verified against official ZeroTier references
  (`my.zerotier.com`, `central.zerotier.com`, `204.80.128`) — none present.
- Planet world `149604618` supplied at runtime from `zgalaxy/planet.bin`.

### Artifacts

- **Windows x64**: `zgalaxy-one-windows-x64.exe`, `ZGALAXY-One-Setup.exe`,
  `zgalaxy-one-windows-x64.zip`, `zgalaxy_desktop_ui.exe` /
  `zerotier_desktop_ui.exe`, NDIS6 tap driver (`zttap300.{cat,inf,sys}`).
- **Linux x86_64**: `zgalaxy-one-linux-x86_64-{arch,glibc2.39,ubuntu26}`.
- Full source and docs: `dist/` in the repo, plus the `v1.16.2-zgalaxy` Release.

> The ZGALAXY engine (planet/moon platform) is released separately in
> `dreamzone-cc/ZGALAXY`.
