#!/usr/bin/env bash
# =============================================================================
# ZGALAXY One — one-line installer
#
#   curl -sSL https://raw.githubusercontent.com/dreamzone-cc/zgalaxy-core/zgalaxy-core/install.sh | sudo bash
#
# Builds the ZGALAXY One client (ZeroTier 1.16.2 fork wired exclusively to the
# ZGALAXY private planet) from source, installs it to /usr/sbin, registers a
# systemd service and starts it. Requires root.
#
# Supported: Ubuntu/Debian, Fedora/RHEL, Arch, Alpine (musl).
# =============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Please run as root: sudo bash install.sh"
  exit 1
fi

REPO_URL="${REPO_URL:-https://github.com/dreamzone-cc/zgalaxy-core.git}"
BRANCH="${BRANCH:-zgalaxy-core}"
SRC_DIR="${SRC_DIR:-/opt/zgalaxy-one-src}"
ZT_BIN="/usr/sbin/zerotier-one"
PORT="${ZT_PORT:-9993}"

log() { echo "[ZGALAXY] $*"; }
die() { echo "[ZGALAXY ERROR] $*" >&2; exit 1; }

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu|debian|linuxmint|pop) echo "debian" ;;
      fedora|rhel|centos|rocky|almalinux) echo "redhat" ;;
      arch|manjaro|cachyos|endeavouros) echo "arch" ;;
      alpine) echo "alpine" ;;
      *) echo "unknown" ;;
    esac
  else
    echo "unknown"
  fi
}

install_deps() {
  local os="$1"
  log "Installing build dependencies for $os..."
  case "$os" in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq build-essential gcc g++ make git curl pkg-config \
        libssl-dev libminiupnpc-dev libnatpmp-dev linux-libc-dev
      ;;
    redhat)
      dnf install -y gcc gcc-c++ make git curl pkg-config openssl-devel \
        miniupnpc-devel libnatpmp-devel kernel-headers
      ;;
    arch)
      pacman -S --needed --noconfirm base-devel gcc make git curl openssl \
        miniupnpc libnatpmp linux-headers
      ;;
    alpine)
      apk add --no-cache build-base gcc g++ make git curl openssl-dev \
        miniupnpc-dev libnatpmp-dev linux-headers
      ;;
    *)
      die "Unsupported OS. Install build tools manually, then set SRC_DIR to a prepared source tree."
      ;;
  esac
}

ensure_rust() {
  if command -v cargo >/dev/null 2>&1; then
    local ver
    ver="$(cargo --version 2>/dev/null | awk '{print $2}')"
    log "cargo $ver present"
    return 0
  fi
  log "Installing Rust via rustup (required to build rustybits/zeroidc)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  export PATH="$HOME/.cargo/bin:$PATH"
}

build() {
  log "Cloning zgalaxy-core (branch $BRANCH) into $SRC_DIR..."
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SRC_DIR" \
    || die "git clone failed (check network / repo access)."
  cd "$SRC_DIR"

  if [ "$(detect_os)" = "alpine" ]; then
    # musl build needs glibc-symbol shims used by the vendored nlohmann::json
    log "Applying musl compatibility shim..."
    cat > shim.c <<'SHIM'
#include <stdlib.h>
#include <stdio.h>
int __libc_single_threaded = 1;
long __isoc23_strtol(const char* n, char** e, int b){ return strtol(n,e,b); }
long long __isoc23_strtoll(const char* n, char** e, int b){ return strtoll(n,e,b); }
unsigned long __isoc23_strtoul(const char* n, char** e, int b){ return strtoul(n,e,b); }
unsigned long long __isoc23_strtoull(const char* n, char** e, int b){ return strtoull(n,e,b); }
float __isoc23_strtof(const char* n, char** e){ return strtof(n,e); }
double __isoc23_strtod(const char* n, char** e){ return strtod(n,e); }
long double __isoc23_strtold(const char* n, char** e){ return strtold(n,e); }
SHIM
    gcc -c -o shim.o shim.c
    make ZT_NONFREE=1 LDLIBS="/$SRC_DIR/shim.o" -j"$(nproc)"
  else
    make ZT_NONFREE=1 -j"$(nproc)"
  fi
  [ -x zerotier-one ] || die "build did not produce zerotier-one"
}

install_binaries() {
  log "Installing binaries to /usr/sbin..."
  install -m 0755 "$SRC_DIR/zerotier-one" "$ZT_BIN"
  ln -sf "$ZT_BIN" /usr/sbin/zerotier-cli
  ln -sf "$ZT_BIN" /usr/sbin/zerotier-idtool
  mkdir -p /var/lib/zerotier-one
}

install_service() {
  if [ ! -d /run/systemd/system ]; then
    log "systemd not detected — skipping service registration (start manually: $ZT_BIN -d -p$PORT)"
    return 0
  fi
  log "Installing systemd service..."
  cat > /etc/systemd/system/zerotier-one.service <<UNIT
[Unit]
Description=ZeroTier One - ZGALAXY private planet client
After=network.target
Wants=network.target

[Service]
Type=forking
PIDFile=/var/lib/zerotier-one/zerotier-one.pid
ExecStart=$ZT_BIN -d -p$PORT
Restart=always
RestartSec=2
User=root

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload || true
  systemctl enable zerotier-one >/dev/null 2>&1 || true
}

verify() {
  local v
  v="$("$ZT_BIN" -v 2>/dev/null)" || die "installed binary failed to run"
  log "Installed ZGALAXY One version: $v"
  log "Branding: $("$ZT_BIN" -h 2>/dev/null | head -1)"
  if strings "$ZT_BIN" 2>/dev/null | grep -qE "204\.80\.128|my\.zerotier|central\.zerotier"; then
    die "binary still contains official ZeroTier references — refusing."
  fi
  log "No official ZeroTier references detected ✓"
}

# ---------------------------------------------------------------- main
OS="$(detect_os)"
log "OS: $OS | arch: $(uname -m)"
install_deps "$OS"
ensure_rust
build
install_binaries
install_service

if [ -d /run/systemd/system ]; then
  log "Starting service..."
  systemctl restart zerotier-one || true
  sleep 5
  systemctl is-active zerotier-one >/dev/null 2>&1 \
    && log "Service active" || log "Service did not start — check: journalctl -u zerotier-one"
else
  log "systemd not detected — starting in foreground briefly to verify..."
  timeout 8 "$ZT_BIN" -p"$PORT" >/dev/null 2>&1 || true
fi

verify
log "Done. Join a network with:  $ZT_BIN/../zerotier-cli join <network-id>  (or sudo zerotier-cli join <nwid>)"
