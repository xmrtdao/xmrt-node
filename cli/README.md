# XMRT-Node Android CLI

**Termux-compatible command-line mining node for Android.**

Part of the XMRT-DAO fleet ecosystem. Runs XMRig on your Android phone via Termux, connects to the pool, and reports to the fleet relay.

## Quick Install

```bash
# In Termux:
curl -fsSL https://raw.githubusercontent.com/xmrtdao/xmrt-node/main/cli/install-termux.sh | bash

# Reload PATH, then start mining:
source ~/.bashrc
xmrt-node start
```

## Commands

| Command | Description |
|---------|-------------|
| `xmrt-node install` | Install XMRig and dependencies |
| `xmrt-node start` | Start mining daemon |
| `xmrt-node stop` | Stop mining daemon |
| `xmrt-node status` | Show node health, hash rate, fleet status |
| `xmrt-node logs` | View recent miner logs |
| `xmrt-node peers` | List fleet agents on the relay |
| `xmrt-node config` | View/set config (`key=value`) |

## Configuration

Config file: `~/.config/xmrt-node/config.json`

```json
{
  "wallet": "46UxNFuGM2E3UwmZWWJicaRPoRwqwW4byQkaTHkX8yPcVihp91qAVtSFipWUGJJUyTXgzSqxzDQtNLf2bsp2DX2qCCgC5mg",
  "pool": "pool.mobilemonero.com:3333",
  "worker": "android-1234",
  "relay_url": "https://relay.mobilemonero.com",
  "max_cpu": 75,
  "auto_start": false
}
```

Change settings:
```bash
xmrt-node config worker=my-phone-01
xmrt-node config max_cpu=50
```

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
│  XMRT-Node   │────▶│  relay       │────▶│  Suite Dashboard │
│  CLI (Termux)│     │  mobilemonero│     │  (Fleet View)    │
│              │     │  .com:8080   │     │                  │
│  ┌─────────┐ │     └──────────────┘     └──────────────────┘
│  │ XMRig   │─┼──▶ pool.mobilemonero.com:3333
│  │ (miner) │ │     (SupportXMR pool)
│  └─────────┘ │
└──────────────┘
```

## Requirements

- Android 10+ with Termux from F-Droid
- 2GB+ RAM recommended
- WiFi recommended (mining uses data)
- Root NOT required

## Fleet Integration

Each node reports to `relay.mobilemonero.com` with:
- Worker name and wallet address
- Mining stats (hashrate, shares, uptime)
- Status (running/stopped)

View all fleet agents: `xmrt-node peers`

## Building from Source

```bash
git clone https://github.com/xmrtdao/xmrt-node.git
cd xmrt-node/cli
chmod +x xmrt-node
./xmrt-node install
```
