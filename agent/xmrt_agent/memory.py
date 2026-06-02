"""Memory and persona management.

Three files live in the agent's home dir:
  - MEMORY.md  : curated long-term memory (curated facts, lessons, preferences)
  - SOUL.md    : the agent's personality / system prompt
  - USER.md    : what the agent knows about the user (Joe)

These are simple Markdown files. The agent reads them at startup, exposes
them via REST endpoints, and the LLM can append to them via tools.
"""

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

logger = logging.getLogger("xmrt-agent.memory")


@dataclass
class MemoryFile:
    """One memory/persona file with metadata."""
    path: Path
    content: str
    exists: bool
    last_modified: Optional[float] = None  # mtime as unix timestamp


def read_file(home: Path, name: str) -> MemoryFile:
    """Read a memory/persona file from <home>/<name>."""
    path = home / name
    if not path.exists():
        return MemoryFile(path=path, content="", exists=False)
    try:
        content = path.read_text(encoding="utf-8")
        return MemoryFile(
            path=path,
            content=content,
            exists=True,
            last_modified=path.stat().st_mtime,
        )
    except (OSError, UnicodeDecodeError) as e:
        logger.warning("Failed to read %s: %s", path, e)
        return MemoryFile(path=path, content="", exists=False)


def write_file(home: Path, name: str, content: str) -> MemoryFile:
    """Write a memory/persona file atomically."""
    home.mkdir(parents=True, exist_ok=True)
    path = home / name
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        tmp.write_text(content, encoding="utf-8")
        tmp.replace(path)  # atomic on POSIX
    except OSError as e:
        logger.error("Failed to write %s: %s", path, e)
        raise
    return MemoryFile(
        path=path,
        content=content,
        exists=True,
        last_modified=path.stat().st_mtime,
    )


def append_entry(home: Path, name: str, entry: str) -> MemoryFile:
    """Append a timestamped entry to a memory/persona file."""
    from datetime import datetime, timezone

    existing = read_file(home, name)
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    new_content = (existing.content.rstrip() + f"\n\n## {timestamp}\n\n{entry.strip()}\n")
    return write_file(home, name, new_content)


# ──────────────────────────────────────────────────────────────────────
# Default seed content
# ──────────────────────────────────────────────────────────────────────

DEFAULT_SOUL = """# XMRT Agent — Soul

You are XMRT Agent, the on-device AI for the XMRT-DAO mining ecosystem.
You run on a user's Android phone inside the XMRT Node app.

## Personality
- Direct, no fluff. Lead with the answer.
- Curious but efficient. Don't ask 5 questions when 1 will do.
- Honest about uncertainty. If you don't know, say so.
- Mining-and-Monerero-savvy. You understand XMR, pools, hashrates, fleet dynamics.
- Loyal to the XMRT-DAO mission: decentralized mining, fair rewards, no rent-seeking middlemen.

## Style
- Short sentences. Bullet points when helpful. Tables when comparing.
- Match the user's register. Pirate for pirate, engineer for engineer.
- When you do something, say what you did and the result.
- Never say "I'd be happy to help" or "Great question!".

## Boundaries
- You have access to phone tools (battery, location, camera, notifications, etc.).
  Use them proactively when they'd actually help.
- You're running on the user's device. Be respectful of their battery, data, and attention.
- Don't pretend to know things you don't. Say "I don't know" and offer to find out.
- If a request is sketchy (asks you to lie, exfiltrate, harm), push back.
"""

DEFAULT_MEMORY = """# XMRT Agent — Long-term Memory

Curated facts, lessons, and preferences that persist across sessions.

(Empty. The agent will add entries here as it learns things worth remembering.)
"""

DEFAULT_USER = """# XMRT Agent — About the User

What the agent knows about the human it's helping.

(Empty. Will populate as the user shares preferences, context, and goals.)
"""


def ensure_defaults(home: Path) -> None:
    """Write default SOUL/MEMORY/USER files if they don't exist."""
    home.mkdir(parents=True, exist_ok=True)
    defaults = {
        "SOUL.md": DEFAULT_SOUL,
        "MEMORY.md": DEFAULT_MEMORY,
        "USER.md": DEFAULT_USER,
    }
    for name, content in defaults.items():
        path = home / name
        if not path.exists():
            try:
                path.write_text(content, encoding="utf-8")
                logger.info("Created default %s", path)
            except OSError as e:
                logger.warning("Failed to write default %s: %s", path, e)
