"""Pip-installable entry point for `pip install -e .` use.

Lets users install the agent as a package and run `xmrt-agent` from anywhere.
"""

from xmrt_agent.__main__ import main

if __name__ == "__main__":
    main()
