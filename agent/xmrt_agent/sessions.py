"""Session storage for XMRT Agent.

Stores chat history in SQLite. Schema:
  sessions(id, title, source, started_at, ended_at, message_count, model, preview)
  messages(id, session_id, role, content, timestamp, tool_calls, tool_name, thinking)

Mirrors hermes-desktop's state.db pattern but simplified.
"""

import json
import logging
import sqlite3
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger("xmrt-agent.sessions")


@dataclass
class Session:
    id: str
    title: str
    source: str
    started_at: int
    ended_at: Optional[int]
    message_count: int
    model: str
    preview: str


@dataclass
class Message:
    id: int
    role: str
    content: str
    timestamp: int
    tool_calls: Optional[List[Dict[str, Any]]] = None
    tool_name: Optional[str] = None
    tool_call_id: Optional[str] = None
    thinking: Optional[str] = None


SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT 'unknown',
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    message_count INTEGER NOT NULL DEFAULT 0,
    model TEXT NOT NULL DEFAULT '',
    preview TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    timestamp INTEGER NOT NULL,
    tool_calls TEXT,
    tool_name TEXT,
    tool_call_id TEXT,
    thinking TEXT,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_messages_session
    ON messages(session_id, timestamp);

CREATE INDEX IF NOT EXISTS idx_sessions_started
    ON sessions(started_at DESC);
"""


class SessionStore:
    """SQLite-backed session and message storage."""

    def __init__(self, db_path: Path):
        self.db_path = db_path
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _init_schema(self) -> None:
        with self._conn() as c:
            c.executescript(SCHEMA)

    @contextmanager
    def _conn(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    # ──────────────────────────────────────────────
    # Session CRUD
    # ──────────────────────────────────────────────

    def create_session(
        self,
        source: str = "xmrt-node",
        model: str = "",
        title: str = "",
        session_id: Optional[str] = None,
    ) -> Session:
        """Create a new session, return it."""
        sid = session_id or f"sess-{int(time.time() * 1000)}-{uuid.uuid4().hex[:8]}"
        now = int(time.time() * 1000)
        with self._conn() as c:
            c.execute(
                "INSERT INTO sessions (id, title, source, started_at, model) VALUES (?, ?, ?, ?, ?)",
                (sid, title, source, now, model),
            )
        return Session(
            id=sid, title=title, source=source,
            started_at=now, ended_at=None, message_count=0, model=model, preview="",
        )

    def get_session(self, session_id: str) -> Optional[Session]:
        with self._conn() as c:
            row = c.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
        if not row:
            return None
        return Session(
            id=row["id"], title=row["title"], source=row["source"],
            started_at=row["started_at"], ended_at=row["ended_at"],
            message_count=row["message_count"], model=row["model"], preview=row["preview"],
        )

    def list_sessions(self, limit: int = 50, offset: int = 0) -> List[Session]:
        with self._conn() as c:
            rows = c.execute(
                "SELECT * FROM sessions ORDER BY started_at DESC LIMIT ? OFFSET ?",
                (limit, offset),
            ).fetchall()
        return [
            Session(
                id=r["id"], title=r["title"], source=r["source"],
                started_at=r["started_at"], ended_at=r["ended_at"],
                message_count=r["message_count"], model=r["model"], preview=r["preview"],
            )
            for r in rows
        ]

    def delete_session(self, session_id: str) -> bool:
        with self._conn() as c:
            cur = c.execute("DELETE FROM sessions WHERE id = ?", (session_id,))
            return cur.rowcount > 0

    def end_session(self, session_id: str) -> None:
        """Mark a session as ended."""
        with self._conn() as c:
            c.execute(
                "UPDATE sessions SET ended_at = ? WHERE id = ?",
                (int(time.time() * 1000), session_id),
            )

    def update_session_title(self, session_id: str, title: str) -> None:
        with self._conn() as c:
            c.execute("UPDATE sessions SET title = ? WHERE id = ?", (title, session_id))

    def search_sessions(self, query: str, limit: int = 20) -> List[Session]:
        """Naive LIKE-based search across titles, previews, and message contents."""
        like = f"%{query}%"
        with self._conn() as c:
            rows = c.execute(
                """
                SELECT DISTINCT s.* FROM sessions s
                LEFT JOIN messages m ON m.session_id = s.id
                WHERE s.title LIKE ? OR s.preview LIKE ? OR m.content LIKE ?
                ORDER BY s.started_at DESC
                LIMIT ?
                """,
                (like, like, like, limit),
            ).fetchall()
        return [
            Session(
                id=r["id"], title=r["title"], source=r["source"],
                started_at=r["started_at"], ended_at=r["ended_at"],
                message_count=r["message_count"], model=r["model"], preview=r["preview"],
            )
            for r in rows
        ]

    # ──────────────────────────────────────────────
    # Messages
    # ──────────────────────────────────────────────

    def add_message(
        self,
        session_id: str,
        role: str,
        content: str = "",
        tool_calls: Optional[List[Dict[str, Any]]] = None,
        tool_name: Optional[str] = None,
        tool_call_id: Optional[str] = None,
        thinking: Optional[str] = None,
    ) -> Message:
        now = int(time.time() * 1000)
        tool_calls_json = json.dumps(tool_calls) if tool_calls else None
        with self._conn() as c:
            cur = c.execute(
                """
                INSERT INTO messages
                  (session_id, role, content, timestamp, tool_calls, tool_name, tool_call_id, thinking)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (session_id, role, content, now, tool_calls_json, tool_name, tool_call_id, thinking),
            )
            msg_id = cur.lastrowid
            # Update session metadata
            preview = content[:200] if content else ""
            c.execute(
                """
                UPDATE sessions SET
                    message_count = message_count + 1,
                    preview = CASE WHEN preview = '' THEN ? ELSE preview END,
                    ended_at = ?
                WHERE id = ?
                """,
                (preview, now, session_id),
            )
        return Message(
            id=msg_id, role=role, content=content, timestamp=now,
            tool_calls=tool_calls, tool_name=tool_name, tool_call_id=tool_call_id, thinking=thinking,
        )

    def get_messages(self, session_id: str) -> List[Message]:
        with self._conn() as c:
            rows = c.execute(
                "SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC",
                (session_id,),
            ).fetchall()
        return [
            Message(
                id=r["id"], role=r["role"], content=r["content"], timestamp=r["timestamp"],
                tool_calls=json.loads(r["tool_calls"]) if r["tool_calls"] else None,
                tool_name=r["tool_name"], tool_call_id=r["tool_call_id"],
                thinking=r["thinking"],
            )
            for r in rows
        ]
