"""LLM provider layer.

Sends chat completion requests to:
  - Ollama native API (/api/chat) for Ollama-served models
  - OpenAI-compatible API (/v1/chat/completions) for Kimi, OpenRouter, etc.

Returns an async iterator of normalized events:
  {"type": "content", "text": "..."}
  {"type": "thinking", "text": "..."}
  {"type": "tool_call", "id": "...", "name": "...", "arguments": {...}}
  {"type": "usage", "prompt_tokens": N, "completion_tokens": M, "total_tokens": T}
  {"type": "done"}
  {"type": "error", "message": "..."}

This abstracts away the difference between Ollama's ndjson streaming and
OpenAI's SSE streaming, so the rest of the agent doesn't care.
"""

import json
import logging
from dataclasses import dataclass
from typing import AsyncIterator, Dict, List, Optional, Any

import httpx

from .config import Provider

logger = logging.getLogger("xmrt-agent.llm")


@dataclass
class ChatMessage:
    """One message in a conversation."""
    role: str  # "system" | "user" | "assistant" | "tool"
    content: Optional[str] = None
    name: Optional[str] = None  # for tool messages
    tool_calls: Optional[List[Dict[str, Any]]] = None
    tool_call_id: Optional[str] = None
    thinking: Optional[str] = None  # for thinking-capable models

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to a dict for the API. Drop None fields."""
        d: Dict[str, Any] = {"role": self.role}
        if self.content is not None:
            d["content"] = self.content
        if self.name is not None:
            d["name"] = self.name
        if self.tool_calls is not None:
            d["tool_calls"] = self.tool_calls
        if self.tool_call_id is not None:
            d["tool_call_id"] = self.tool_call_id
        if self.thinking is not None:
            d["thinking"] = self.thinking
        return d


class LLMError(Exception):
    """Raised when the LLM provider returns an error."""
    pass


def _build_ollama_payload(messages: List[ChatMessage], model: str, stream: bool, tools: Optional[List[dict]] = None) -> dict:
    """Build payload for Ollama's /api/chat endpoint."""
    payload: Dict[str, Any] = {
        "model": model,
        "messages": [m.to_dict() for m in messages],
        "stream": stream,
    }
    if tools:
        payload["tools"] = tools
    return payload


def _build_openai_payload(messages: List[ChatMessage], model: str, stream: bool, tools: Optional[List[dict]] = None) -> dict:
    """Build payload for OpenAI-compatible /v1/chat/completions endpoint."""
    payload: Dict[str, Any] = {
        "model": model,
        "messages": [m.to_dict() for m in messages],
        "stream": stream,
    }
    if tools:
        # OpenAI uses {"type": "function", "function": {...}}; Ollama uses the same shape now
        payload["tools"] = tools
    return payload


async def stream_chat(
    provider: Provider,
    messages: List[ChatMessage],
    tools: Optional[List[dict]] = None,
    timeout: float = 120.0,
) -> AsyncIterator[dict]:
    """Stream a chat completion from the given provider.

    Yields normalized events (see module docstring).
    """
    if provider.is_ollama:
        async for event in _stream_ollama(provider, messages, tools, timeout):
            yield event
    else:
        async for event in _stream_openai(provider, messages, tools, timeout):
            yield event


async def _stream_ollama(
    provider: Provider,
    messages: List[ChatMessage],
    tools: Optional[List[dict]],
    timeout: float,
) -> AsyncIterator[dict]:
    """Stream from Ollama's native /api/chat endpoint (ndjson)."""
    url = f"{provider.base_url}/api/chat"
    payload = _build_ollama_payload(messages, provider.model, stream=True, tools=tools)

    headers = {"Content-Type": "application/json"}
    # Ollama OAuth is handled by the local daemon via ollama signin
    # We don't need to send an API key for *:cloud models

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream("POST", url, json=payload, headers=headers) as response:
                if response.status_code != 200:
                    body = await response.aread()
                    raise LLMError(f"Ollama returned {response.status_code}: {body.decode('utf-8', errors='replace')[:500]}")

                buffer = ""
                async for chunk in response.aiter_text():
                    buffer += chunk
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except json.JSONDecodeError:
                            logger.warning("Ollama sent invalid JSON: %r", line[:200])
                            continue

                        if "error" in obj:
                            yield {"type": "error", "message": obj["error"]}
                            return

                        msg = obj.get("message", {})

                        # Thinking / reasoning content (DeepSeek, Qwen, etc.)
                        thinking = msg.get("thinking")
                        if thinking:
                            yield {"type": "thinking", "text": thinking}

                        # Regular content
                        content = msg.get("content")
                        if content:
                            yield {"type": "content", "text": content}

                        # Tool calls (Ollama format)
                        tool_calls = msg.get("tool_calls")
                        if tool_calls:
                            for tc in tool_calls:
                                # Ollama tool calls: {"function": {"name": "...", "arguments": {...}}}
                                fn = tc.get("function", {})
                                name = fn.get("name", "")
                                args = fn.get("arguments", {})
                                if isinstance(args, str):
                                    try:
                                        args = json.loads(args)
                                    except json.JSONDecodeError:
                                        args = {"_raw": args}
                                yield {
                                    "type": "tool_call",
                                    "id": tc.get("id", f"call_{name}"),
                                    "name": name,
                                    "arguments": args,
                                }

                        # Usage stats (Ollama emits in final chunk)
                        if obj.get("done"):
                            usage = {
                                "prompt_tokens": obj.get("prompt_eval_count", 0),
                                "completion_tokens": obj.get("eval_count", 0),
                                "total_tokens": (obj.get("prompt_eval_count", 0) + obj.get("eval_count", 0)),
                            }
                            yield {"type": "usage", **usage}
                            yield {"type": "done"}
                            return

    except httpx.ConnectError as e:
        raise LLMError(f"Cannot connect to Ollama at {url}: {e}")
    except httpx.TimeoutException:
        raise LLMError(f"Ollama request timed out after {timeout}s")


