# Deployment

Deploying a ZGALAXY One build onto the two production servers.

## Infrastructure summary

| Server | IP | Role | Engine |
|--------|----|------|--------|
| ZGALAXY | `192.168.1.171` | Planet root, port UDP `9994` | `zgalaxy-core` v1.16.2 (systemd `zgalaxy-root.service`) |
| ztnet | `192.168.1.161` | Controller (ztnet + embedded zerotier) | `zgalaxy-core` v1.16.2 (inside `zerotier` Docker container) |

## Important: build for the target platform

The two targets run **different libc implementations**, so the binary MUST be
built on the matching platform — a binary built for one will NOT run on the
other.

| Target | OS / libc | Build location |
|--------|-----------|----------------|
| ZGALAXY server (171) | Ubuntu 26.04, **glibc** 2.43, OpenSSL 3.5.5 | on the server itself |
| ztnet container (161) | Alpine Linux, **musl** libc, OpenSSL 3.5 | inside the container itself |

> A glibc build fails on Alpine (`EVP_idea_ofb` undefined symbol / musl loader
> errors) and a musl build will not run on glibc systems. Always build on the
> deployment target.

## 1. Build on the ZGALAXY server (192.168.1.171)

```bash
# Install build tools (one-time)
sudo apt-get install -y rustc cargo pkg-config libssl-dev \
  miniupnpc libnatpmp git make gcc g++

# Clone the fork and check out the stable branch
git clone https://github.com/dreamzone-cc/zgalaxy-core.git
cd zgalaxy-core
git checkout zgalaxy-core

# Build
make -j$(nproc)

# Sanity check the resulting binary
./zerotier-one -v              # 1.16.2
./zerotier-one -h | head -1    # "ZGALAXY One version 1.16.2"
strings zerotier-one | grep -cE "204.80.128|my.zerotier" || echo clean
```

## 2. Deploy on the ZGALAXY server (192.168.1.171)

```bash
# Stop the planet-root service, swap the binary, start again
sudo systemctl stop zgalaxy-root
sudo cp /home/<user>/zgalaxy/zerotier-one /home/<user>/zgalaxy/zerotier-one.bak.1.14.2
sudo cp /home/<user>/zgalaxy-core/zerotier-one /home/<user>/zgalaxy/zerotier-one
sudo chmod +x /home/<user>/zgalaxy/zerotier-one
sudo systemctl start zgalaxy-root

# Verify
sudo systemctl is-active zgalaxy-root   # active
/home/<user>/zgalaxy/zerotier-one -v    # 1.16.2
```

Notes:

* `local.conf` at `/var/lib/zerotier-one/local.conf`:
  `{"settings":{"primaryPort":9994,"portMappingEnabled":false,"allowTcpFallbackRelay":false}}`
* The ZGALAXY `planet` file lives at `/var/lib/zerotier-one/planet`.

## 3. Build inside the ztnet container (192.168.1.161)

The `zerotier` container is Alpine/musl, so the engine is built **inside the
container** to match its libc:

```bash
# Install build tools inside the container (one-time)
sudo docker exec zerotier sh -c \
  'apk add --no-cache build-base gcc g++ make git rust cargo pkgconfig openssl-dev linux-headers'

# Clone and build inside the container
sudo docker exec zerotier sh -c \
  'cd /tmp && git clone --depth 1 --branch zgalaxy-core https://github.com/dreamzone-cc/zgalaxy-core.git'
sudo docker exec zerotier sh -c 'cd /tmp/zgalaxy-core && make -j4'

# Sanity check
sudo docker exec zerotier sh -c 'cd /tmp/zgalaxy-core && ./zerotier-one -v'
```

> The in-container build tree lives under `/tmp` and is **ephemeral** — it is
> lost when the container is recreated. For a permanent solution, build a
> custom image from the fork (see below).

## 4. Deploy inside the ztnet container (192.168.1.161)

```bash
# Backup and swap the binary, then restart
sudo docker exec zerotier sh -c \
  'cp /usr/sbin/zerotier-one /usr/sbin/zerotier-one.bak.1.16.2 && cp /tmp/zgalaxy-core/zerotier-one /usr/sbin/zerotier-one && chmod +x /usr/sbin/zerotier-one'
sudo docker restart zerotier

# Verify
sudo docker exec zerotier zerotier-cli -v    # 1.16.2
sudo docker exec zerotier zerotier-cli status
sudo docker exec zerotier zerotier-cli peers
# expect: 069ae38092 1.16.2 PLANET DIRECT 192.168.1.171/9994
```

ztnet's `local.conf` inside the container
(`/var/lib/zerotier-one/local.conf`) has TCP fallback disabled:

```
{ "settings": { "primaryPort": 9993, "portMappingEnabled": true,
  "softwareUpdate": "disable", "allowManagementFrom": ["172.31.255.0/29"],
  "allowTcpFallbackRelay": false } }
```

**ztnet itself (`sinamics/ztnet:latest`) is untouched** — it only talks to the
ZeroTier API, which is unchanged.

## 5. Permanent container image (recommended)

For a reproducible ztnet deployment, build a Docker image from the fork
instead of patching a running container:

```
FROM zyclonite/zerotier:1.16.2
# or build from the zgalaxy-core sources with apk build tools, then:
COPY zerotier-one /usr/sbin/zerotier-one
```

Then update `docker-compose.yml`:

```yaml
services:
  zerotier:
    image: dreamzone-cc/zgalaxy-core:1.16.2   # custom image
    ...
    volumes:
      - zerotier:/var/lib/zerotier-one
```

and `docker compose up -d`.

## 6. End-to-end verification

```bash
# From ztnet (client side)
sudo docker exec zerotier zerotier-cli status    # ONLINE
sudo docker exec zerotier zerotier-cli peers     # PLANET 069ae38092 @ 192.168.1.171/9994, no official roots

# From ZGALAXY (root side)
sudo systemctl is-active zgalaxy-root            # active
```

Both sides report engine version **1.16.2** and peer role **PLANET** with the
ZGALAXY root. No peer or path should reference any ZeroTier, Inc.
infrastructure.

## Rollback

* Keep the backup binaries (`zerotier-one.bak.1.14.2`, `zerotier-one.bak.1.16.2`).
* Restore the backup and restart the service/container:
  * ZGALAXY: `sudo cp <backup> /home/<user>/zgalaxy/zerotier-one && sudo systemctl restart zgalaxy-root`
  * ztnet: `sudo docker exec zerotier sh -c 'cp <backup> /usr/sbin/zerotier-one' && sudo docker restart zerotier`

## Version state

As of the latest deployment, both servers run **zgalaxy-core v1.16.2**
(previously 1.14.2 on the root and 1.16.2 upstream image in the container).
ZeroTier nodes are generally forward/backward compatible across minor
versions; the ecosystem is now uniformly on the ZGALAXY One 1.16.2 build.
