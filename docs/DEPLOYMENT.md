# Deployment

Deploying a ZGALAXY One build onto the two production servers.

## Infrastructure summary

| Server | IP | SSH (user@host) | Role | Current engine |
|--------|----|-----------------|------|----------------|
| ZGALAXY | `192.168.1.171` | `<deploy-user>@192.168.1.171` | Planet root, port UDP `9994` | `zerotier-one` v1.14.2 |
| ztnet | `192.168.1.161` | `<deploy-user>@192.168.1.161` | Controller (ztnet + embedded zerotier) | docker `zyclonite/zerotier:1.16.2` |

## Strategy

**Phase 1 — Runtime patch (no rebuild):** replace `planet` files and set
`local.conf` to disable the TCP fallback relay. This is safe and reversible.

**Phase 2 — Binary replacement:** swap the official engine binary for a
ZGALAXY One build (this fork). Because the ZGALAXY planet is now baked into
the binary, no external `planet` file is even required (though keeping one is
harmless).

## ztnet specifics

ztnet's controller lives inside a Docker container:

```
services:
  zerotier:
    image: zyclonite/zerotier:1.16.2   # ← replace with a ZGALAXY One image
    ...
    volumes:
      - zerotier:/var/lib/zerotier-one  # planet / local.conf live here
```

To use the patched engine:

1. Build a container image from this fork (or copy `zerotier-one` into the
   existing volume and run it directly).
2. Update `docker-compose.yml` to reference the new image.
3. `docker compose up -d`.

**ztnet itself (`sinamics/ztnet:latest`) is untouched** — it only talks to the
ZeroTier API, which is unchanged.

## Steps on ZGALAXY (192.168.1.171)

```bash
# 1. Disable the official TCP fallback relay at runtime (already preferred)
#    /var/lib/zerotier-one/local.conf
#    { "settings": { "primaryPort": 9994, "portMappingEnabled": false, "allowTcpFallbackRelay": false } }

# 2. Ensure the ZGALAXY planet is in place
#    /var/lib/zerotier-one/planet  (271 bytes, root 069ae38092)

# 3. Replace the engine binary
sudo cp /path/to/zerotier-one /usr/sbin/zerotier-one
sudo systemctl restart zerotier-one   # or restart the process manager used

# 4. Verify
zerotier-cli status
zerotier-cli peers    # PLANET = 069ae38092 @ 192.168.1.171/9994, no official roots
```

## Steps on ztnet (192.168.1.161)

```bash
# 1. Planet already shared via the ztnet_zerotier volume; confirm it matches
#    zgalaxy/planet.bin

# 2. Disable TCP fallback in the container's local.conf
docker exec zerotier sh -c \
  'jq ".settings.allowTcpFallbackRelay=false" /var/lib/zerotier-one/local.conf > /tmp/lc && mv /tmp/lc /var/lib/zerotier-one/local.conf'
docker restart zerotier

# 3. (Phase 2) Swap image to a ZGALAXY One build and restart the stack
docker compose up -d
```

## Rollback

* Keep a backup of the previous `planet` file and `local.conf` on each node.
* Phase 1 changes are reverted by restoring those files.
* Phase 2 changes are reverted by restoring the previous image/binary.

## Note on version skew

The ZGALAXY planet server currently runs v1.14.2 while ztnet runs v1.16.2.
ZeroTier nodes are generally forward/backward compatible across minor
versions, and the protocol has not changed between 1.14 and 1.16. For
consistency, the plan is to converge everything on the ZGALAXY One v1.16.2
build from this fork.
