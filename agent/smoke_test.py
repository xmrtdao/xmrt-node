"""Smoke tests for xmrt-agent.

Run with: python smoke_test.py
Assumes the agent is already running on http://127.0.0.1:8642.

These tests don't need Ollama — they exercise the HTTP layer and
non-LLM endpoints (health, models, skills, sessions, memory).
"""

import json
import sys
import time
import uuid

import httpx

BASE = "http://127.0.0.1:8642"
PASS = 0
FAIL = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global PASS, FAIL
    icon = "[OK]" if condition else "[X]"
    print(f"  {icon} {name}" + (f" — {detail}" if detail else ""))
    if condition:
        PASS += 1
    else:
        FAIL += 1


def main() -> int:
    print(f"=== xmrt-agent smoke tests (target: {BASE}) ===\n")

    with httpx.Client(timeout=10) as c:
        # 1. Health
        print("[Health]")
        r = c.get(f"{BASE}/health")
        check("GET /health returns 200", r.status_code == 200)
        if r.status_code == 200:
            data = r.json()
            check("status is ok", data.get("status") == "ok")
            check("version is set", data.get("version", "").startswith("0."))
            check("has providers", len(data.get("providers", [])) >= 1)
            primary = data["providers"][0] if data.get("providers") else {}
            check("primary is deepseek-v4-flash:cloud",
                  "deepseek-v4-flash" in primary.get("model", ""))
            check("4 skills loaded", len(data.get("skills", [])) == 4,
                  f"found {len(data.get('skills', []))}")

        # 2. Models (OpenAI compat)
        print("\n[Models]")
        r = c.get(f"{BASE}/v1/models")
        check("GET /v1/models returns 200", r.status_code == 200)
        if r.status_code == 200:
            data = r.json()
            check("returns object=list", data.get("object") == "list")
            check("has deepseek-v4-flash:cloud",
                  any("deepseek-v4-flash" in m["id"] for m in data.get("data", [])))

        # 3. Skills
        print("\n[Skills]")
        r = c.get(f"{BASE}/v1/skills")
        check("GET /v1/skills returns 200", r.status_code == 200)
        if r.status_code == 200:
            data = r.json()
            names = [s["name"] for s in data.get("skills", [])]
            for expected in ["xmrt-mining", "xmrt-fleet", "xmrt-dao", "xmrt-monero"]:
                check(f"skill {expected} present", expected in names)

        # 4. Skill content
        r = c.get(f"{BASE}/v1/skills/xmrt-mining")
        check("GET /v1/skills/xmrt-mining returns 200", r.status_code == 200)
        if r.status_code == 200:
            data = r.json()
            check("skill has body", "body" in data and len(data["body"]) > 50)

        # 5. Sessions CRUD
        print("\n[Sessions]")
        r = c.post(f"{BASE}/v1/sessions", json={"title": f"smoke-{uuid.uuid4().hex[:6]}"})
        check("POST /v1/sessions returns 2xx", r.status_code in (200, 201))
        sid = None
        if r.status_code in (200, 201):
            sid = r.json()["id"]
            check("session has id", bool(sid))

        r = c.get(f"{BASE}/v1/sessions")
        check("GET /v1/sessions returns 200", r.status_code == 200)
        if r.status_code == 200 and sid:
            sessions = r.json().get("sessions", [])
            check("new session in list", any(s["id"] == sid for s in sessions))

        r = c.get(f"{BASE}/v1/sessions/{sid}")
        check("GET /v1/sessions/{id} returns 200", r.status_code == 200)
        if r.status_code == 200:
            data = r.json()
            check("session has messages list", "messages" in data)

        r = c.delete(f"{BASE}/v1/sessions/{sid}")
        check("DELETE /v1/sessions/{id} returns 200", r.status_code == 200)

        r = c.get(f"{BASE}/v1/sessions/{sid}")
        check("deleted session returns 404", r.status_code == 404)

        # 6. Memory read/write
        print("\n[Memory]")
        r = c.get(f"{BASE}/v1/memory")
        check("GET /v1/memory returns 200", r.status_code == 200)
        if r.status_code == 200:
            data = r.json()
            check("memory file exists", data.get("exists"))

        r = c.post(f"{BASE}/v1/memory",
                   json={"action": "append", "entry": f"smoke-test {time.time()}"})
        check("POST /v1/memory returns 200", r.status_code == 200)
        if r.status_code == 200:
            data = r.json()
            check("memory content was updated",
                  "smoke-test" in data.get("content", ""))

        # 7. Soul read/write
        print("\n[Soul]")
        r = c.get(f"{BASE}/v1/soul")
        check("GET /v1/soul returns 200", r.status_code == 200)

        # 8. User
        print("\n[User]")
        r = c.get(f"{BASE}/v1/user")
        check("GET /v1/user returns 200", r.status_code == 200)

        # 9. Skills search
        print("\n[Search]")
        r = c.get(f"{BASE}/v1/sessions/search", params={"q": "smoke"})
        check("GET /v1/sessions/search returns 200", r.status_code == 200)

        # 10. Chat endpoint exists (don't actually call LLM)
        print("\n[Chat endpoint]")
        r = c.post(f"{BASE}/v1/chat/completions",
                   json={"model": "deepseek-v4-flash:cloud", "messages": []},
                   headers={"X-Session-Id": f"smoke-{uuid.uuid4().hex[:6]}"})
        # Should return 400 for empty messages, not 404
        check("POST /v1/chat/completions is reachable", r.status_code in (400, 200))
        if r.status_code == 400:
            check("rejects empty messages gracefully", "messages" in r.json().get("error", {}).get("message", "").lower() or "empty" in str(r.json()).lower())

    print(f"\n=== Results: {PASS} passed, {FAIL} failed ===")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
