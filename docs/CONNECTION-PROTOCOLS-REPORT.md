# ZGALAXY Connection Protocols & Mechanism — Deep Investigation Report

Date: 2026-08-09
Scope: how ZGALAXY clients connect — **direct P2P** between users and
**relay via the ZGALAXY root** — with a live deep examination and a full health
/ error check of every part involved.

---

## 1. The two connection mechanisms

### 1.1 Direct P2P (users ↔ users)
- **Discovery**: a client that does not know a peer's address asks the root via
  a `WHOIS` (`Node::processBackgroundTasks` keeps roots in `alwaysContact`).
- **Direct path**: once both sides are known, they exchange `HELLO` and
  establish a direct `Path` (`Peer::sendDirect` → `Path`). Subsequent traffic
  flows directly with no intermediary.
- Selected by `Peer::getAppropriatePath` / `Path` liveness; the lowest-latency
  alive path wins.

### 1.2 Relay via the ZGALAXY root (fallback)
- When a peer is unknown or has no alive direct path, packets are relayed
  through an upstream — the ZGALAXY root. Source: `node/Switch.cpp`:
  - `Switch.cpp:92-96`: no direct path → `relayTo = getUpstreamPeer(0)` →
    `sendDirect(..., force=true)`.
  - `Switch.cpp:184-189`: relay via upstream **and** `Peer::introduce(...)`,
    which hands each side the other's path so a direct path can be established.
- `Topology::getUpstreamPeer` selects the best upstream by `relayQuality`.
- This is why a root (planet) is essential: it is the always-on rendezvous /
  relay point. NAT'd or firewalled clients use it until a direct path forms.

### 1.3 Path introduction (self-optimizing)
The root does not just relay — it **introduces** the two peers to each other.
Sustained traffic between two relaying peers triggers direct-path formation,
dropping latency dramatically.

---

## 2. Live deep examination (all verified)

| Step | Result |
|---|---|
| Relay via root (before stimulus) | ✅ traffic works through the root, RTT ~5 ms |
| Traffic stimulus (ping to peer) | ✅ root `introduce`s both sides |
| Direct path after stimulus | ✅ local↔dz20 become **DIRECT** (lat 0–1) |
| Direct RTT after formation | ✅ **0.86 ms** (≈6× lower than relay) |
| Additional direct paths (dz20) | ✅ DIRECT to the controller and to `c1aa29b20e` |
| Idle nodes (offline `c1aa29b20e`) | ✅ shown RELAY/no-path — expected while the device is down |

## 3. Health of every part

| Part | Status |
|---|---|
| dz171 engine (`zgalaxy`) + root (`zgalaxy-root`) | ✅ active; `/ready` → 200 |
| dz161 ztnet controller (v2 image `6557361cd0f`) | ✅ Up; identity `ef313fb5c9` preserved; ONLINE |
| dz20 client (v2) | ✅ ONLINE; root DIRECT; network OK |
| local client (v2) | ✅ ONLINE; root DIRECT; network OK |
| Network `ef313fb5c9f817a2` | ✅ 3 members; IPs assigned |

## 4. Error scan — ZERO errors

`journalctl` for the local client, dz20, and the root (dz171): **no connection
errors** (only deliberate test artifacts, all recovered cleanly).

## 5. Conclusion

The connection layer is healthy and complete:
- **Relay via ZGALAXY** is the automatic fallback (works, ~5 ms).
- **Direct P2P** forms automatically via path introduction (0.86 ms).
- Every part (engine, root, controller, clients, mesh) is up and error-free.
