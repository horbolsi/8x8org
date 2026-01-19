import os
import requests

def _env(k: str, d: str = "") -> str:
    return os.getenv(k, d)

def _ok(provider: str, reply: str) -> dict:
    return {"ok": True, "provider": provider, "reply": reply}

def _fail(provider: str, error: str) -> dict:
    return {"ok": False, "provider": provider, "error": error}

def chat_ollama(prompt: str) -> dict:
    try:
        base = _env("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
        model = _env("OLLAMA_MODEL", "llama3.2:1b").strip() or "llama3.2:1b"

        payload = {
            "model": model,
            "stream": False,
            "messages": [
                {"role": "system", "content": "You are FlashTM8-like assistant tied to a local workspace. Be concise and practical."},
                {"role": "user", "content": prompt},
            ],
            "options": {"temperature": 0.2},
        }

        r = requests.post(f"{base}/api/chat", json=payload, timeout=60)
        if r.status_code != 200:
            return _fail("ollama", f"HTTP {r.status_code}: {r.text[:400]}")

        data = r.json()
        text = (data.get("message") or {}).get("content", "").strip()
        if not text:
            return _fail("ollama", "Empty reply from Ollama")
        return _ok("ollama", text)

    except Exception as e:
        return _fail("ollama", str(e))

def fallback_reply(prompt: str) -> dict:
    return _ok(
        "fallback",
        "FlashTM8 is running ✅ No AI provider reachable right now.\n"
        "But workspace indexing/search/tools still work.\n\n"
        "Try: Index Workspace → then Search or Read files."
    )

def generate_reply(prompt: str) -> dict:
    mode = _env("AI_PROVIDER", "auto").strip().lower()

    if mode == "ollama":
        res = chat_ollama(prompt)
        if res.get("ok"):
            return res
        return fallback_reply(prompt)

    # auto → ollama → fallback
    res = chat_ollama(prompt)
    if res.get("ok"):
        return res
    return fallback_reply(prompt)
