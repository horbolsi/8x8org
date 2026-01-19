import os
import subprocess
import time
import sqlite3
from pathlib import Path
from typing import Dict, List

def root() -> Path:
    return Path(os.getenv("WORKSPACE_ROOT", ".")).resolve()

def safe_rel(p: Path) -> str:
    try:
        return str(p.relative_to(root()))
    except Exception:
        return str(p)

def index_db_path() -> Path:
    return Path(os.getenv("INDEX_DB", "apps/sovereign_console/runtime/index.db")).resolve()

def ensure_db():
    db = index_db_path()
    db.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db)
    cur = con.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS files(
        path TEXT PRIMARY KEY,
        size INTEGER,
        mtime INTEGER
    )""")
    con.commit()
    con.close()

def index_workspace(max_files: int = 5000) -> Dict:
    ensure_db()
    base = root()
    files = []
    for p in base.rglob("*"):
        if p.is_file():
            # skip venv/node_modules big dirs
            sp = str(p)
            if "/.git/" in sp or "/node_modules/" in sp or "/.venv/" in sp or "/__pycache__/" in sp:
                continue
            files.append(p)
            if len(files) >= max_files:
                break

    con = sqlite3.connect(index_db_path())
    cur = con.cursor()
    n = 0
    for f in files:
        st = f.stat()
        cur.execute(
            "INSERT OR REPLACE INTO files(path,size,mtime) VALUES(?,?,?)",
            (safe_rel(f), int(st.st_size), int(st.st_mtime)),
        )
        n += 1
    con.commit()
    con.close()
    return {"ok": True, "count": n}

def search_workspace(query: str, limit: int = 50) -> Dict:
    if not query.strip():
        return {"ok": True, "results": []}

    base = root()
    cmd = ["rg", "-n", "--no-heading", "--smart-case", query, str(base)]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=15).decode("utf-8", "ignore")
    except subprocess.CalledProcessError as e:
        out = e.output.decode("utf-8", "ignore")
    except Exception as e:
        return {"ok": False, "error": str(e)}

    lines = out.splitlines()[:limit]
    return {"ok": True, "results": lines}

def read_file(rel_path: str, max_bytes: int = 200_000) -> Dict:
    p = root() / rel_path
    if not p.exists() or not p.is_file():
        return {"ok": False, "error": "File not found"}
    data = p.read_bytes()[:max_bytes]
    return {"ok": True, "path": rel_path, "content": data.decode("utf-8", "ignore")}

def exec_cmd(cmd: str, timeout: int = 20) -> Dict:
    if os.getenv("EXEC_ENABLED", "false").lower() != "true":
        return {"ok": False, "error": "EXEC is disabled. Enable EXEC_ENABLED=true in Settings."}
    try:
        proc = subprocess.run(
            cmd,
            shell=True,
            cwd=str(root()),
            timeout=timeout,
            capture_output=True,
            text=True,
        )
        return {
            "ok": True,
            "code": proc.returncode,
            "stdout": proc.stdout[-20000:],
            "stderr": proc.stderr[-20000:],
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}

def write_file(rel_path: str, content: str) -> Dict:
    if os.getenv("WRITE_ENABLED", "false").lower() != "true":
        return {"ok": False, "error": "WRITE is disabled. Enable WRITE_ENABLED=true in Settings."}
    p = root() / rel_path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8", errors="ignore")
    return {"ok": True, "path": rel_path}

def metrics() -> Dict:
    try:
        import psutil
        du = psutil.disk_usage(str(root()))
        vm = psutil.virtual_memory()
        return {
            "ok": True,
            "cpu_percent": psutil.cpu_percent(interval=0.3),
            "mem_percent": vm.percent,
            "disk_percent": du.percent,
            "disk_free_gb": round(du.free / (1024**3), 2),
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}
