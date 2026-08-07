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
