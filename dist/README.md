# ZGALAXY One — prebuilt binaries

Ready-to-run ZGALAXY One binaries (ZeroTier 1.16.2 fork wired exclusively to
the ZGALAXY private planet). No build required — download, install, join.

> **IP-agnostic:** these binaries ship WITHOUT any embedded IP address. The
> ZGALAXY planet (with the current live IP) is supplied at run time by the
> companion module `client/zgalaxy-planet-sync.sh` (installed by `install.sh`),
> which resolves `dz.dreamzone.cc` and keeps the planet updated — so the client
> never needs rebuilding when the service's public IP changes.

| File | Platform | Built on | Runtime requirements |
|------|----------|----------|----------------------|
| `zgalaxy-one-linux-x86_64-ubuntu26` | Linux x86_64 | Ubuntu 26.04 | glibc ≥ 2.42 (Ubuntu 26.04+) · `libminiupnpc21` · `libnatpmp1` · `libssl3` |
| `zgalaxy-one-linux-x86_64-glibc2.39` | Linux x86_64 | Ubuntu 24.04 | glibc ≥ 2.39 (Ubuntu 24.04+, Debian 13+) · `libminiupnpc17` · `libnatpmp1` · `libssl3` |
| `zgalaxy-one-linux-x86_64-arch` | Linux x86_64 | Arch Linux | Arch glibc · `miniupnpc` · `libnatpmp` · `openssl` |

## Install (Linux)

```bash
# pick the file matching your distro, e.g.:
BIN=https://raw.githubusercontent.com/dreamzone-cc/zgalaxy-core/zgalaxy-core/dist/zgalaxy-one-linux-x86_64-ubuntu26
sudo curl -sSL -o /usr/sbin/zerotier-one "$BIN"
sudo chmod +x /usr/sbin/zerotier-one
sudo ln -sf /usr/sbin/zerotier-one /usr/sbin/zerotier-cli
sudo ln -sf /usr/sbin/zerotier-one /usr/sbin/zerotier-idtool
sudo mkdir -p /var/lib/zerotier-one
sudo /usr/sbin/zerotier-one -d
sudo /usr/sbin/zerotier-cli join <network-id>
```

## Verify

```bash
/usr/sbin/zerotier-one -h   # -> ZGALAXY One version 1.16.2
/usr/sbin/zerotier-cli info # planetWorldId must be 149604618
```

> Other distros / older glibc / musl: use `install.sh` (build-on-target):
> `curl -sSL https://raw.githubusercontent.com/dreamzone-cc/zgalaxy-core/zgalaxy-core/install.sh | sudo bash`
