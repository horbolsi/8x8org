import os, json, requests, traceback
from typing import Tuple

def _env(k, d=""):
    return os.getenv(k, d)

def _ok(provider: str, reply: str):
    return {"ok": True, "provider": provider, "reply": reply}

def _fail(provider: str, err: str):
    return {"ok": False, "provider": provider, "error": err}

def _post_json(url, headers=None, payload=None, timeout=40):
    r = requests.post(url, headers=headers or {}, json=payload or {}, timeout=timeout)
    return r.status_code, r.text

def provider_local_llama(prompt: str):
    model_path = _env("LOCAL_MODEL_PATH", "")
    if not model_path or not os.path.exists(model_path):
        return _fail("local", "LOCAL_MODEL_PATH missing or file not found")

    try:
        from llama_cpp import Llama
    except Exception:
        return _fail("local", "llama-cpp-python not installed")

    try:
        llm = Llama(model_path=model_path, n_ctx=4096)
        out = llm(prompt, max_tokens=512, stop=["</s>"])
        text = out["choices"][0]["text"].strip()
        return _ok("local", text or "[empty reply]")
    except Exception as e:
        return _fail("local", str(e))

def provider_ollama(prompt: str):
    base = _env("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
    model = _env("OLLAMA_MODEL", "llama3")
    try:
        code, txt = _post_json(
            f"{base}/api/generate",
            payload={"model": model, "prompt": prompt, "stream": False},
            timeout=40
        )
        if code != 200:
            return _fail("ollama", f"HTTP {code}: {txt[:200]}")
        data = json.loads(txt)
        return _ok("ollama", (data.get("response") or "").strip() or "[empty]")
    except Exception as e:
        return _fail("ollama", str(e))

def provider_openai(prompt: str):
    key = _env("OPENAI_API_KEY", "")
    if not key:
        return _fail("openai", "OPENAI_API_KEY missing")
    model = _env("OPENAI_MODEL", "gpt-4o-mini")
    try:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        payload = {
            "model": model,
            "messages": [{"role":"user","content": prompt}],
            "temperature": 0.2
        }
        code, txt = _post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return _fail("openai", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return _ok("openai", reply.strip())
    except Exception as e:
        return _fail("openai", str(e))

def provider_gemini(prompt: str):
    key = _env("GEMINI_API_KEY", "")
    if not key:
        return _fail("gemini", "GEMINI_API_KEY missing")
    model = _env("GEMINI_MODEL", "gemini-1.5-flash")
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
        payload = {"contents":[{"parts":[{"text": prompt}]}]}
        code, txt = _post_json(url, payload=payload, timeout=60)
        if code != 200:
            return _fail("gemini", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["candidates"][0]["content"]["parts"][0]["text"]
        return _ok("gemini", reply.strip())
    except Exception as e:
        return _fail("gemini", str(e))

def provider_deepseek(prompt: str):
    key = _env("DEEPSEEK_API_KEY", "")
    if not key:
        return _fail("deepseek", "DEEPSEEK_API_KEY missing")
    model = _env("DEEPSEEK_MODEL", "deepseek-chat")
    base = _env("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
    try:
        url = f"{base}/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type":"application/json"}
        payload = {
            "model": model,
            "messages": [{"role":"user","content": prompt}],
            "temperature": 0.2
        }
        code, txt = _post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return _fail("deepseek", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return _ok("deepseek", reply.strip())
    except Exception as e:
        return _fail("deepseek", str(e))

def provider_fallback(prompt: str):
    # Always works: minimal helpful answer without LLM
    return _ok(
        "fallback",
        "FlashTM8 is running ✅\n"
        "AI provider is not reachable right now, but workspace indexing + search + tools still work.\n"
        "Try: Index Workspace → Search → Ask about run scripts."
    )

def generate_reply(prompt: str) -> Tuple[str, dict]:
    mode = _env("AI_PROVIDER", "auto").strip().lower()

    chain = []
    if mode == "auto":
        # Best order for Termux reliability:
        # local → ollama → gemini → openai → deepseek → fallback
        chain = [provider_local_llama, provider_ollama, provider_gemini, provider_openai, provider_deepseek, provider_fallback]
    elif mode == "local":
        chain = [provider_local_llama, provider_fallback]
    elif mode == "ollama":
        chain = [provider_ollama, provider_fallback]
    elif mode == "gemini":
        chain = [provider_gemini, provider_fallback]
    elif mode == "openai":
        chain = [provider_openai, provider_fallback]
    elif mode == "deepseek":
        chain = [provider_deepseek, provider_fallback]
    else:
        chain = [provider_fallback]

    last = None
    for fn in chain:
        res = fn(prompt)
        last = res
        if res.get("ok"):
            return res.get("provider","unknown"), res

    return "fallback", last or provider_fallback(prompt)
