# Verification

How to confirm that a ZGALAXY One build is fully independent from the official
ZeroTier service.

## 1. Static checks on the binary

```bash
# No official relay endpoint
strings zerotier-one | grep -c "204.80.128.1" || echo "OK: no official relay"

# No official cloud control-plane domains
strings zerotier-one | grep -iE "my\.zerotier\.com|central\.zerotier\.com|updates\.zerotier\.com" \
  || echo "OK: no official cloud endpoints"

# The ZGALAXY planet root is present in the binary
strings zerotier-one | grep -c "192.168.1.171" || echo "check planet bytes directly"
```

Binary-level grep for the planet is limited (the world is binary data), so the
strongest static check is comparing the embedded array with the source:

```bash
# Extract the bytes from node/Topology.cpp and compare with zgalaxy/planet.bin
python3 - <<'EOF'
import re, pathlib
src = pathlib.Path('node/Topology.cpp').read_text()
m = re.search(r'ZT_DEFAULT_WORLD\[ZT_DEFAULT_WORLD_LENGTH\] = \{(.*?)\};', src, re.S)
bytes_ = bytes(int(x, 16) for x in re.findall(r'0x([0-9a-f]{2})', m.group(1)))
assert bytes_ == pathlib.Path('zgalaxy/planet.bin').read_bytes(), "planet mismatch!"
print("OK: embedded planet == zgalaxy/planet.bin (", len(bytes_), "bytes )")
EOF
```

## 2. Runtime check

Run the daemon against a scratch home directory (root required for tap
creation, but the node can be started without a tap for the peer/planet test):

```bash
mkdir -p /tmp/zgtest && cd /tmp/zgtest
sudo /path/to/zerotier-one -d -p9995 .
# wait a few seconds, then query the local node
sudo zerotier-cli -D /tmp/zgtest status
sudo zerotier-cli -D /tmp/zgtest peers
```

Expected:

* `status` shows `ONLINE`.
* `peers` lists `PLANET` role peers whose paths are **only** ZGALAXY roots
  (e.g. `192.168.1.171/9994`).
* **No** peer and **no** path should resolve to any ZeroTier, Inc.
  infrastructure.

## 3. Filesystem checks (applied deployment)

After deploying, confirm on every node:

```bash
# planet must be the ZGALAXY planet (271 bytes, root 069ae38092)
ls -l /var/lib/zerotier-one/planet
xxd /var/lib/zerotier-one/planet | head -1
# expect: 00000000: 0100 0000 0008 eac9 0a00 0001 6ce3 e239 ...

# no official relay
jq '.settings.allowTcpFallbackRelay' /var/lib/zerotier-one/local.conf   # expect false or absent
```

## 4. Continuous verification (proposed CI)

When the project is wired into GitHub Actions, add a job that:

1. Greps the source tree for official domains (`my.zerotier.com`,
   `central.zerotier.com`, `updates.zerotier.com`, `204.80.128.1`).
2. Verifies the embedded planet matches `zgalaxy/planet.bin`.
3. Builds and runs the binary-level `strings` checks above.
4. Fails the pipeline on any hit.

This prevents future upstream merges from re-introducing official
dependencies.

## 5. What "no official dependency" means here

* The node only ever connects to ZGALAXY planet/moon roots.
* No update service is contacted (software update disabled; updates would be
  signed by the ZGALAXY planet's key).
* No `my.zerotier.com`-style network API is used (network config comes from
  the embedded controller that ztnet drives).
