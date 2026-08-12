# Building ZGALAXY One for Windows

This guide covers producing the **ZGALAXY One** Windows client (ZeroTier 1.16.2
fork wired exclusively to the ZGALAXY private planet) and a Windows installer.

## Option A — Build via GitHub Actions (no local Windows machine needed)

Push the `zgalaxy-core` branch; the `.github/workflows/windows-build.yml`
workflow builds the x64 binaries and the NSIS installer automatically.

1. Go to **Actions → Windows Build → Run workflow** (or push to the branch).
2. Download the **zgalaxy-one-windows-x64** artifact.
3. Run `ZGALAXY-One-Setup.exe` (admin) on the target Windows machine.

The artifact contains:
- `zerotier-one.exe`, `zerotier-cli.exe`, `zerotier-idtool.exe`
- `ZGALAXY-One-Setup.exe` (NSIS installer)

## Option B — Build locally on Windows

### Prerequisites
- **Visual Studio 2022** with the *Desktop development with C++* workload
- **Rust** toolchain (installed automatically by the script if missing)
- For the Desktop UI (`DesktopUI/`, Rust + libui-ng + tray): **Meson/Ninja**,
  **MinGW GCC + GNU make**, and the `x86_64-pc-windows-msvc` Rust target.
  The build script uses them if present.

### Steps
```powershell
# from a PowerShell (admin) prompt, at the repo root
.\windows\build-windows.ps1
```
This:
1. Locates MSBuild via VS2022.
2. Installs Rust (if missing) and the `x86_64-pc-windows-msvc` target.
3. Builds `rustybits/zeroidc` (Rust helper lib, release).
4. Builds the engine project → `windows\Build\x64\Release\zerotier-one_x64.exe`.
5. Builds the Desktop UI (`DesktopUI/zgalaxy_desktop_ui.exe`) — libui-ng via
   Meson/Ninja (under the MSVC env), the tray helper via GCC/make, then the Rust
   app — and copies it into `windows\dist\` as both `zerotier_desktop_ui.exe`
   and `zgalaxy_desktop_ui.exe`.
6. Copies the outputs into `windows\dist\`.

> **Note (Windows compile fix):** `service/OneService.cpp` previously failed on
> Windows with `error C1083: cannot open include file: 'netdb.h'`. The dynamic-DNS
> layer included a `#ifdef __WINDOWS__` block before `node/Constants.hpp` (which
> defines that macro) is included, so the preprocessor took the `#else` branch and
> tried to include POSIX headers. Fixed by using `#if defined(_WIN32) || defined(_WIN64)`
> (compiler-defined, order-independent). See `docs/FIX-ONESERVICE-WINDOWS-INCLUDE.md`.

### Build the installer
```powershell
# install NSIS from https://nsis.sourceforge.io
makensis .\windows\installer\ZGALAXY-One.nsi
```
Produces `windows\installer\ZGALAXY-One-Setup.exe`.

## What the installer does
- Installs the binaries + Desktop UI to `C:\Program Files\ZGALAXY One\`.
- Registers the **ZeroTierOneService** Windows service (auto-start).
- Adds firewall rules for UDP `9993` inbound + the binary.
- Installs the **ZGALAXY planet** and a default `local.conf` (with
  `zgalaxyDomain` + `zgalaxyEngineUrl`) into `%ProgramData%\ZeroTier\One\` so a
  **fresh machine connects immediately** (the client is IP-agnostic — without
  the planet file it stays OFFLINE; an existing `local.conf` is never
  overwritten on upgrades).
- Provides an uninstaller (keeps your network identity in
  `%ProgramData%\ZeroTier\One`).

## ⚠️ NDIS6 tap driver note
ZeroTier Windows clients use the **NDIS6 tap driver** (`zttap300`) to create
virtual network interfaces. The driver is a separate project
(`windows\TapDriver6`) that requires the **Windows Driver Kit (WDK)** and
driver signing.

- Without the driver, the client can still run, peer with the ZGALAXY planet,
  and manage networks, but it **cannot create a virtual NIC** (no assigned IP).
- For full client functionality, build and install `zttap300.inf` via the WDK
  (and enable test-signing for an unsigned build), or use a signed release.

## Verify the build
```cmd
C:\Program Files\ZGALAXY One\zerotier-one.exe -v        :: 1.16.2
C:\Program Files\ZGALAXY One\zerotier-cli.exe info
C:\Program Files\ZGALAXY One\zerotier-cli.exe join <network-id>
```
The `planetWorldId` reported must be `149604618` (ZGALAXY planet) and
`listpeers` must show only ZGALAXY infrastructure.

## IP-agnostic build (same as Linux)

The Windows build uses the same source as Linux, so it **also ships WITHOUT any
baked IP address** (`node/Topology.cpp` has no embedded world). The current
planet — with the live ZGALAXY IP — must be supplied at run time.

- On first run the client writes the (empty) default world and is offline until
  a real `planet` file is placed in `%ProgramData%\ZeroTier\One\`.
- The Windows companion watchdog (Windows equivalent of the systemd
  `client/zgalaxy-watch.service` + `zgalaxy-planet-sync.sh`) lives in
  `windows\watchdog\` — see below.

## Windows watchdog (dynamic-IP companion)

The ZGALAXY domain (`dz.dreamzone.cc`) changes IP over time, and ZeroTier is
IP-only (hostnames are dropped from the planet). The Windows client therefore
ships with the same **reactive** companion as Linux: it does nothing while the
client is connected, and only re-links when the connection is lost.

- `windows\watchdog\ZGALAXY-Planet-Sync.ps1` — the action (one-shot): checks
  `zerotier-cli listpeers` for the root `069ae38092`; if still connected it
  exits immediately. On disconnect it resolves `dz.dreamzone.cc`, fetches the
  latest planet from the ZGALAXY engine, applies it to
  `%ProgramData%\ZeroTier\One\planet` and restarts the `ZeroTierOneService`
  (including a stopped one).
- `windows\watchdog\install-watchdog.ps1` — registers the **ZGALAXY One
  Watchdog** scheduled task (runs every 1 minute as SYSTEM, restarts on
  failure).

Install it on the target machine (admin PowerShell, after installing the
client):

```powershell
cd "C:\Program Files\ZGALAXY One"
# copy windows\watchdog\* into the install dir first, then:
powershell -ExecutionPolicy Bypass -File install-watchdog.ps1
```

Tune via environment variables (defaults shown):
`ZGALAXY_DOMAIN=dz.dreamzone.cc`, `ZGALAXY_ROOT_ID=069ae38092`,
`ZGALAXY_PLANET_URL=http://dz.dreamzone.cc:3000/api/v1/planet/download`,
`ZGALAXY_DATA_DIR=%ProgramData%\ZeroTier\One`,
`ZGALAXY_SERVICE_NAME=ZeroTierOneService`.

Activity is logged to `%ProgramData%\ZeroTier\One\zgalaxy-watch.log`.
