# Building ZGALAXY One

## Prerequisites (Linux)

| Tool | Purpose |
|------|---------|
| `gcc` / `g++` (or `clang` / `clang++`) | C/C++ compiler |
| `make` | Build driver |
| Rust toolchain (`cargo` / `rustc`) | Builds `rustybits` (the OIDC helper library) |
| `libssl-dev` | OpenSSL headers (link time) |
| `miniupnpc`, `libnatpmp` dev packages | NAT traversal (optional but default) |

The build was verified on Arch Linux with GCC 16 / clang and GNU Make 4.4.1.

## Building

```bash
# From the repository root
cd /home/ggonlinux/zt/zerotierone   # or wherever you cloned

# Regular build (engine + embedded controller via ZT_NONFREE=1)
make -j$(nproc)
```

The build:

1. Compiles the Rust `rustybits` crate (first run downloads crates).
2. Compiles the C/C++ engine (`node/`, `osdep/`, `service/`, `one.cpp`).
3. When `ZT_NONFREE=1` (set by default in `make-linux.mk`), also builds the
   embedded controller (`nonfree/controller/`).
4. Produces `zerotier-one` and symlinks `zerotier-idtool` → `zerotier-one`
   and `zerotier-cli` → `zerotier-one`.

## Outputs

| Artifact | Notes |
|----------|-------|
| `zerotier-one` | The daemon (≈17.5 MB). Acts as `zerotier-one`, `zerotier-cli`, or `zerotier-idtool` depending on `argv[0]`. |
| `zerotier-idtool` | Symlink — identity/moon/planet tooling |
| `zerotier-cli` | Symlink — CLI client for the local node |

## Build flags / variants

| Make var | Effect |
|----------|--------|
| `ZT_NONFREE=1` | Include the embedded controller (`nonfree/controller/`). Default on Linux. Needed by ztnet. |
| `ZT1_CENTRAL_CONTROLLER` | NOT supported / not built — would require Google Cloud, Redis, PostgreSQL stacks. Explicitly avoided. |
| `ZT_SOFTWARE_UPDATE_DEFAULT` | Already `"disable"`. |
| `ZT_SDK` | Undefined here; would compile out the TCP fallback relay region (now removed regardless). |

## Clean rebuild

```bash
make clean && make -j$(nproc)
```

## Sanity check after build

```bash
./zerotier-one -v        # prints: 1.16.2
./zerotier-one -h        # prints "ZGALAXY One version 1.16.2"
strings zerotier-one | grep -E "204\.80\.128|my\.zerotier|central\.zerotier|updates\.zerotier"
# expected: no output
```

See [VERIFICATION.md](VERIFICATION.md) for the full verification checklist.

## IP-agnostic build (no embedded IP addresses)

Since the round of changes for dynamic-IP support, **the client binary ships
WITHOUT any baked default world / IP address** (`node/Topology.cpp` no longer
embeds a world). Consequences:

- `strings zerotier-one` contains **no** service IPs (e.g. `192.168.`, the
  ZGALAXY public IP, the legacy `154.253.231.164`, etc.).
- On first boot the client has no planet roots (`planetWorldId 0`, offline).
- The current planet — with the **live** ZGALAXY IP — is supplied at run time
  by the companion module (below), so the client never needs rebuilding when
  the service's public address changes.

Verify after building:

```bash
strings zerotier-one | grep -cE "192\.168\.|105\.97\.|154\.253\.|0\.0\.0\.0/9994"   # expect 0
```

## Companion module: connectivity watchdog (reactive dynamic IP)

ZeroTier's engine is IP-only — it cannot resolve hostname endpoints. Dynamic-IP
handling is therefore delegated to a module installed **alongside** the client:

| File | Purpose |
|------|---------|
| `client/zgalaxy-watch.sh` + `zgalaxy-watch.service` | Runs continuously; every 10 s checks whether the client is connected to the ZGALAXY root. **When connected it does nothing.** Only on a detected disconnection does it act. |
| `client/zgalaxy-planet-sync.sh` | The action: resolves `dz.dreamzone.cc`, fetches the updated planet (with the current IP) from the ZGALAXY engine, applies it and restarts `zerotier-one` to re-link automatically. |

This is **event-driven, not periodic** — while the connection is healthy there
is no planet fetching.

## Install (one-line, recommended)

```bash
curl -sSL https://raw.githubusercontent.com/dreamzone-cc/zgalaxy-core/zgalaxy-core/install.sh | sudo bash
```

`install.sh`:

1. detects the distro, installs build deps + Rust,
2. builds ZGALAXY One from source (`ZT_NONFREE=1`, **no baked IP**),
3. installs binaries to `/usr/sbin` and a systemd service,
4. installs + starts the **connectivity watchdog** (`zgalaxy-watch.service`),
5. applies the current planet immediately so the client connects on first boot.

## Prebuilt binaries (no build required)

Ready-to-run, IP-agnostic binaries are shipped in `dist/` and on the
[v1.16.2-zgalaxy release](https://github.com/dreamzone-cc/zgalaxy-core/releases):

| File | Platform |
|------|----------|
| `zgalaxy-one-linux-x86_64-ubuntu26` | Ubuntu 26.04+ |
| `zgalaxy-one-linux-x86_64-glibc2.39` | Ubuntu 24.04+ / Debian 13+ |
| `zgalaxy-one-linux-x86_64-arch` | Arch Linux |

All three are built from the same source and contain **no embedded IPs**.

## Building on the Ubuntu Server

On Ubuntu, run `install.sh` (it clones, builds and installs in place) — or
build manually:

```bash
cd /opt/zgalaxy-one-src          # after install.sh, or clone the repo here
git fetch origin zgalaxy-core && git reset --hard FETCH_HEAD
make clean && make ZT_NONFREE=1 -j$(nproc)
sudo install -m755 zerotier-one /usr/sbin/zerotier-one
```
