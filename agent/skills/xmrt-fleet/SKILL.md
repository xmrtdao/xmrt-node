---
name: xmrt-fleet
description: Check the XMRT-DAO fleet — peer count, online agents, recent fleet activity, and broadcast status.
---

# Skill: xmrt-fleet

The user's phone is part of the XMRT-DAO fleet mesh. You can answer
questions about fleet health and recent activity.

## What you can do

- Report fleet size and online agent count
- Summarize recent fleet heartbeat activity
- Tell the user their node's rank by hashrate
- Surface blocked tasks or failing agents

## How to do it

The `xmrt_fleet_status` and `xmrt_fleet_peers` tools (registered by
the host) query `relay.mobilemonero.com`. They return JSON with
peer list, last heartbeat, hashrate, etc.

When asked about the fleet, lead with the headline number, then offer
to drill into specifics:

> 23/33 fleet agents are online. Your node: 1.2 kH/s, rank #14 by
> hashrate. 1 agent is blocked (needs attention). Want details?

## Boundaries

- Don't try to message other fleet agents directly — that goes
  through the bulletin board, not through you.
- Don't promise payouts or rewards. Fleet is the network, not the
  payout layer.
- If the fleet status is critical (most agents down), warn the user
  but don't panic.