async def _stream_openai(
    provider: Provider,
    messages: List[ChatMessage],
    tools: Optional[List[dict]],
    timeout: float,
) -> AsyncIterator[dict]:
    """Stream from an OpenAI-compatible /v1/chat/completions endpoint (SSE)."""
    url = f"{provider.base_url}/v1/chat/completions"
    payload = _build_openai_payload(messages, provider.model, stream=True, tools=tools)

    headers = {"Content-Type": "application/json"}
    if provider.api_key:
        headers["Authorization"] = f"Bearer {provider.api_key}"

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream("POST", url, json=payload, headers=headers) as response:
                if response.status_code != 200:
                    body = await response.aread()
                    raise LLMError(f"{provider.name} returned {response.status_code}: {body.decode('utf-8', errors='replace')[:500]}")

                buffer = ""
                async for chunk in response.aiter_text():
                    buffer += chunk
                    # SSE blocks separated by \n\n
                    while "\n\n" in buffer:
                        block, buffer = buffer.split("\n\n", 1)
                        for line in block.split("\n"):
                            line = line.strip()
                            if line.startswith("data:"):
                                data = line[5:].strip()
                                if data == "[DONE]":
                                    yield {"type": "done"}
                                    return
                                try:
                                    obj = json.loads(data)
                                except json.JSONDecodeError:
                                    continue
                                # Standard OpenAI streaming chunk
                                choices = obj.get("choices", [])
                                if not choices:
                                    continue
                                delta = choices[0].get("delta", {})

                                # Reasoning content (some OpenRouter routes)
                                if "reasoning_content" in delta:
                                    yield {"type": "thinking", "text": delta["reasoning_content"]}
                                elif "reasoning" in delta:
                                    yield {"type": "thinking", "text": delta["reasoning"]}

                                if "content" in delta and delta["content"]:
                                    yield {"type": "content", "text": delta["content"]}

                                if "tool_calls" in delta:
                                    for tc in delta["tool_calls"]:
                                        # OpenAI tool calls stream incrementally — accumulate by index
                                        # For simplicity, we emit one event per chunk; the caller buffers
                                        fn = tc.get("function", {})
                                        name = fn.get("name", "")
                                        args_str = fn.get("arguments", "")
                                        # Try to parse, but if incomplete, wrap as raw
                                        args: Any = args_str
                                        if isinstance(args_str, str) and args_str:
                                            try:
                                                args = json.loads(args_str)
                                            except json.JSONDecodeError:
                                                # Partial JSON; keep as string for now
                                                args = {"_partial": args_str}
                                        yield {
                                            "type": "tool_call",
                                            "id": tc.get("id", ""),
                                            "name": name,
                                            "arguments": args,
                                        }

                                # Usage stats (if stream_options.include_usage is set)
                                if "usage" in obj and obj["usage"]:
                                    u = obj["usage"]
                                    yield {
                                        "type": "usage",
                                        "prompt_tokens": u.get("prompt_tokens", 0),
                                        "completion_tokens": u.get("completion_tokens", 0),
                                        "total_tokens": u.get("total_tokens", 0),
                                    }

    except httpx.ConnectError as e:
        raise LLMError(f"Cannot connect to {provider.name} at {url}: {e}")
    except httpx.TimeoutException:
        raise LLMError(f"{provider.name} request timed out after {timeout}s")


async def chat(
    provider: Provider,
    messages: List[ChatMessage],
    tools: Optional[List[dict]] = None,
    timeout: float = 120.0,
) -> dict:
    """Non-streaming chat. Returns the full assistant message as a dict.

    Useful for non-streaming endpoints or for callers that don't need SSE.
    """
    content = ""
    thinking = ""
    tool_calls: List[Dict[str, Any]] = []
    usage: Dict[str, int] = {}

    async for event in stream_chat(provider, messages, tools, timeout):
        if event["type"] == "content":
            content += event["text"]
        elif event["type"] == "thinking":
            thinking += event["text"]
        elif event["type"] == "tool_call":
            tool_calls.append({
                "id": event["id"],
                "type": "function",
                "function": {
                    "name": event["name"],
                    "arguments": json.dumps(event["arguments"]) if not isinstance(event["arguments"], str) else event["arguments"],
                },
            })
        elif event["type"] == "usage":
            usage = {k: v for k, v in event.items() if k != "type"}
        elif event["type"] == "error":
            raise LLMError(event["message"])

    msg: Dict[str, Any] = {"role": "assistant", "content": content}
    if thinking:
        msg["thinking"] = thinking
    if tool_calls:
        msg["tool_calls"] = tool_calls
    if usage:
        msg["usage"] = usage
    return msg
