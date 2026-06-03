"""ReAct agent loop.

The agent runs a Thought -> Action -> Observation loop:
  1. Build messages: [system, ...history, user]
  2. Call LLM with tools available
  3. If LLM returns tool_calls: execute them, append results, loop
  4. If LLM returns content (no tool calls): done, return final answer
  5. Cap at max_tool_iterations to prevent infinite loops

Yields normalized events for the HTTP layer to stream back.
"""

import json
import logging
import time
from typing import AsyncIterator, Dict, List, Optional

from .config import Config
from .llm import ChatMessage, LLMError, stream_chat
from .memory import read_file
from .skills import Skill, render_skills_as_prompt
from .tools import ToolRegistry

logger = logging.getLogger("xmrt-agent.agent")


def _build_system_prompt(
    config: Config,
    skills: List[Skill],
    memory_content: str,
    soul_content: str,
    user_content: str,
) -> str:
    """Assemble the full system prompt from base + soul + memory + skills."""
    parts: List[str] = []

    # Base system prompt
    base = (
        "You are XMRT Agent, the on-device AI for the XMRT-DAO mining ecosystem. "
        "You run inside the xmrt-node app on an Android phone. "
        "You can call tools to interact with the device (battery, location, camera, notifications, etc.). "
        "Be concise, direct, and helpful. Match the user's register."
    )
    parts.append(base)

    # Persona (SOUL.md)
    if soul_content.strip():
        parts.append(f"\n# Your Persona (SOUL.md)\n\n{soul_content.strip()}")

    # About the user (USER.md)
    if user_content.strip():
        parts.append(f"\n# About the User (USER.md)\n\n{user_content.strip()}")

    # Long-term memory (MEMORY.md)
    if memory_content.strip():
        parts.append(f"\n# Your Long-term Memory (MEMORY.md)\n\n{memory_content.strip()}")

    # Skills
    skills_section = render_skills_as_prompt(skills)
    if skills_section:
        parts.append(f"\n{skills_section}")

    return "\n\n---\n\n".join(parts)


async def run_agent_loop(
    config: Config,
    tool_registry: ToolRegistry,
    messages: List[ChatMessage],
    skills: List[Skill],
    home_dir,
    session_id: str,
) -> AsyncIterator[Dict]:
    """Run the ReAct loop, yielding normalized events.

    Events:
      {"type": "content", "text": "..."}      — streamed content from LLM
      {"type": "thinking", "text": "..."}     — reasoning/thinking tokens
      {"type": "tool_call", "name": "...", "arguments": {...}} — tool invocation
      {"type": "tool_result", "name": "...", "result": {...}}  — tool return
      {"type": "usage", ...}                    — token counts
      {"type": "done", "session_id": "..."}     — end of response
      {"type": "error", "message": "..."}      — error
    """
    # Build system prompt with current memory/soul/user/skills
    memory = read_file(home_dir, "MEMORY.md")
    soul = read_file(home_dir, "SOUL.md")
    user = read_file(home_dir, "USER.md")
    system_prompt = _build_system_prompt(
        config, skills, memory.content, soul.content, user.content,
    )

    # Prepend system message
    full_messages: List[ChatMessage] = [ChatMessage(role="system", content=system_prompt)]
    # Keep the last N messages to bound context
    history = messages[-config.max_context_messages:]
    full_messages.extend(history)

    # Get tool schemas
    tool_schemas = tool_registry.list_schemas() if tool_registry else None
    if not tool_schemas:
        tool_schemas = None

    # Provider fallback chain
    providers = config.all_providers
    last_error: Optional[str] = None

    for provider in providers:
        logger.info("Trying provider: %s (%s)", provider.name, provider.model)
        try:
            async for event in _run_with_provider(
                config, provider, full_messages, tool_schemas, tool_registry,
                session_id=session_id,
            ):
                if event["type"] == "error":
                    last_error = event["message"]
                    logger.warning("Provider %s failed: %s", provider.name, last_error)
                    break  # try next provider
                yield event
            else:
                # The for-else runs only if the inner loop completed without break
                return
        except LLMError as e:
            last_error = str(e)
            logger.warning("Provider %s raised LLMError: %s", provider.name, last_error)
            continue

    # All providers failed
    yield {
        "type": "error",
        "message": f"All providers failed. Last error: {last_error or 'unknown'}",
    }


