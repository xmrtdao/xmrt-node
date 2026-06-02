"""Skill loader for XMRT Agent.

Skills are directories containing a SKILL.md file. Each SKILL.md has:
  - YAML frontmatter (between ---) with metadata: name, description, tools, etc.
  - Markdown body with instructions for the LLM

When a skill is "active", its body gets injected into the system prompt
so the LLM knows it can handle specific tasks. The body describes:
  - What the skill does
  - When to use it
  - How to use the available tools to accomplish the goal

This is the same SKILL.md format used by hermes-agent and the Claude
Agent SDK. We deliberately match it for compatibility.
"""

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Dict, Any

import yaml

logger = logging.getLogger("xmrt-agent.skills")


@dataclass
class Skill:
    """One loaded skill."""
    name: str
    description: str
    path: Path
    body: str
    metadata: Dict[str, Any] = field(default_factory=dict)
    enabled: bool = True

    def to_system_prompt_section(self) -> str:
        """Render this skill as a system prompt section."""
        if not self.enabled:
            return ""
        return f"## Skill: {self.name}\n\n{self.description}\n\n{self.body}".strip()


# YAML frontmatter regex: matches --- at start of file, then content, then ---
_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)$", re.DOTALL)


def parse_skill_file(path: Path) -> Optional[Skill]:
    """Parse a single SKILL.md file."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        logger.warning("Failed to read skill %s: %s", path, e)
        return None

    m = _FRONTMATTER_RE.match(text)
    if not m:
        logger.warning("Skill %s has no YAML frontmatter, skipping", path)
        return None

    try:
        meta = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError as e:
        logger.warning("Skill %s has invalid YAML: %s", path, e)
        return None

    body = m.group(2).strip()
    name = meta.get("name") or path.parent.name
    description = meta.get("description", "").strip()

    return Skill(
        name=name,
        description=description,
        path=path,
        body=body,
        metadata=meta,
        enabled=meta.get("enabled", True),
    )


def discover_skills(skills_dirs: List[str]) -> List[Skill]:
    """Find all SKILL.md files in the given directories and parse them.

    Each dir is expanded with ~ and searched recursively. Only immediate
    subdirectories with a SKILL.md are treated as skills.
    """
    skills: List[Skill] = []
    seen_paths: set = set()

    for dir_str in skills_dirs:
        dir_path = Path(dir_str).expanduser()
        if not dir_path.is_dir():
            logger.debug("Skills dir %s does not exist, skipping", dir_path)
            continue

        for skill_md in dir_path.glob("*/SKILL.md"):
            if skill_md in seen_paths:
                continue
            seen_paths.add(skill_md)

            skill = parse_skill_file(skill_md)
            if skill:
                skills.append(skill)
                logger.info("Loaded skill: %s (%s)", skill.name, skill.description[:50])

    return skills


def render_skills_as_prompt(skills: List[Skill], max_chars: int = 8000) -> str:
    """Render the active skills as a system prompt section.

    Caps total length to avoid blowing the context window.
    """
    sections: List[str] = []
    total = 0

    for skill in skills:
        if not skill.enabled:
            continue
        section = skill.to_system_prompt_section()
        if total + len(section) > max_chars:
            logger.warning("Skills truncated at %d chars (cap=%d)", total, max_chars)
            break
        sections.append(section)
        total += len(section)

    if not sections:
        return ""

    header = "# Active Skills\n\nThe following skills are available. Use their tools and follow their instructions when relevant.\n\n"
    return header + "\n\n---\n\n".join(sections)
