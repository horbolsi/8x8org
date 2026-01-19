import os, subprocess
from pathlib import Path

def _env(k, d=""):
    return os.getenv(k, d)

def enabled(flag: str) -> bool:
    return _env(flag, "0").lower() in ("1","true","yes","on")

def _deny_by_pattern(path: str) -> bool:
    deny = _env("DENY_WRITE_PATTERNS","").lower().split(",")
    path_l = path.lower()
    return any(x.strip() and x.strip() in path_l for x in deny)

def _allowed_subdir(path: str) -> bool:
    allow = [x.strip() for x in _env("ALLOW_WRITE_SUBDIRS","").split(",") if x.strip()]
    if not allow:
        return True
    parts = Path(path).parts
    if not parts:
        return False
    # allow if first folder is in allow list
    return parts[0] in allow

def safe_exec(cmd: str, cwd: str):
    if not enabled("EXEC_ENABLED"):
        return {"ok": False, "error": "EXEC is disabled (set EXEC_ENABLED=1 in .env)"}
    try:
        r = subprocess.run(cmd, shell=True, cwd=cwd, text=True, capture_output=True)
        return {"ok": r.returncode == 0, "code": r.returncode, "stdout": r.stdout[-8000:], "stderr": r.stderr[-8000:]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def safe_write(rel_path: str, content: str, root: str):
    if not enabled("WRITE_ENABLED"):
        return {"ok": False, "error": "WRITE is disabled (set WRITE_ENABLED=1 in .env)"}

    if _deny_by_pattern(rel_path):
        return {"ok": False, "error": "Write blocked by DENY_WRITE_PATTERNS"}

    if not _allowed_subdir(rel_path):
        return {"ok": False, "error": "Write blocked (path not in ALLOW_WRITE_SUBDIRS)"}

    rp = Path(root).resolve()
    p = (rp / rel_path).resolve()

    if not str(p).startswith(str(rp)):
        return {"ok": False, "error": "Write blocked (outside WORKSPACE_ROOT)"}

    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    return {"ok": True, "path": str(p)}

def safe_read(rel_path: str, root: str):
    rp = Path(root).resolve()
    p = (rp / rel_path).resolve()
    if not str(p).startswith(str(rp)) or not p.exists() or p.is_dir():
        return {"ok": False, "error": "File not found"}
    try:
        return {"ok": True, "content": p.read_text(errors="ignore")[:20000]}
    except Exception as e:
        return {"ok": False, "error": str(e)}
