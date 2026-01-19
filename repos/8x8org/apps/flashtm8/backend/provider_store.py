import json
from pathlib import Path

PROVIDERS_FILE = Path(__file__).resolve().parent.parent / "runtime" / "providers.json"

DEFAULTS = {
    "AI_PROVIDER": "auto",
    "OLLAMA_BASE_URL": "http://127.0.0.1:11434",
    "OLLAMA_MODEL": "llama3.2:3b",

    "OPENAI_API_KEY": "",
    "OPENAI_BASE_URL": "https://api.openai.com/v1",

    "DEEPSEEK_API_KEY": "",
    "DEEPSEEK_BASE_URL": "https://api.deepseek.com/v1",

    "GEMINI_API_KEY": "",
}

def load():
    if PROVIDERS_FILE.exists():
        try:
            data = json.loads(PROVIDERS_FILE.read_text(encoding="utf-8"))
            out = DEFAULTS.copy()
            out.update(data or {})
            return out
        except Exception:
            return DEFAULTS.copy()
    return DEFAULTS.copy()

def save(new_data: dict):
    out = load()
    out.update(new_data or {})
    PROVIDERS_FILE.parent.mkdir(parents=True, exist_ok=True)
    PROVIDERS_FILE.write_text(json.dumps(out, indent=2), encoding="utf-8")
    return out
