"""XMRT Agent entry point.

Runs aiohttp server on 127.0.0.1:8642. Listens for OpenAI-compatible
chat requests and proxies them to Ollama (or another configured LLM).

Usage:
    python -m xmrt_agent

Environment variables (all optional):
    XMRT_AGENT_HOST       default: 127.0.0.1
    XMRT_AGENT_PORT       default: 8642
    XMRT_AGENT_HOME       default: ~/.local/share/xmrt-agent
    XMRT_LOG_LEVEL        default: INFO
"""

import asyncio
import logging
import os
import signal
import sys
from pathlib import Path

from aiohttp import web

from .config import load_config, Config
from .server import build_app

logger = logging.getLogger("xmrt-agent")


def configure_logging(level: str = "INFO") -> None:
    """Set up logging to stdout with ASCII-safe format."""
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stdout,
    )
    # aiohttp access log is noisy; demote it
    logging.getLogger("aiohttp.access").setLevel(logging.WARNING)


async def run() -> None:
    """Main entry point: load config, build app, run forever."""
    host = os.environ.get("XMRT_AGENT_HOST", "127.0.0.1")
    port = int(os.environ.get("XMRT_AGENT_PORT", "8642"))
    home = Path(os.environ.get("XMRT_AGENT_HOME", str(Path.home() / ".local" / "share" / "xmrt-agent")))

    log_level = os.environ.get("XMRT_LOG_LEVEL", "INFO")
    configure_logging(log_level)

    # Ensure home dir exists with default config + memory files
    home.mkdir(parents=True, exist_ok=True)

    config = load_config(home)
    logger.info("XMRT Agent v%s starting", __version__ if hasattr(sys.modules[__name__], "__version__") else "0.1.0")
    logger.info("Home dir: %s", home)
    logger.info("Primary model: %s @ %s", config.provider.primary.model, config.provider.primary.base_url)
    logger.info("Listening on http://%s:%d", host, port)

    app = build_app(config)

    runner = web.AppRunner(app, access_log=None)
    await runner.setup()
    site = web.TCPSite(runner, host, port)
    await site.start()

    # Graceful shutdown
    stop_event = asyncio.Event()

    def _on_signal(signame: str) -> None:
        logger.info("Received %s, shutting down...", signame)
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _on_signal, sig.name)
        except NotImplementedError:
            # Windows doesn't support add_signal_handler for all signals
            pass

    try:
        await stop_event.wait()
    finally:
        logger.info("Stopping server...")
        await runner.cleanup()
        logger.info("Bye.")


def main() -> None:
    """Sync entry point for setuptools / pip install -e ."""
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
