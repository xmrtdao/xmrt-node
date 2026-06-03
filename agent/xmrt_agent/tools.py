"""Tool registry for XMRT Agent.

Each tool is a Python function exposed to the LLM. The LLM sees them as
JSON schemas in the OpenAI/Ollama `tools` field.

Categories:
  - Termux:API tools (battery, location, camera, notification, etc.) — only
    registered when enable_termux_tools is True
  - Built-in tools (memory read/write, soul read/write, session list)
  - Custom tools (added via plugin entry points, future)

Design:
  - Tools are pure functions that take a dict of args and return a dict result.
  - Errors are caught and returned as {"error": "..."} so the LLM can recover.
  - Schemas follow OpenAI's tool format: name, description, parameters (JSON Schema).
"""

import logging
import subprocess
import json
import shutil
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from .config import Config

logger = logging.getLogger("xmrt-agent.tools")


# ──────────────────────────────────────────────────────────────────────
# Termux:API tool implementations
# ──────────────────────────────────────────────────────────────────────


def _termux_available() -> bool:
    """Check if termux-api is installed (the `termux-*` commands exist)."""
    return shutil.which("termux-battery-status") is not None


def _run_termux(cmd: str, *args: str, timeout: int = 30) -> Dict[str, Any]:
    """Run a termux-api command, return parsed JSON or raw output.

    Wraps subprocess.run with sensible defaults.
    """
    full_cmd = ["termux-" + cmd, *args]
    try:
        result = subprocess.run(
            full_cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"error": f"termux-{cmd} timed out after {timeout}s"}
    except FileNotFoundError:
        return {"error": f"termux-{cmd} not found — is termux-api installed?"}

    if result.returncode != 0:
        return {"error": result.stderr.strip() or f"exit {result.returncode}"}

    out = result.stdout.strip()
    if not out:
        return {"output": ""}
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return {"output": out}


def termux_battery_status(args: dict) -> Dict[str, Any]:
    """Get the device battery status: percentage, temperature, health, plugged status."""
    return _run_termux("battery-status")


def termux_location(args: dict) -> Dict[str, Any]:
    """Get the device's current location.

    Args:
      provider: "gps" | "network" | "passive" (default: gps)
    """
    provider = args.get("provider", "gps")
    return _run_termux("location", "-p", provider, timeout=20)


def termux_camera_photo(args: dict) -> Dict[str, Any]:
    """Take a photo with the device camera and save to a file.

    Args:
      camera: 0 (back) | 1 (front), default 0
      output: file path to save to, default /sdcard/xmrt-photo.jpg
    """
    camera = str(args.get("camera", 0))
    output = args.get("output", "/sdcard/xmrt-photo.jpg")
    result = _run_termux("camera-photo", "-c", camera, output)
    if "error" not in result:
        return {"path": output, "size": Path(output).stat().st_size if Path(output).exists() else 0}
    return result


def termux_notification(args: dict) -> Dict[str, Any]:
    """Show a system notification.

    Args:
      title: notification title
      content: notification body
      id: optional notification ID (replace existing)
    """
    title = args.get("title", "XMRT Agent")
    content = args.get("content", "")
    if not content:
        return {"error": "content is required"}
    cmd_args = ["-t", title, "-c", content]
    if "id" in args:
        cmd_args.extend(["--id", str(args["id"])])
    return _run_termux("notification", *cmd_args)


def termux_clipboard_get(args: dict) -> Dict[str, Any]:
    """Read the device's system clipboard."""
    return _run_termux("clipboard-get")


def termux_clipboard_set(args: dict) -> Dict[str, Any]:
    """Write text to the device's system clipboard.

    Args:
      text: text to copy
    """
    text = args.get("text", "")
    if not text:
        return {"error": "text is required"}
    return _run_termux("clipboard-set", text)


