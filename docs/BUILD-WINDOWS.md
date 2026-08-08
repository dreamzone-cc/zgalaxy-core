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

### Steps
```powershell
# from a PowerShell (admin) prompt, at the repo root
.\windows\build-windows.ps1
```
This:
1. Locates MSBuild via VS2022.
2. Installs Rust (if missing) and the `x86_64-pc-windows-msvc` target.
3. Builds `rustybits/zeroidc` (Rust helper lib).
4. Builds the engine project → `windows\Build\x64\Release\zerotier-one_x64.exe`.
5. Copies the outputs into `windows\dist\`.

### Build the installer
```powershell
# install NSIS from https://nsis.sourceforge.io
makensis .\windows\installer\ZGALAXY-One.nsi
```
Produces `windows\installer\ZGALAXY-One-Setup.exe`.

## What the installer does
- Installs the three binaries to `C:\Program Files\ZGALAXY One\`.
- Registers the **ZeroTierOneService** Windows service (auto-start).
- Adds firewall rules for UDP `9993` inbound + the binary.
- Provides an uninstaller (keeps your network data in `%ProgramData%\ZeroTier\One`).

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
- The Linux companion watchdog (`client/zgalaxy-watch.sh`) is systemd-based; a
  Windows equivalent (Task Scheduler or a small service that copies the planet
  from the ZGALAXY engine and restarts the service on disconnect) is planned
  for the Windows release.
