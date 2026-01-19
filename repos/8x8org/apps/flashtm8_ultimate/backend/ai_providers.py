import os, json, requests
from typing import Tuple

def env(k, d=""):
    return os.getenv(k, d)

def ok(provider: str, reply: str):
    return {"ok": True, "provider": provider, "reply": reply}

def fail(provider: str, err: str):
    return {"ok": False, "provider": provider, "error": err}

def post_json(url, headers=None, payload=None, timeout=60):
    r = requests.post(url, headers=headers or {}, json=payload or {}, timeout=timeout)
    return r.status_code, r.text

def local_llama(prompt: str):
    model_path = env("LOCAL_MODEL_PATH","")
    if not model_path:
        return fail("local", "LOCAL_MODEL_PATH missing")
    try:
        from llama_cpp import Llama
    except Exception:
        return fail("local", "llama-cpp-python not installed (optional)")
    try:
        llm = Llama(model_path=model_path, n_ctx=4096)
        out = llm(prompt, max_tokens=512)
        text = out["choices"][0]["text"].strip()
        return ok("local", text or "[empty]")
    except Exception as e:
        return fail("local", str(e))

def ollama(prompt: str):
    base = env("OLLAMA_BASE_URL","http://127.0.0.1:11434").rstrip("/")
    model = env("OLLAMA_MODEL","llama3")
    try:
        code, txt = post_json(f"{base}/api/generate", payload={"model": model, "prompt": prompt, "stream": False}, timeout=60)
        if code != 200:
            return fail("ollama", f"HTTP {code}: {txt[:200]}")
        data = json.loads(txt)
        return ok("ollama", (data.get("response") or "").strip() or "[empty]")
    except Exception as e:
        return fail("ollama", str(e))

def gemini(prompt: str):
    key = env("GEMINI_API_KEY","")
    if not key:
        return fail("gemini", "GEMINI_API_KEY missing")
    model = env("GEMINI_MODEL","gemini-1.5-flash")
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
        payload = {"contents":[{"parts":[{"text": prompt}]}]}
        code, txt = post_json(url, payload=payload, timeout=60)
        if code != 200:
            return fail("gemini", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["candidates"][0]["content"]["parts"][0]["text"]
        return ok("gemini", reply.strip())
    except Exception as e:
        return fail("gemini", str(e))

def openai(prompt: str):
    key = env("OPENAI_API_KEY","")
    if not key:
        return fail("openai", "OPENAI_API_KEY missing")
    model = env("OPENAI_MODEL","gpt-4o-mini")
    try:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type":"application/json"}
        payload = {"model": model, "messages":[{"role":"user","content":prompt}], "temperature":0.2}
        code, txt = post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return fail("openai", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return ok("openai", reply.strip())
    except Exception as e:
        return fail("openai", str(e))

def deepseek(prompt: str):
    key = env("DEEPSEEK_API_KEY","")
    if not key:
        return fail("deepseek", "DEEPSEEK_API_KEY missing")
    model = env("DEEPSEEK_MODEL","deepseek-chat")
    base = env("DEEPSEEK_BASE_URL","https://api.deepseek.com").rstrip("/")
    try:
        url = f"{base}/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type":"application/json"}
        payload = {"model": model, "messages":[{"role":"user","content":prompt}], "temperature":0.2}
        code, txt = post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return fail("deepseek", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return ok("deepseek", reply.strip())
    except Exception as e:
        return fail("deepseek", str(e))

def xai(prompt: str):
    key = env("XAI_API_KEY","")
    if not key:
        return fail("xai", "XAI_API_KEY missing")
    model = env("XAI_MODEL","grok-2-latest")
    base = env("XAI_BASE_URL","https://api.x.ai/v1").rstrip("/")
    try:
        url = f"{base}/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type":"application/json"}
        payload = {"model": model, "messages":[{"role":"user","content":prompt}], "temperature":0.2}
        code, txt = post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return fail("xai", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return ok("xai", reply.strip())
    except Exception as e:
        return fail("xai", str(e))

def fallback(prompt: str):
    return ok(
        "fallback",
        "FlashTM8 Ultimate is running ✅\n"
        "AI provider not reachable now, but indexing + search + tools still work.\n"
        "Try: Index Workspace → Search 'run.sh' → Ask how to start bots."
    )

def generate_reply(prompt: str) -> Tuple[str, dict]:
    mode = env("AI_PROVIDER","auto").strip().lower()

    chain = []
    if mode == "auto":
        chain = [local_llama, ollama, gemini, openai, xai, deepseek, fallback]
    elif mode == "local":
        chain = [local_llama, fallback]
    elif mode == "ollama":
        chain = [ollama, fallback]
    elif mode == "gemini":
        chain = [gemini, fallback]
    elif mode == "openai":
        chain = [openai, fallback]
    elif mode == "xai":
        chain = [xai, fallback]
    elif mode == "deepseek":
        chain = [deepseek, fallback]
    else:
        chain = [fallback]

    last = None
    for fn in chain:
        res = fn(prompt)
        last = res
        if res.get("ok"):
            return res.get("provider","unknown"), res

    return "fallback", last or fallback(prompt)
