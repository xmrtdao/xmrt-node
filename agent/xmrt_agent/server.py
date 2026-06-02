"""HTTP server for XMRT Agent.

Exposes OpenAI-compatible endpoints plus our own management routes.
All routes bind to 127.0.0.1 only — this is a local agent, not a public API.
"""

import asyncio
import json
import logging
import time
import uuid
from pathlib import Path
from typing import Any, Dict

from aiohttp import web

from . import __version__
from .agent import run_agent_loop
from .config import Config
from .llm import ChatMessage
from .memory import (
    append_entry,
    ensure_defaults,
    read_file,
    write_file,
)
from .sessions import SessionStore
from .skills import Skill, discover_skills
from .tools import ToolRegistry

logger = logging.getLogger("xmrt-agent.server")


# ──────────────────────────────────────────────────────────────────────
# CORS — allow the local Flutter app to call us
# ──────────────────────────────────────────────────────────────────────

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",  # local-only anyway
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Session-Id",
}


def _cors_preflight():
    """Return a preflight response."""
    return web.Response(status=204, headers=CORS_HEADERS)


def _cors_wrap(resp: web.StreamResponse) -> web.StreamResponse:
    """Add CORS headers to a response."""
    for k, v in CORS_HEADERS.items():
        resp.headers[k] = v
    return resp


# ──────────────────────────────────────────────────────────────────────
# App state
# ──────────────────────────────────────────────────────────────────────


class AppState:
    """Shared state for all routes."""
    def __init__(self, config: Config, home: Path):
        self.config = config
        self.home = home
        self.sessions = SessionStore(home / "state.db")
        self.tools = ToolRegistry(config)
        self.skills: list = []  # loaded later

    def reload_skills(self) -> None:
        self.skills = discover_skills(self.config.skills_dirs)
        logger.info("Reloaded %d skills", len(self.skills))


# ──────────────────────────────────────────────────────────────────────
# Health + models
# ──────────────────────────────────────────────────────────────────────


async def handle_health(request: web.Request) -> web.Response:
    """GET /health — simple liveness probe."""
    state: AppState = request.app["state"]
    return web.json_response({
        "status": "ok",
        "version": __version__,
        "providers": [
            {"name": p.name, "model": p.model, "base_url": p.base_url, "is_ollama": p.is_ollama}
            for p in state.config.all_providers
        ],
        "tools": list(state.tools.tools.keys()),
        "skills": [s.name for s in state.skills],
        "sessions_dir": str(state.home / "state.db"),
    }, headers=CORS_HEADERS)


async def handle_list_models(request: web.Request) -> web.Response:
    """GET /v1/models — OpenAI-compatible model list (for compatibility)."""
    state: AppState = request.app["state"]
    models = []
    for p in state.config.all_providers:
        models.append({
            "id": p.model,
            "object": "model",
            "created": int(time.time()),
            "owned_by": p.name,
        })
    return web.json_response({"object": "list", "data": models}, headers=CORS_HEADERS)


# ──────────────────────────────────────────────────────────────────────
# Chat completions (OpenAI-compatible)
# ──────────────────────────────────────────────────────────────────────


async def handle_chat_completions(request: web.Request) -> web.StreamResponse:
    """POST /v1/chat/completions — the main chat endpoint.

    Supports both streaming (SSE) and non-streaming modes.
    """
    state: AppState = request.app["state"]

    try:
        body = await request.json()
    except json.JSONDecodeError:
        return web.json_response(
            {"error": {"message": "Invalid JSON", "type": "invalid_request_error"}},
            status=400, headers=CORS_HEADERS,
        )

    # Extract fields (OpenAI format)
    raw_messages = body.get("messages", [])
    stream = body.get("stream", True)
    model_name = body.get("model", state.config.provider.primary.model)
    session_id = request.headers.get("X-Session-Id") or body.get("session_id") or f"chat-{int(time.time()*1000)}"

    # Convert messages to ChatMessage
    messages = _parse_messages(raw_messages)
    if not messages:
        return web.json_response(
            {"error": {"message": "messages must not be empty", "type": "invalid_request_error"}},
            status=400, headers=CORS_HEADERS,
        )

    # Ensure session exists in DB
    session = state.sessions.get_session(session_id)
    if session is None:
        session = state.sessions.create_session(
            source="openai-compat",
            model=model_name,
            session_id=session_id,
        )

    # Persist the user message
    last_user = next((m for m in reversed(messages) if m.role == "user"), None)
    if last_user and last_user.content:
        state.sessions.add_message(session_id, "user", last_user.content)

    if stream:
        return await _stream_chat_response(state, messages, model_name, session_id, request)
    else:
        return await _non_streaming_chat_response(state, messages, model_name, session_id, request)


