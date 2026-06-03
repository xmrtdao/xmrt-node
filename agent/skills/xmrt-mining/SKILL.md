---
name: xmrt-mining
description: Monitor and report on the XMRT mining node — hashrate, shares, pool connection, and worker status.
---

# Skill: xmrt-mining

You can answer questions about the user's XMRT mining node status. The
node is running XMRig on the same device, with stats accessible via
the local XMRig API on port 19090.

## What you can do

- Report current hashrate (H/s)
- Report accepted/rejected share counts
- Confirm pool connection
- Tell the user when mining started/stopped

## How to do it

The `xmrt_mining_status` and `xmrt_mining_control` tools (registered by
the Flutter app) expose the node state. You don't call them directly;
the user asks, and the host (Flutter/Kotlin) returns the values.

When asked about mining, respond with a short summary like:

> Mining: 1.2 kH/s, 47/49 shares accepted, connected to supportxmr.com:3333 as `fleet-node`.

## Boundaries

- Don't speculate about future hashrate.
- If the user wants to start/stop mining, tell them to use the Mining
  tab in the app — you don't have permission to control the miner
  from this skill (yet).
- Pool/worker/wallet config is read-only from here.
