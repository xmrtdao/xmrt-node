"""XMRT Agent — local on-device AI agent for xmrt-node.

Exposes an OpenAI-compatible HTTP API on 127.0.0.1:8642 so the Flutter app
can talk to it the same way it talks to any LLM provider.

Architecture (mirrors hermes-desktop's 3-process model):
    Flutter UI  ->  Kotlin orchestrator  ->  THIS (Python)  ->  Ollama / Kimi / OpenRouter

Default model: deepseek-v4-flash:cloud (served by Ollama via ollama.com OAuth).
Fallback: qwen3-coder:480b-cloud, Kimi, OpenRouter.

Public surface (all OpenAI-compatible):
    GET  /health
    GET  /v1/models
    POST /v1/chat/completions        (streaming + non-streaming)
    GET  /v1/sessions
    GET  /v1/sessions/{id}/messages
    POST /v1/sessions
    DELETE /v1/sessions/{id}
    GET  /v1/profiles
    POST /v1/profiles
    GET  /v1/memory
    POST /v1/memory
    GET  /v1/soul
    POST /v1/soul
    GET  /v1/skills
    GET  /v1/skills/{name}
    POST /v1/skills/install
    GET  /v1/cron
    POST /v1/cron
    DELETE /v1/cron/{id}
"""

__version__ = "0.1.0"
