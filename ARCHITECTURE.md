# XMRT Node Architecture

**One codebase. Three deployment targets. Zero compromise.**

| Target | Platform | Form Factor |
|--------|----------|-------------|
| Play Store App | Android (Flutter) | Phone / Tablet |
| XMRT Charger | Android Things / Custom ROM | Wall-powered mining station |
| XMRT Stick | Android TV dongle | Plug-and-play node |

## Architecture

```
┌──────────────────────────────────────────┐
│           Flutter UI Layer              │
│  Dashboard · Mining · Agent · Settings  │
├──────────────────────────────────────────┤
│        Dart Service Layer               │
│  MiningService  HermesAgent  Heartbeat  │
├──────────────────┬───────────────────────┤
│  Platform Channel │   HTTP / WebSocket   │
├──────────────────┼───────────────────────┤
│  XMRig (.so)     │  Ollama Cloud API    │
│  (ARM64 native)  │  (AI orchestration)  │
├──────────────────┴───────────────────────┤
│     Android Foreground Service          │
│  (Persistent background node)           │
└──────────────────────────────────────────┘
```

## Three Layers

**1. UI Layer (Flutter/Dart)** — Dashboard with live hashrate, pool stats, worker status. Mining console with start/stop/threads. Agent chat via Ollama cloud. Settings for wallet, worker, pool.

**2. Service Layer (Dart)** — `MiningService` bridges to XMRig native lib. `HermesAgent` calls Ollama cloud models. `FleetHeartbeat` registers node with relay.mobilemonero.com.

**3. Native Layer (Kotlin/JNI)** — `MiningService.java` foreground service. `XMRigBridge.java` JNI to compiled ARM64 .so. XMRig built via CMake + NDK.

## Components

- **XMRig .so** — Compiled for arm64-v8a. Config passed via JNI. Hashrate/shares returned via callback. Local API on :19090.
- **Foreground Service** — Persistent notification. Survives backgrounding. Auto-restart via WorkManager.
- **Fleet Heartbeat** — POST to relay every 60s: `{agent_id, status, hashrate, wallet, worker}`.
- **Hermes Agent** — Ollama cloud API for AI. Falls back to basic commands offline.

## Play Store Strategy

- **Name:** XMRT Node — AI Fleet Orchestrator
- **Category:** Tools > Network Monitoring
- **Pitch:** "AI-orchestrated network monitoring node" — mining is a background compute feature
- XMRig compiled from source (different hash from known miner binaries)
- No "crypto mining" language in store listing

## Build

```bash
git clone --recurse-submodules https://github.com/xmrtdao/xmrt-node.git
cd android/xmrig && ./build-android.sh arm64
cd ../.. && flutter build apk --release
```

## Roadmap

| Phase | Milestone | Target |
|-------|-----------|--------|
| 1 | Repo + architecture doc | Now |
| 2 | Flutter scaffold + navigation | Week 1 |
| 3 | XMRig ARM64 native build | Week 2 |
| 4 | Foreground service + mining control | Week 3 |
| 5 | Fleet heartbeat + dashboard reg | Week 4 |
| 6 | Hermes agent + Ollama integration | Week 5 |
| 7 | Play Store submission | Week 6 |
| 8 | XMRT Charger prototype | Week 8 |
