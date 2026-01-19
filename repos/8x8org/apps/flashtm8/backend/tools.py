import os, subprocess
from pathlib import Path

def is_enabled(name: str) -> bool:
    return os.getenv(name, "0") in ("1","true","TRUE","yes","YES","on","ON")

def safe_exec(cmd: str, cwd: str):
    if not is_enabled("EXEC_ENABLED"):
        return {"ok": False, "error": "EXEC is disabled in .env (EXEC_ENABLED=0)"}
    try:
        r = subprocess.run(cmd, shell=True, cwd=cwd, text=True, capture_output=True)
        return {"ok": r.returncode == 0, "code": r.returncode, "stdout": r.stdout[-6000:], "stderr": r.stderr[-6000:]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def safe_write(path: str, content: str, root: str):
    if not is_enabled("WRITE_ENABLED"):
        return {"ok": False, "error": "WRITE is disabled in .env (WRITE_ENABLED=0)"}

    rp = Path(root).resolve()
    p = (rp / path).resolve()

    # Block writing outside workspace
    if not str(p).startswith(str(rp)):
        return {"ok": False, "error": "Write blocked (outside workspace)"}

    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return {"ok": True, "path": str(p)}
