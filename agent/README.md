# XMRT Agent

On-device AI agent for the [XMRT-DAO mining node](https://github.com/xmrtdao/xmrt-node).
Runs as a Python service on Android (via Termux) or any Linux/macOS box. Exposes
an OpenAI-compatible HTTP API on `127.0.0.1:8642` so the Flutter app can talk to
it like any other LLM provider.

## What it does

- **OpenAI-compatible chat completions** (`/v1/chat/completions`) with SSE streaming
- **Tool use** via Ollama/OpenAI `tools` field — ReAct loop with auto-execution
- **Termux:API tools** — battery, location, camera, notifications, clipboard,
  torch, vibrate, WiFi info, volume, toast
- **Skills system** — `SKILL.md` files in `~/.local/share/xmrt-agent/skills/`
- **Memory + Soul + User** — three editable Markdown files
- **Sessions** — SQLite-backed chat history with full-text search
- **Provider fallback** — tries primary, then fallbacks in order

## Default model

`deepseek-v4-flash:cloud` served by Ollama via the `ollama signin` OAuth flow.
The agent never sees auth — it just talks to Ollama at `http://127.0.0.1:11434`.

Fallback chain:
1. `deepseek-v4-flash:cloud` (Ollama OAuth)
2. `qwen3-coder:480b-cloud` (alt Ollama cloud)
3. `kimi-for-coding` (Kimi API)
4. `deepseek/deepseek-v3.1` (OpenRouter)

All cloud. Local Ollama is opportunistic only — most 4-6 GB Android phones
can't run decent local models, so the floor is cloud.

## Install

```bash
# Python 3.11+ required
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Or as a package:
```bash
pip install -e .
```

## Run

```bash
# Default — listens on 127.0.0.1:8642
python -m xmrt_agent

# Or, if installed as a package
xmrt-agent

# Override home dir
XMRT_AGENT_HOME=/path/to/agent python -m xmrt_agent

# Custom port/host
XMRT_AGENT_HOST=0.0.0.0 XMRT_AGENT_PORT=9000 python -m xmrt_agent
```

## Configuration

The agent reads `~/.local/share/xmrt-agent/config.yaml`. If it doesn't exist,
a default is written. Edit it to change models, add fallbacks, or disable Termux
tools.

```yaml
name: XMRT Agent
provider:
  primary:
    name: ollama-cloud
    base_url: http://127.0.0.1:11434
    model: deepseek-v4-flash:cloud
    is_ollama: true
  fallbacks:
    - name: ollama-cloud-qwen-coder
      base_url: http://127.0.0.1:11434
      model: qwen3-coder:480b-cloud
      is_ollama: true
    - name: kimi
      base_url: https://api.kimi.com/coding/v1
      model: kimi-for-coding
      auth_env: KIMI_API_KEY
max_context_messages: 50
max_tool_iterations: 8
enable_termux_tools: true
```

API keys come from environment variables (e.g. `KIMI_API_KEY=...`). Don't put
keys in the YAML.

## HTTP API

### Health check
```bash
curl http://127.0.0.1:8642/health
```

### Chat completion (streaming, OpenAI-compatible)
```bash
curl -N http://127.0.0.1:8642/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Session-Id: my-session-1" \
  -d '{
    "model": "deepseek-v4-flash:cloud",
    "messages": [
      {"role": "user", "content": "What is my battery level?"}
    ],
    "stream": true
  }'
```

The agent will likely call the `battery_status` tool, get the result, and
stream the final answer.

### Non-streaming
Same request with `"stream": false` returns a complete JSON response.

### Sessions
```bash
# List sessions
curl http://127.0.0.1:8642/v1/sessions

# Get one session + messages
curl http://127.0.0.1:8642/v1/sessions/chat-1234567890

# Search
curl 'http://127.0.0.1:8642/v1/sessions/search?q=battery'

# Delete
curl -X DELETE http://127.0.0.1:8642/v1/sessions/chat-1234567890
```

### Memory / Soul / User
```bash
curl http://127.0.0.1:8642/v1/memory
curl -X POST http://127.0.0.1:8642/v1/memory \
  -H "Content-Type: application/json" \
  -d '{"action": "append", "entry": "User prefers Spanish responses."}'

curl http://127.0.0.1:8642/v1/soul
curl -X POST http://127.0.0.1:8642/v1/soul \
  -H "Content-Type: application/json" \
  -d '{"content": "# New SOUL\n\nYou are..."}'
