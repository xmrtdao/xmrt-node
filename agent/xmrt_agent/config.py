"""Configuration loader for XMRT Agent.

Reads ~/.local/share/xmrt-agent/config.yaml and exposes a typed Config object.
Falls back to sane defaults if file is missing.

Default config matches the locked-in plan:
  primary: deepseek-v4-flash:cloud (Ollama OAuth)
  fallbacks: qwen3-coder:480b-cloud, Kimi, OpenRouter
  no local-first fallback (4-6GB Android phones can't run decent local models)
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

import yaml


@dataclass
class Provider:
    """One LLM provider entry (Ollama, Kimi, OpenRouter, etc.)."""
    name: str
    base_url: str
    model: str
    auth_env: Optional[str] = None  # env var name that holds the API key
    api_key: Optional[str] = None   # inline key (avoid; prefer env)
    is_ollama: bool = False
    extra: dict = field(default_factory=dict)


@dataclass
class ProviderConfig:
    """All LLM provider entries. Agent tries primary, then fallbacks."""
    primary: Provider
    fallbacks: List[Provider] = field(default_factory=list)

    def all_providers(self) -> List[Provider]:
        return [self.primary] + self.fallbacks


@dataclass
class AgentConfig:
    """Top-level config object."""
    provider: ProviderConfig
    name: str = "XMRT Agent"
    max_context_messages: int = 50
    max_tool_iterations: int = 8
    tool_timeout_seconds: int = 30
    enable_termux_tools: bool = True
    skills_dirs: List[str] = field(default_factory=list)

    # Sub-configs
    @property
    def all_providers(self) -> List[Provider]:
        return self.provider.all_providers()


# Alias for the loader function below
Config = AgentConfig


def _default_yaml() -> dict:
    """Hardcoded fallback config — used when config.yaml doesn't exist."""
    return {
        "name": "XMRT Agent",
        "provider": {
            "primary": {
                "name": "ollama-cloud",
                "base_url": "http://127.0.0.1:11434",
                "model": "deepseek-v4-flash:cloud",
                "is_ollama": True,
            },
            "fallbacks": [
                {
                    "name": "ollama-cloud-qwen-coder",
                    "base_url": "http://127.0.0.1:11434",
                    "model": "qwen3-coder:480b-cloud",
                    "is_ollama": True,
                },
                {
                    "name": "kimi",
                    "base_url": "https://api.kimi.com/coding/v1",
                    "model": "kimi-for-coding",
                    "auth_env": "KIMI_API_KEY",
                },
                {
                    "name": "openrouter",
                    "base_url": "https://openrouter.ai/api/v1",
                    "model": "deepseek/deepseek-v3.1",
                    "auth_env": "OPENROUTER_API_KEY",
                },
            ],
        },
        "max_context_messages": 50,
        "max_tool_iterations": 8,
        "tool_timeout_seconds": 30,
        "enable_termux_tools": True,
        "skills_dirs": ["~/.local/share/xmrt-agent/skills"],
    }


def _parse_provider(d: dict) -> Provider:
    """Parse one provider entry from a config dict."""
    import os
    auth_env = d.get("auth_env")
    api_key = d.get("api_key")
    if auth_env and not api_key:
        api_key = os.environ.get(auth_env)
    return Provider(
        name=d.get("name", "unknown"),
        base_url=d["base_url"].rstrip("/"),
        model=d["model"],
        auth_env=auth_env,
        api_key=api_key,
        is_ollama=d.get("is_ollama", False),
        extra={k: v for k, v in d.items()
               if k not in ("name", "base_url", "model", "auth_env", "api_key", "is_ollama")},
    )


def load_config(home: Path) -> Config:
    """Load config from <home>/config.yaml. Falls back to defaults."""
    config_path = home / "config.yaml"
    if config_path.exists():
        with config_path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    else:
        data = _default_yaml()
        # Write the default so the user can edit it
        try:
            with config_path.open("w", encoding="utf-8") as f:
                yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
        except OSError:
            pass  # read-only filesystem; just use in-memory defaults

    primary = _parse_provider(data.get("provider", {}).get("primary", {}))
    fallbacks = [_parse_provider(fb) for fb in data.get("provider", {}).get("fallbacks", [])]

    return Config(
        provider=ProviderConfig(primary=primary, fallbacks=fallbacks),
        name=data.get("name", "XMRT Agent"),
        max_context_messages=data.get("max_context_messages", 50),
        max_tool_iterations=data.get("max_tool_iterations", 8),
        tool_timeout_seconds=data.get("tool_timeout_seconds", 30),
        enable_termux_tools=data.get("enable_termux_tools", True),
        skills_dirs=data.get("skills_dirs", []),
    )