def termux_vibrate(args: dict) -> Dict[str, Any]:
    """Vibrate the device.

    Args:
      duration: milliseconds (default 300)
    """
    duration = str(args.get("duration", 300))
    return _run_termux("vibrate", "-d", duration)


def termux_torch(args: dict) -> Dict[str, Any]:
    """Toggle the device flashlight.

    Args:
      state: "on" | "off"
    """
    state = args.get("state", "on")
    if state not in ("on", "off"):
        return {"error": "state must be 'on' or 'off'"}
    return _run_termux("torch", state)


def termux_wifi_info(args: dict) -> Dict[str, Any]:
    """Get current WiFi connection info (SSID, IP, signal strength)."""
    return _run_termux("wifi-connectioninfo")


def termux_volume(args: dict) -> Dict[str, Any]:
    """Set device volume.

    Args:
      stream: "music" | "ring" | "alarm" | "notification" | "system"
      level: 0-15
    """
    stream = args.get("stream", "music")
    level = str(args.get("level", 5))
    return _run_termux("volume", stream, level)


def termux_toast(args: dict) -> Dict[str, Any]:
    """Show a short toast message.

    Args:
      message: text to show
    """
    message = args.get("message", "")
    if not message:
        return {"error": "message is required"}
    return _run_termux("toast", message)


# ──────────────────────────────────────────────────────────────────────
# Tool registry
# ──────────────────────────────────────────────────────────────────────


@dataclass
class Tool:
    """One callable tool exposed to the LLM."""
    name: str
    description: str
    parameters: Dict[str, Any]  # JSON Schema
    fn: Callable[[Dict[str, Any]], Dict[str, Any]]
    category: str = "general"

    def to_openai_schema(self) -> Dict[str, Any]:
        """Serialize to OpenAI tool format."""
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters,
            },
        }


# JSON Schema for an empty parameters object (most Termux tools)
_EMPTY_PARAMS = {"type": "object", "properties": {}, "required": []}


def _string_param(name: str, description: str, enum: Optional[List[str]] = None, required: bool = True) -> Dict[str, Any]:
    """Helper to build a string parameter schema."""
    p: Dict[str, Any] = {"type": "string", "description": description}
    if enum:
        p["enum"] = enum
    return p


def _int_param(name: str, description: str, default: Optional[int] = None, minimum: int = 0) -> Dict[str, Any]:
    p: Dict[str, Any] = {"type": "integer", "description": description, "minimum": minimum}
    if default is not None:
        p["default"] = default
    return p


