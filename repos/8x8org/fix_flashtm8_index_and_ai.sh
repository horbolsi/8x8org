#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
ENVFILE="$APP/.env"
INDEX="$BACK/workspace_index.py"

echo "✅ Repo: $REPO"
echo "✅ Fixing FlashTM8 indexing + AI provider fallback..."

# -----------------------------
# 1) Force WORKSPACE_ROOT correct
# -----------------------------
mkdir -p "$APP/runtime"
touch "$ENVFILE"

python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/.env")
lines = p.read_text(errors="ignore").splitlines() if p.exists() else []
env = {}

for ln in lines:
    ln = ln.strip()
    if not ln or ln.startswith("#") or "=" not in ln:
        continue
    k,v = ln.split("=",1)
    env[k.strip()] = v.strip()

# hard force correct workspace root
env["WORKSPACE_ROOT"] = "/home/runner/workspace/repos/8x8org"
env["AI_PROVIDER"] = env.get("AI_PROVIDER","auto") or "auto"
env["HOST"] = env.get("HOST","0.0.0.0") or "0.0.0.0"
env["PORT"] = env.get("PORT","5000") or "5000"

# keep safety defaults
env.setdefault("ENABLE_EXEC","0")
env.setdefault("ENABLE_WRITE","0")

# make file source-safe
def quote(v: str) -> str:
    v=v.strip()
    if not v:
        return '""'
    if v[0] in "\"'" and v[-1] in "\"'":
        return v
    if any(c.isspace() for c in v):
        v=v.replace("'", "'\"'\"'")
        return f"'{v}'"
    return v

out=[]
for k in sorted(env.keys()):
    out.append(f"{k}={quote(env[k])}")
p.write_text("\n".join(out).strip()+"\n")
print("✅ .env fixed: WORKSPACE_ROOT + safe quoting")
PY

# -----------------------------
# 2) Patch workspace_index.py to index MORE files (no over-exclude)
# -----------------------------
echo "✅ Patching workspace_index.py to index correctly..."

cat <<'PY' > "$INDEX"
import os
import sqlite3
import hashlib

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "runtime", "index.db")

# Only exclude by folder NAME (safe)
EXCLUDE_NAMES = {
    ".git",
    ".venv",
    "__pycache__",
    "node_modules",
    "dist",
    "build",
}

# Index these extensions (expanded)
EXTS = {
    ".py",".sh",".md",".txt",".json",".toml",".yaml",".yml",
    ".js",".ts",".tsx",".css",".html",".env",".replit"
}

MAX_BYTES = 600_000  # allow bigger files too

def _conn():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    c = sqlite3.connect(DB_PATH)
    c.execute("""
    CREATE TABLE IF NOT EXISTS files (
        path TEXT PRIMARY KEY,
        size INTEGER,
        mtime REAL,
        sha TEXT,
        text TEXT
    )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)")
    return c

def _hash_text(txt: str) -> str:
    return hashlib.sha256(txt.encode("utf-8", errors="ignore")).hexdigest()[:16]

def index_workspace(root: str) -> dict:
    root = os.path.abspath(root)
    c = _conn()
    files = 0

    for dirpath, dirnames, filenames in os.walk(root):
        # exclude by folder name only
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_NAMES]

        for fn in filenames:
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root).replace("\\","/")

            ext = os.path.splitext(fn)[1].lower()
            if ext and ext not in EXTS:
                continue

            try:
                st = os.stat(p)
                if st.st_size > MAX_BYTES:
                    continue

                try:
                    with open(p, "r", encoding="utf-8", errors="ignore") as f:
                        txt = f.read()
                except Exception:
                    txt = ""

                sha = _hash_text(txt[:40000])
                c.execute(
                    "INSERT OR REPLACE INTO files(path,size,mtime,sha,text) VALUES(?,?,?,?,?)",
                    (rel, st.st_size, st.st_mtime, sha, txt[:40000])
                )
                files += 1
            except Exception:
                continue

    c.commit()
    c.close()
    return {"ok": True, "files": files, "db": DB_PATH}

def workspace_summary(root: str) -> str:
    root = os.path.abspath(root)
    c = _conn()
    cur = c.execute("SELECT path FROM files ORDER BY path LIMIT 250")
    paths = [r[0] for r in cur.fetchall()]
    c.close()
    return "Indexed files (sample):\n" + "\n".join(paths)

def search(query: str, root: str | None = None, limit: int = 25):
    q = query.strip().lower()
    if not q:
        return []
    c = _conn()
    cur = c.execute("SELECT path, text FROM files")
    hits = []
    for path, text in cur.fetchall():
        t = (text or "").lower()
        if q in path.lower() or q in t:
            idx = t.find(q)
            snippet = ""
            if idx >= 0:
                snippet = (text or "")[max(0, idx-90): idx+220].replace("\n"," ")
            hits.append({"path": path, "snippet": snippet[:320]})
            if len(hits) >= limit:
                break
    c.close()
    return hits
PY

# -----------------------------
# 3) Quick sanity test (index locally)
# -----------------------------
echo "✅ Running local index test..."
cd "$BACK"
python - <<'PY'
import os
import workspace_index
root = os.environ.get("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")
res = workspace_index.index_workspace(root)
print("INDEX RESULT:", res)
PY

echo ""
echo "✅ DONE. Now restart FlashTM8:"
echo "   cd $REPO"
echo "   set -a; source $ENVFILE; set +a"
echo "   PORT=5000 bash start_flashtm8.sh"
echo ""