def _parse_messages(raw_messages: list) -> list:
    """Convert OpenAI message dicts to ChatMessage objects."""
    out = []
    for m in raw_messages:
        role = m.get("role", "user")
        content = m.get("content")
        if content is None and role == "user":
            content = ""
        # Handle multimodal content arrays (we only take text for now)
        if isinstance(content, list):
            text_parts = [p.get("text", "") for p in content if p.get("type") == "text"]
            content = "\n".join(text_parts) if text_parts else ""
        out.append(ChatMessage(
            role=role,
            content=content,
            name=m.get("name"),
            tool_calls=m.get("tool_calls"),
            tool_call_id=m.get("tool_call_id"),
            thinking=m.get("thinking"),
        ))
    return out


async def _stream_chat_response(
    state: AppState,
    messages: list,
    model_name: str,
    session_id: str,
    request: web.Request,
) -> web.StreamResponse:
    """Stream SSE chunks back to the client (OpenAI format)."""
    response = web.StreamResponse(
        status=200,
        headers={
            **CORS_HEADERS,
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
    await response.prepare(request)

    # Build a unique completion ID for OpenAI compat
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:24]}"
    created = int(time.time())

    # We need to accumulate the final assistant message for session storage
    accumulated_content = ""
    accumulated_thinking = ""
    accumulated_tool_calls = []

    async def emit_sse(data: dict) -> None:
        """Write one SSE chunk to the stream."""
        try:
            chunk = f"data: {json.dumps(data)}\n\n"
            await response.write(chunk.encode("utf-8"))
        except (ConnectionResetError, asyncio.CancelledError):
            raise

    # Send the role chunk first (OpenAI streaming convention)
    await emit_sse({
        "id": completion_id,
        "object": "chat.completion.chunk",
        "created": created,
        "model": model_name,
        "choices": [{
            "index": 0,
            "delta": {"role": "assistant", "content": ""},
            "finish_reason": None,
        }],
    })

    # Run the agent loop
    try:
        async for event in run_agent_loop(
            state.config, state.tools, messages, state.skills, state.home, session_id,
        ):
            etype = event["type"]

            if etype == "content":
                accumulated_content += event["text"]
                await emit_sse({
                    "id": completion_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "delta": {"content": event["text"]},
                        "finish_reason": None,
                    }],
                })

            elif etype == "thinking":
                accumulated_thinking += event["text"]
                # Forward thinking as reasoning_content (matches DeepSeek/OpenRouter)
                await emit_sse({
                    "id": completion_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "delta": {"reasoning_content": event["text"]},
                        "finish_reason": None,
                    }],
                })

            elif etype == "tool_call":
                # Forward to the client; we use a custom event so the UI can render the tool card
                await emit_sse({
                    "id": completion_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "delta": {
                            "tool_calls": [{
                                "index": len(accumulated_tool_calls),
                                "id": event.get("id", ""),
                                "type": "function",
                                "function": {
                                    "name": event.get("name", ""),
                                    "arguments": json.dumps(event.get("arguments", {})),
                                },
                            }],
                        },
                        "finish_reason": None,
                    }],
                })
                accumulated_tool_calls.append(event)

            elif etype == "tool_result":
                # Custom event for tool result (not standard OpenAI but useful for UIs)
                await emit_sse({
                    "id": completion_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "delta": {},
                        "finish_reason": None,
                    }],
                    "xmrt_tool_result": {
                        "id": event.get("id", ""),
                        "name": event.get("name", ""),
                        "result": event.get("result", {}),
                    },
                })

            elif etype == "usage":
                await emit_sse({
                    "id": completion_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "delta": {},
                        "finish_reason": None,
                    }],
                    "usage": {
                        "prompt_tokens": event.get("prompt_tokens", 0),
                        "completion_tokens": event.get("completion_tokens", 0),
                        "total_tokens": event.get("total_tokens", 0),
                    },
                })

            elif etype == "error":
                # Emit an error and stop
                await emit_sse({
                    "error": {"message": event.get("message", "unknown error"), "type": "server_error"},
                })
                # Persist what we got before the error
                if accumulated_content:
                    state.sessions.add_message(
                        session_id, "assistant", accumulated_content,
                        tool_calls=accumulated_tool_calls or None,
                        thinking=accumulated_thinking or None,
                    )
                state.sessions.end_session(session_id)
                await response.write(b"data: [DONE]\n\n")
                await response.write_eof()
                return

            elif etype == "done":
                # Final chunk with finish_reason
                await emit_sse({
                    "id": completion_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "delta": {},
                        "finish_reason": "stop",
                    }],
                })
                # Persist the assistant message
                state.sessions.add_message(
                    session_id, "assistant", accumulated_content,
                    tool_calls=accumulated_tool_calls or None,
                    thinking=accumulated_thinking or None,
                )
                state.sessions.end_session(session_id)
                await response.write(b"data: [DONE]\n\n")
                await response.write_eof()
                return

    except (ConnectionResetError, asyncio.CancelledError):
        # Client disconnected mid-stream — save what we have
        if accumulated_content:
            state.sessions.add_message(
                session_id, "assistant", accumulated_content,
                tool_calls=accumulated_tool_calls or None,
                thinking=accumulated_thinking or None,
            )
        state.sessions.end_session(session_id)
        logger.info("Client disconnected mid-stream from session %s", session_id)
        return

    # If we exit the loop without a "done" event, still close cleanly
    await response.write(b"data: [DONE]\n\n")
    await response.write_eof()
    return response