def build_termux_tools() -> List[Tool]:
    """Build the list of Termux:API tools (if available on this device)."""
    if not _termux_available():
        logger.info("termux-api not found; Termux tools disabled")
        return []

    return [
        Tool(
            name="battery_status",
            description="Get the device battery status: percentage, temperature, health, and whether it's plugged in.",
            parameters=_EMPTY_PARAMS,
            fn=termux_battery_status,
            category="termux",
        ),
        Tool(
            name="get_location",
            description="Get the device's current location (latitude, longitude, accuracy). Uses GPS by default; pass 'network' for faster but less accurate result.",
            parameters={
                "type": "object",
                "properties": {
                    "provider": _string_param("provider", "Location provider", enum=["gps", "network", "passive"]),
                },
            },
            fn=termux_location,
            category="termux",
        ),
        Tool(
            name="take_photo",
            description="Take a photo with the device camera. Returns the file path. Use camera=0 for back, 1 for front.",
            parameters={
                "type": "object",
                "properties": {
                    "camera": _int_param("camera", "0=back, 1=front", default=0, minimum=0),
                    "output": _string_param("output", "File path to save to"),
                },
            },
            fn=termux_camera_photo,
            category="termux",
        ),
        Tool(
            name="show_notification",
            description="Show an Android system notification. Useful for alerts or to surface results to the user.",
            parameters={
                "type": "object",
                "properties": {
                    "title": _string_param("title", "Notification title"),
                    "content": _string_param("content", "Notification body text"),
                },
                "required": ["content"],
            },
            fn=termux_notification,
            category="termux",
        ),
        Tool(
            name="get_clipboard",
            description="Read the current contents of the device's system clipboard.",
            parameters=_EMPTY_PARAMS,
            fn=termux_clipboard_get,
            category="termux",
        ),
        Tool(
            name="set_clipboard",
            description="Write text to the device's system clipboard. The user can then paste it elsewhere.",
            parameters={
                "type": "object",
                "properties": {
                    "text": _string_param("text", "Text to copy to clipboard"),
                },
                "required": ["text"],
            },
            fn=termux_clipboard_set,
            category="termux",
        ),
        Tool(
            name="vibrate",
            description="Vibrate the device. Useful for alerts or to get the user's attention.",
            parameters={
                "type": "object",
                "properties": {
                    "duration": _int_param("duration", "Duration in milliseconds", default=300, minimum=50),
                },
            },
            fn=termux_vibrate,
            category="termux",
        ),
        Tool(
            name="toggle_flashlight",
            description="Turn the device flashlight on or off.",
            parameters={
                "type": "object",
                "properties": {
                    "state": _string_param("state", "on or off", enum=["on", "off"]),
                },
                "required": ["state"],
            },
            fn=termux_torch,
            category="termux",
        ),
        Tool(
            name="get_wifi_info",
            description="Get current WiFi connection info: SSID, IP address, signal strength, link speed.",
            parameters=_EMPTY_PARAMS,
            fn=termux_wifi_info,
            category="termux",
        ),
        Tool(
            name="set_volume",
            description="Set the device volume for a specific stream (music, ring, alarm, notification, system).",
            parameters={
                "type": "object",
                "properties": {
                    "stream": _string_param("stream", "Audio stream", enum=["music", "ring", "alarm", "notification", "system"]),
                    "level": _int_param("level", "Volume level 0-15", default=5, minimum=0),
                },
                "required": ["stream", "level"],
            },
            fn=termux_volume,
            category="termux",
        ),
        Tool(
            name="show_toast",
            description="Show a short toast message (popup) on the device.",
            parameters={
                "type": "object",
                "properties": {
                    "message": _string_param("message", "Toast message text"),
                },
                "required": ["message"],
            },
            fn=termux_toast,
            category="termux",
        ),
    ]


class ToolRegistry:
    """Holds the active tool set and dispatches calls."""

    def __init__(self, config: Config):
        self.config = config
        self.tools: Dict[str, Tool] = {}
        self._load_builtin_tools()
        if config.enable_termux_tools:
            self._load_termux_tools()

    def _load_builtin_tools(self) -> None:
        """Add tools that don't depend on Termux."""
        # We'll add memory/soul tools in their respective modules
        # For now, leave this for the future memory/soul integrations
        pass

    def _load_termux_tools(self) -> None:
        for tool in build_termux_tools():
            self.tools[tool.name] = tool

    def add(self, tool: Tool) -> None:
        """Register a new tool (e.g. from a skill)."""
        self.tools[tool.name] = tool

    def list_schemas(self) -> List[Dict[str, Any]]:
        """Return OpenAI-format tool schemas for all registered tools."""
        return [t.to_openai_schema() for t in self.tools.values()]

    async def call(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatch a tool call. Returns the result dict.

        On unknown tool: returns {"error": "unknown tool: NAME"}.
        On exception: returns {"error": "..."} with the message.
        """
        tool = self.tools.get(name)
        if tool is None:
            return {"error": f"unknown tool: {name}"}

        start = time.time()
        try:
            result = tool.fn(arguments or {})
            duration = time.time() - start
            logger.debug("tool %s took %.2fs", name, duration)
            if not isinstance(result, dict):
                result = {"output": str(result)}
            return result
        except Exception as e:
            logger.exception("tool %s failed", name)
            return {"error": f"tool {name} failed: {e}"}
