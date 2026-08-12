# ZGALAXY One Release Notes

## v1.16.2-zgalaxy (IP-Agnostic Build, 2026-08-11)

The latest ZGALAXY One client, built from a single source tree for Linux and
Windows x64. This release centers on a native, domain-based dynamic-IP layer
and full planet/moon independence, with an integrated Windows Desktop Control
Panel.

Changes are marked as General (all platforms), Windows only, or Linux only.

### Key changes

1. Native reactive dynamic-DNS layer (General)
   - Connects via a reference domain name; resolves at startup and re-resolves
     on disconnect. No fixed IP is ever baked or configured.
   - Bounded validation plus automatic re-resolution on connection loss, with
     no service restart.
   - Multi-A record support and graceful re-link.

2. Planet and moon independence (General)
   - Planet and moons are external, importable world files.
   - Auto-import from the ZGALAXY engine at startup over public endpoints.
   - Moons use the domain mechanism too; endpoints refresh dynamically.
   - Runtime moons.d watcher detects added or removed moon files within
     seconds, no restart.

3. Desktop Control Panel bundled (Windows only)
   - The Windows installer bundles the Desktop Control Panel
     (zgalaxy_desktop_ui / zerotier_desktop_ui).

4. Windows build and runtime fixes (Windows only)
   - Fixed the Windows-only compile error C1083 (netdb.h) in
     service/OneService.cpp (now tests _WIN32/_WIN64).
   - NSIS installer with service, firewall, and NDIS6 tap driver.

5. IP-agnostic Linux binaries (Linux only)
   - Prebuilt binaries: arch, glibc2.39, ubuntu26, with the controller
     enabled (ZT_NONFREE=1).

6. Verification (General)
   - Integration deep-test suite (tests/integration-test.sh), 22/22 passing.
   - Clean binaries: no embedded IPs, no official ZeroTier endpoints.

### Artifacts

- Linux: zgalaxy-one-linux-x86_64-arch, -glibc2.39, -ubuntu26
- Windows: zgalaxy-one-windows-x64.exe, ZGALAXY-One-Setup.exe,
  zgalaxy-one-windows-x64.zip, driver (zttap300.cat/inf/sys),
  zgalaxy_desktop_ui.exe / zerotier_desktop_ui.exe

The ZGALAXY engine (planet/moon platform) is released separately in
dreamzone-cc/ZGALAXY (v1.3.1).