async def _non_streaming_chat_response(
    state: AppState,
    messages: list,
    model_name: str,
    session_id: str,
    request: web.Request,
) -> web.Response:
    """Return a single JSON response (OpenAI non-streaming format)."""
    accumulated_content = ""
    accumulated_thinking = ""
    accumulated_tool_calls = []

    async for event in run_agent_loop(
        state.config, state.tools, messages, state.skills, state.home, session_id,
    ):
        if event["type"] == "content":
            accumulated_content += event["text"]
        elif event["type"] == "thinking":
            accumulated_thinking += event["text"]
        elif event["type"] == "tool_call":
            accumulated_tool_calls.append(event)
        elif event["type"] == "error":
            return web.json_response(
                {"error": {"message": event.get("message"), "type": "server_error"}},
                status=500, headers=CORS_HEADERS,
            )

    # Persist
    state.sessions.add_message(
        session_id, "assistant", accumulated_content,
        tool_calls=accumulated_tool_calls or None,
        thinking=accumulated_thinking or None,
    )
    state.sessions.end_session(session_id)

    return web.json_response({
        "id": f"chatcmpl-{uuid.uuid4().hex[:24]}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model_name,
        "choices": [{
            "index": 0,
            "message": {
                "role": "assistant",
                "content": accumulated_content,
                **({"reasoning_content": accumulated_thinking} if accumulated_thinking else {}),
            },
            "finish_reason": "stop",
        }],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }, headers=CORS_HEADERS)


# ──────────────────────────────────────────────────────────────────────
# Sessions
# ──────────────────────────────────────────────────────────────────────