```

### Skills
```bash
curl http://127.0.0.1:8642/v1/skills
curl http://127.0.0.1:8642/v1/skills/xmrt-mining
curl -X POST http://127.0.0.1:8642/v1/skills/install \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/SKILL.md"}'
```

## Skills format

A skill is a directory with a `SKILL.md` file:

```
skills/
  xmrt-mining/
    SKILL.md
```

`SKILL.md` format (matches hermes-agent / Claude Agent SDK):

```markdown
---
name: my-skill
description: One-line description shown to the LLM.
---

# Skill body

Detailed instructions for the LLM. Markdown. Explain when to use this
skill, what tools to call, and what responses to give.
```

Drop the directory into `~/.local/share/xmrt-agent/skills/` and restart the agent.
The skill is auto-injected into the system prompt.

## Tool system

Tools are Python functions exposed to the LLM via OpenAI/Ollama `tools` format.
Termux:API tools are auto-registered if `termux-api` is installed:

| Tool | Description |
|------|-------------|
| `battery_status` | Device battery level, temp, health |
| `get_location` | GPS or network location |
| `take_photo` | Camera capture |
| `show_notification` | System notification |
| `get_clipboard` / `set_clipboard` | Read/write system clipboard |
| `vibrate` | Vibrate the device |
| `toggle_flashlight` | Torch on/off |
| `get_wifi_info` | SSID, IP, signal |
| `set_volume` | Set audio stream volume |
| `show_toast` | Short popup message |

Custom tools can be added by editing `xmrt_agent/tools.py`.

## Architecture

```
┌────────────────────────────────────────────────────────┐
│  Flutter app (Android)                                  │
│  Chat screen → MethodChannel "io.xmrt.node/agent"      │
└────────────────────┬───────────────────────────────────┘
                     │ HTTP/SSE  (127.0.0.1:8642)
┌────────────────────▼───────────────────────────────────┐
│  xmrt-agent (this repo, runs in Termux)                 │
│  ┌──────────────────────────────────────────────────┐  │
│  │ aiohttp server.py                                │  │
│  │  → OpenAI-compatible /v1/chat/completions        │  │
│  │  → session/memory/soul/skills/cron routes        │  │
│  └──────────────────┬───────────────────────────────┘  │
│                     │                                   │
│  ┌──────────────────▼───────────────────────────────┐  │
│  │ agent.py — ReAct loop                            │  │
│  │  → LLM call → tool execution → loop until done   │  │
│  └──────┬─────────────────────────────────┬─────────┘  │
│         │                                 │            │
│  ┌──────▼────────┐                ┌───────▼─────────┐  │
│  │ tools.py      │                │ llm.py          │  │
│  │ Termux:API    │                │ Ollama / Kimi / │  │
│  │ + builtins    │                │ OpenRouter      │  │
│  └───────────────┘                └──────┬──────────┘  │
│                                         │             │
│         ┌───────────────────────────────┘             │
│         │ HTTP                                          │
│  ┌──────▼─────────┐  ┌──────────────────┐              │
│  │ Ollama local   │  │ Kimi / OpenRouter │              │
│  │ 127.0.0.1:11434│  │ cloud             │              │
│  │  → :cloud      │  │                   │              │
│  │    routes to   │  │                   │              │
│  │  ollama.com    │  │                   │              │
│  └────────────────┘  └──────────────────┘              │
└─────────────────────────────────────────────────────────┘
```

## Testing

```bash
# Start the agent
python -m xmrt_agent &

# Wait for it to come up
sleep 2

# Test health
curl http://127.0.0.1:8642/health

# Test chat (non-streaming)
curl -s http://127.0.0.1:8642/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-v4-flash:cloud",
    "messages": [{"role": "user", "content": "Say hello in Spanish."}],
    "stream": false
  }' | python -m json.tool

# Test a tool call (battery)
curl -N http://127.0.0.1:8642/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-v4-flash:cloud",
    "messages": [{"role": "user", "content": "What is my battery level?"}],
    "stream": true
  }'
```

## On Android (Termux)

The agent ships inside the xmrt-node APK. The Kotlin `AgentService` extracts
it to `~/.local/share/xmrt-agent/` on first launch and spawns it via
`Termux:Boot` or `RUN_COMMAND` intent.

```bash
# Manual run on phone
cd ~/.local/share/xmrt-agent
python3 -m xmrt_agent

# Or via the xmrt-node CLI
xmrt-node agent start
xmrt-node agent stop
xmrt-node agent status
```

## License

MIT
