# ZGALAXY One ΓÇö Release Notes

## 2026-08-11 ΓÇö v1.16.2-zgalaxy (IP-Agnostic Build)

Latest release of the ZGALAXY client ΓÇö **Linux and Windows** from the same
source. Focus of this release: a **native, domain-based dynamic-IP layer** and
full **planet/moon independence**, shipped for every platform.

### Key fixes & features in this release

1. **Native reactive dynamic-DNS layer** (all platforms)
   - Connects via a reference domain name (`dz.dreamzone.cc`); the client
     resolves it at startup and re-resolves it on disconnect ΓÇö **no fixed IP
     is ever baked or configured** (the platform's IP is dynamic).
   - **Bounded validation** (`zgalaxyValidateIntervalMinutes`) plus an
     automatic fallback that re-resolves the domain of the affected world when
     a connection is lost ΓÇö no service restart.
   - Multi-A record support and graceful re-link (peer reset).

2. **Planet & moon independence** (all platforms)
   - The planet and moons are **external, importable world files** ΓÇö no
     recompilation to add or swap them.
   - **Auto-import from the ZGALAXY engine** at startup (`zgalaxyEngineUrl`):
     the client downloads the current `planet` and configured moons over the
     public endpoints, so worlds update automatically.
   - **Moons use the domain mechanism too** (`zgalaxyMoons`): their endpoints
     are resolved and refreshed dynamically.
   - **Runtime `moons.d` watcher**: adding/removing a `.moon` file is picked up
     within seconds ΓÇö no restart.

3. **Windows x64**
   - Fixed the **Windows-only compile error C1083 (`netdb.h`)** in
     `service/OneService.cpp`: the dynamic-DNS include block now tests
     `#if defined(_WIN32) || defined(_WIN64)` (it previously tested
     `__WINDOWS__` before `node/Constants.hpp` defines it).
   - Ship `zgalaxy-one-windows-x64.exe`, `ZGALAXY-One-Setup.exe` (NSIS
     installer: service + firewall + NDIS6 tap driver) and `driver/`
     (`zttap300.{cat,inf,sys}`).
   - **Desktop Control Panel** (`zgalaxy_desktop_ui.exe`, Rust + libui-ng +
     tray, from `DesktopUI/`) is now **built by `windows/build-windows.ps1`**
     and bundled in the installer as `zerotier_desktop_ui.exe` /
     `zgalaxy_desktop_ui.exe`. It was previously referenced by the installer
     but never built, so the Control Panel shortcuts pointed at a missing
     binary.

4. **Linux x64** (three prebuilt binaries)
   - `zgalaxy-one-linux-x86_64-arch`
   - `zgalaxy-one-linux-x86_64-glibc2.39`
   - `zgalaxy-one-linux-x86_64-ubuntu26`
   - All built from the latest source, **IP-agnostic** (zero embedded IPs),
     with the controller enabled (`ZT_NONFREE=1`).

5. **Verification & docs**
   - Integration deep-test suite (`tests/integration-test.sh`) ΓÇö **22/22
     passing** (domain mechanism, engine integration, client layer, reactive
     fallback, mesh ping, client independence).
   - Reports: `docs/CONNECTION-PROTOCOLS-REPORT.md`,
     `docs/DEEP-EXAMINATION-REPORT.md`, `docs/DYNAMIC-IP-IMPLEMENTATION.md`.

### Artifacts
- `dist/` (repo) and the `v1.16.2-zgalaxy` Release:
  Linux binaries (├ù3), Windows binary + installer + zip, NDIS6 tap driver.
- The ZGALAXY engine (planet/moon platform) is released separately in
  `dreamzone-cc/ZGALAXY` (v1.3.1).

---

## Older releases (kept for reference)

- **2026-05-20 ΓÇö 1.16.2**: line-ending fix for `zttap300.inf`; internal
  controller updates; increased `ZT_MAX_NETWORK_SPECIALISTS` to 512; faster
  network leave/join on Windows; compiler-warning cleanup (GCC 14, Clang 18/21).
- **2025-12-22 ΓÇö 1.16.1**: metrics disabled by default (`enableMetrics`);
  metrics in daemon mode; minor Mac/BSD tun/tap fixes.
- **2025-08-21 ΓÇö 1.16.0**: MPL licensing for core/service; controller under a
  source-available license (`make ZT_NONFREE=1`); and earlier history.