async def handle_list_sessions(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    limit = int(request.query.get("limit", "50"))
    offset = int(request.query.get("offset", "0"))
    sessions = state.sessions.list_sessions(limit=limit, offset=offset)
    return web.json_response({
        "sessions": [_session_to_dict(s) for s in sessions],
        "limit": limit,
        "offset": offset,
    }, headers=CORS_HEADERS)


async def handle_get_session(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    sid = request.match_info["session_id"]
    session = state.sessions.get_session(sid)
    if not session:
        return web.json_response({"error": "not found"}, status=404, headers=CORS_HEADERS)
    messages = state.sessions.get_messages(sid)
    return web.json_response({
        **_session_to_dict(session),
        "messages": [_message_to_dict(m) for m in messages],
    }, headers=CORS_HEADERS)


async def handle_delete_session(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    sid = request.match_info["session_id"]
    deleted = state.sessions.delete_session(sid)
    return web.json_response({"deleted": deleted}, headers=CORS_HEADERS)


async def handle_create_session(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    body = {}
    if request.content_type == "application/json":
        try:
            body = await request.json()
        except json.JSONDecodeError:
            pass
    session = state.sessions.create_session(
        source=body.get("source", "xmrt-node"),
        model=body.get("model", state.config.provider.primary.model),
        title=body.get("title", ""),
    )
    return web.json_response(_session_to_dict(session), status=201, headers=CORS_HEADERS)


async def handle_search_sessions(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    q = request.query.get("q", "")
    limit = int(request.query.get("limit", "20"))
    sessions = state.sessions.search_sessions(q, limit=limit)
    return web.json_response({
        "query": q,
        "sessions": [_session_to_dict(s) for s in sessions],
    }, headers=CORS_HEADERS)


def _session_to_dict(s) -> dict:
    return {
        "id": s.id,
        "title": s.title,
        "source": s.source,
        "started_at": s.started_at,
        "ended_at": s.ended_at,
        "message_count": s.message_count,
        "model": s.model,
        "preview": s.preview,
    }


def _message_to_dict(m) -> dict:
    return {
        "id": m.id,
        "role": m.role,
        "content": m.content,
        "timestamp": m.timestamp,
        "tool_calls": m.tool_calls,
        "tool_name": m.tool_name,
        "tool_call_id": m.tool_call_id,
        "thinking": m.thinking,
    }


# ──────────────────────────────────────────────────────────────────────
# Memory + Soul + User (read/write the .md files)
# ──────────────────────────────────────────────────────────────────────


async def handle_get_memory(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    memory = read_file(state.home, "MEMORY.md")
    return web.json_response({
        "content": memory.content,
        "exists": memory.exists,
        "last_modified": memory.last_modified,
    }, headers=CORS_HEADERS)


async def handle_post_memory(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    body = await request.json()
    action = body.get("action", "append")
    if action == "write":
        result = write_file(state.home, "MEMORY.md", body.get("content", ""))
    else:
        result = append_entry(state.home, "MEMORY.md", body.get("entry", ""))
    return web.json_response({
        "content": result.content,
        "exists": result.exists,
        "last_modified": result.last_modified,
    }, headers=CORS_HEADERS)


async def handle_get_soul(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    soul = read_file(state.home, "SOUL.md")
    return web.json_response({
        "content": soul.content,
        "exists": soul.exists,
        "last_modified": soul.last_modified,
    }, headers=CORS_HEADERS)


async def handle_post_soul(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    body = await request.json()
    result = write_file(state.home, "SOUL.md", body.get("content", ""))
    return web.json_response({
        "content": result.content,
        "exists": result.exists,
        "last_modified": result.last_modified,
    }, headers=CORS_HEADERS)


async def handle_get_user(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    user = read_file(state.home, "USER.md")
    return web.json_response({
        "content": user.content,
        "exists": user.exists,
        "last_modified": user.last_modified,
    }, headers=CORS_HEADERS)


async def handle_post_user(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    body = await request.json()
    result = write_file(state.home, "USER.md", body.get("content", ""))
    return web.json_response({
        "content": result.content,
        "exists": result.exists,
        "last_modified": result.last_modified,
    }, headers=CORS_HEADERS)


# ──────────────────────────────────────────────────────────────────────
# Skills
# ──────────────────────────────────────────────────────────────────────


async def handle_list_skills(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    return web.json_response({
        "skills": [
            {
                "name": s.name,
                "description": s.description,
                "path": str(s.path),
                "enabled": s.enabled,
            }
            for s in state.skills
        ],
    }, headers=CORS_HEADERS)


async def handle_get_skill(request: web.Request) -> web.Response:
    state: AppState = request.app["state"]
    name = request.match_info["name"]
    skill = next((s for s in state.skills if s.name == name), None)
    if not skill:
        return web.json_response({"error": "not found"}, status=404, headers=CORS_HEADERS)
    return web.json_response({
        "name": skill.name,
        "description": skill.description,
        "body": skill.body,
        "metadata": skill.metadata,
    }, headers=CORS_HEADERS)


async def handle_install_skill(request: web.Request) -> web.Response:
    """Install a skill from a local path."""
    state: AppState = request.app["state"]
    body = await request.json()
    src = Path(body.get("path", "")).expanduser()
    if not src.is_file() or src.name != "SKILL.md":
        return web.json_response({"error": "path must point to a SKILL.md file"}, status=400, headers=CORS_HEADERS)

    # Copy to the first skills dir
    if not state.config.skills_dirs:
        return web.json_response({"error": "no skills_dirs configured"}, status=500, headers=CORS_HEADERS)
    dest_dir = Path(state.config.skills_dirs[0]).expanduser() / src.parent.name
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / "SKILL.md"
    dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
    state.reload_skills()
    return web.json_response({"installed": dest.name, "path": str(dest)}, headers=CORS_HEADERS)


# ──────────────────────────────────────────────────────────────────────
# Cron (lightweight — uses the in-memory scheduler for now)
# ──────────────────────────────────────────────────────────────────────

# For Phase 1 we just stub cron. Real implementation comes later.
_cron_jobs: list = []


async def handle_list_cron(request: web.Request) -> web.Response:
    return web.json_response({"jobs": _cron_jobs}, headers=CORS_HEADERS)


async def handle_create_cron(request: web.Request) -> web.Response:
    body = await request.json()
    job = {
        "id": f"cron-{uuid.uuid4().hex[:8]}",
        "name": body.get("name", ""),
        "schedule": body.get("schedule", ""),
        "prompt": body.get("prompt", ""),
        "enabled": True,
    }
    _cron_jobs.append(job)
    return web.json_response(job, status=201, headers=CORS_HEADERS)


async def handle_delete_cron(request: web.Request) -> web.Response:
    jid = request.match_info["job_id"]
    global _cron_jobs
    _cron_jobs = [j for j in _cron_jobs if j["id"] != jid]
    return web.json_response({"deleted": True}, headers=CORS_HEADERS)


# ──────────────────────────────────────────────────────────────────────
# App factory
# ──────────────────────────────────────────────────────────────────────


def build_app(config: Config) -> web.Application:
    """Build the aiohttp application with all routes."""
    home = Path.home() / ".local" / "share" / "xmrt-agent"
    home.mkdir(parents=True, exist_ok=True)
    ensure_defaults(home)

    app = web.Application()
    state = AppState(config, home)
    state.reload_skills()
    app["state"] = state
    app["home"] = home

    # Health + models
    app.router.add_get("/health", handle_health)
    app.router.add_get("/v1/models", handle_list_models)

    # Ship default skills to the home dir on first run
    _seed_default_skills(home)
    state.reload_skills()

    # Chat (the money endpoint)
    app.router.add_post("/v1/chat/completions", handle_chat_completions)

    # Sessions
    app.router.add_get("/v1/sessions", handle_list_sessions)
    app.router.add_post("/v1/sessions", handle_create_session)
    app.router.add_get("/v1/sessions/search", handle_search_sessions)
    app.router.add_get("/v1/sessions/{session_id}", handle_get_session)
    app.router.add_delete("/v1/sessions/{session_id}", handle_delete_session)

    # Memory + Soul + User
    app.router.add_get("/v1/memory", handle_get_memory)
    app.router.add_post("/v1/memory", handle_post_memory)
    app.router.add_get("/v1/soul", handle_get_soul)
    app.router.add_post("/v1/soul", handle_post_soul)
    app.router.add_get("/v1/user", handle_get_user)
    app.router.add_post("/v1/user", handle_post_user)

    # Skills
    app.router.add_get("/v1/skills", handle_list_skills)
    app.router.add_get("/v1/skills/{name}", handle_get_skill)
    app.router.add_post("/v1/skills/install", handle_install_skill)

    # Cron
    app.router.add_get("/v1/cron", handle_list_cron)
    app.router.add_post("/v1/cron", handle_create_cron)
    app.router.add_delete("/v1/cron/{job_id}", handle_delete_cron)

    # CORS preflight for all routes
    async def options_handler(request: web.Request) -> web.Response:
        return _cors_preflight()
    app.router.add_route("OPTIONS", "/{path:.*}", options_handler)

    return app


def _seed_default_skills(home: Path) -> None:
    """Copy the pre-shipped skills from the agent package into <home>/skills/ on first run."""
    import shutil
    skills_dest = home / "skills"
    if skills_dest.exists() and any(skills_dest.iterdir()):
        return  # already seeded
    # Find the bundled skills dir.
    # Layout: agent/xmrt_agent/server.py
    #         agent/skills/<name>/SKILL.md
    # So the bundled dir is at agent/skills/, two levels up from server.py then into "skills"
    bundled = Path(__file__).resolve().parent.parent / "skills"
    if not bundled.is_dir():
        logger.warning("Bundled skills dir not found at %s", bundled)
        return
    skills_dest.mkdir(parents=True, exist_ok=True)
    for skill_dir in bundled.iterdir():
        if skill_dir.is_dir() and (skill_dir / "SKILL.md").is_file():
            dest = skills_dest / skill_dir.name
            if dest.exists():
                continue
            shutil.copytree(skill_dir, dest)
            logger.info("Seeded default skill: %s", skill_dir.name)
