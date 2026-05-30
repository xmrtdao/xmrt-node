#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
# XMRT-Node — Termux Android CLI Installer
# ═══════════════════════════════════════════════════════════════
# Installs the XMRT-Node CLI tool for Monero mining on Android
# via Termux. Part of the XMRT-DAO fleet ecosystem.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/xmrtdao/xmrt-node/main/cli/install-termux.sh | bash
#
# Or manually:
#   chmod +x install-termux.sh && ./install-termux.sh
# ═══════════════════════════════════════════════════════════════

set -e

# Colors
R='\033[31m'; G='\033[32m'; Y='\033[33m'; C='\033[36m'; N='\033[0m'

echo -e "${C}"
echo '╔══════════════════════════════════════════════╗'
echo '║       XMRT-Node — Termux Installer           ║'
echo '║       Android Mining Node for XMRT-DAO       ║'
echo '╚══════════════════════════════════════════════╝'
echo -e "${N}"

# ── Step 1: Check Termux ────────────────────────────────────────────────────
echo -e "${C}[*]${N} Checking Termux environment..."

if [ ! -d /data/data/com.termux ]; then
    echo -e "${R}[X]${N} This script must be run inside Termux on Android."
    echo "    Download Termux from F-Droid: https://f-droid.org/packages/com.termux/"
    exit 1
fi

# ── Step 2: Update packages ─────────────────────────────────────────────────
echo -e "${C}[*]${N} Updating Termux packages..."
pkg update -y 2>/dev/null || true
pkg upgrade -y 2>/dev/null || true

# ── Step 3: Install dependencies ────────────────────────────────────────────
echo -e "${C}[*]${N} Installing dependencies..."
pkg install -y python wget curl unzip git 2>/dev/null || true

# ── Step 4: Download CLI ────────────────────────────────────────────────────
echo -e "${C}[*]${N} Downloading XMRT-Node CLI..."
CLI_DIR="$HOME/.local/bin"
mkdir -p "$CLI_DIR"

CLI_URL="https://raw.githubusercontent.com/xmrtdao/xmrt-node/main/cli/xmrt-node"
if curl -fsSL "$CLI_URL" -o "$CLI_DIR/xmrt-node"; then
    chmod +x "$CLI_DIR/xmrt-node"
    echo -e "${G}[+]${N} CLI installed to $CLI_DIR/xmrt-node"
else
    echo -e "${R}[X]${N} Failed to download CLI. Check connectivity."
    exit 1
fi

# ── Step 5: Add to PATH ────────────────────────────────────────────────────
SHELL_RC="$HOME/.bashrc"
if ! grep -q "local/bin" "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    echo -e "${G}[+]${N} Added ~/.local/bin to PATH in $SHELL_RC"
fi

# ── Step 6: Install XMRig ──────────────────────────────────────────────────
echo -e "${C}[*]${N} Installing XMRig mining engine..."
"$CLI_DIR/xmrt-node" install 2>&1 || true

# ── Done ────────────────────────────────────────────────────────────────────
echo
echo -e "${G}╔══════════════════════════════════════════════╗${N}"
echo -e "${G}║       Installation Complete! 🎉              ║${N}"
echo -e "${G}╚══════════════════════════════════════════════╝${N}"
echo
echo -e "  ${C}Usage:${N}"
echo -e "  xmrt-node status    — Check node health"
echo -e "  xmrt-node start     — Start mining"
echo -e "  xmrt-node stop      — Stop mining"
echo -e "  xmrt-node peers     — View fleet"
echo
echo -e "  ${Y}Quick start:${N}"
echo -e "  source ~/.bashrc && xmrt-node start"
echo
echo -e "  ${C}Relay:${N} https://relay.mobilemonero.com"
echo -e "  ${C}Fleet:${N} https://xmrtdao.github.io"
echo