async def _run_with_provider(
    config: Config,
    provider,
    messages: List[ChatMessage],
    tool_schemas: Optional[List[dict]],
    tool_registry: ToolRegistry,
    session_id: str,
) -> AsyncIterator[Dict]:
    """Run the loop with one specific provider, falling through tool iterations."""
    iteration = 0
    # Mutable list of messages — we append tool results as we go
    conversation = list(messages)

    while iteration < config.max_tool_iterations:
        iteration += 1
        logger.debug("agent loop iteration %d (provider=%s, msgs=%d)", iteration, provider.name, len(conversation))

        # Stream from the LLM
        accumulated_content = ""
        accumulated_thinking = ""
        tool_calls: List[Dict] = []  # [{"id", "name", "arguments"}]
        usage: Dict = {}

        try:
            async for event in stream_chat(provider, conversation, tools=tool_schemas):
                etype = event["type"]
                if etype == "content":
                    accumulated_content += event["text"]
                    yield event
                elif etype == "thinking":
                    accumulated_thinking += event["text"]
                    yield event
                elif etype == "tool_call":
                    # OpenAI streams tool calls in fragments; merge by id+name
                    tc_id = event.get("id", "")
                    tc_name = event.get("name", "")
                    tc_args = event.get("arguments", {})
                    # Find or create matching tool call entry
                    existing = next(
                        (t for t in tool_calls if t.get("id") == tc_id or (tc_id == "" and t.get("name") == tc_name)),
                        None,
                    )
                    if existing is None:
                        tool_calls.append({
                            "id": tc_id or f"call_{tc_name}_{iteration}",
                            "type": "function",
                            "function": {
                                "name": tc_name,
                                "arguments": json.dumps(tc_args) if not isinstance(tc_args, str) else tc_args,
                            },
                        })
                    else:
                        # Merge arguments (OpenAI streams arguments incrementally as JSON string fragments)
                        old_args_str = existing["function"]["arguments"]
                        new_args = tc_args
                        if isinstance(new_args, dict):
                            new_args_str = json.dumps(new_args)
                        else:
                            new_args_str = new_args
                        if old_args_str and new_args_str:
                            existing["function"]["arguments"] = old_args_str + new_args_str
                        else:
                            existing["function"]["arguments"] = old_args_str or new_args_str
                elif etype == "usage":
                    usage = {k: v for k, v in event.items() if k != "type"}
                elif etype == "done":
                    pass  # we'll signal done at the end
                elif etype == "error":
                    # Bubble up to outer loop for provider fallback
                    yield event
                    return
        except LLMError as e:
            yield {"type": "error", "message": str(e)}
            return

        # If no content and no tool calls, we're done (edge case)
        if not accumulated_content and not tool_calls:
            yield {"type": "done", "session_id": session_id}
            return

        # Append the assistant message to conversation
        assistant_msg = ChatMessage(
            role="assistant",
            content=accumulated_content or None,
            thinking=accumulated_thinking or None,
            tool_calls=tool_calls if tool_calls else None,
        )
        conversation.append(assistant_msg)

        # If no tool calls, the LLM is done
        if not tool_calls:
            if usage:
                yield {"type": "usage", **usage}
            yield {"type": "done", "session_id": session_id}
            return

        # Execute each tool call
        for tc in tool_calls:
            fn_name = tc["function"]["name"]
            raw_args = tc["function"]["arguments"]
            # Parse arguments (may be a partial JSON string)
            try:
                if isinstance(raw_args, str):
                    args = json.loads(raw_args) if raw_args.strip() else {}
                else:
                    args = raw_args
            except json.JSONDecodeError:
                args = {"_raw": raw_args}

            # Yield the tool call to the client (so the UI can show "Calling battery_status...")
            yield {
                "type": "tool_call",
                "id": tc["id"],
                "name": fn_name,
                "arguments": args,
            }

            # Execute
            logger.info("calling tool: %s(%s)", fn_name, args)
            result = await tool_registry.call(fn_name, args)
            yield {
                "type": "tool_result",
                "id": tc["id"],
                "name": fn_name,
                "result": result,
            }

            # Append tool result to conversation
            tool_msg = ChatMessage(
                role="tool",
                content=json.dumps(result),
                name=fn_name,
                tool_call_id=tc["id"],
            )
            conversation.append(tool_msg)

        # Loop continues — call LLM again with the new tool results

    # Hit max iterations
    yield {
        "type": "error",
        "message": f"Agent exceeded max tool iterations ({config.max_tool_iterations})",
    }
