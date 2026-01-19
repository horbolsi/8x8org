import os, sqlite3, hashlib, time
from pathlib import Path

DEFAULT_EXCLUDES = {
    ".git", ".venv", "node_modules", "__pycache__", ".pytest_cache",
    "dist", "build", ".mypy_cache", ".cache"
}

def _hash_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", "ignore")).hexdigest()

def init_db(db_path: str):
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS files (
        path TEXT PRIMARY KEY,
        mtime REAL,
        size INTEGER,
        sha TEXT,
        content TEXT
    );
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_files_path ON files(path);")
    con.commit()
    con.close()

def index_workspace(root: str, db_path: str, max_bytes: int = 250_000, exclude=None):
    exclude = set(exclude or []) | DEFAULT_EXCLUDES
    init_db(db_path)
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    rootp = Path(root).resolve()
    count = 0

    for p in rootp.rglob("*"):
        try:
            if p.is_dir():
                if p.name in exclude:
                    # skip deep walking excluded folders
                    continue
                continue

            rel = str(p.relative_to(rootp))
            if any(part in exclude for part in p.parts):
                continue

            # only index text-like files
            if p.suffix.lower() not in {
                ".py",".js",".ts",".tsx",".json",".md",".txt",".sh",".html",".css",".yml",".yaml",".toml",".ini"
            }:
                continue

            st = p.stat()
            if st.st_size > max_bytes:
                # too large, index metadata only
                content = f"[SKIPPED: too large {st.st_size} bytes]"
                sha = _hash_text(content)
            else:
                content = p.read_text(errors="ignore")
                sha = _hash_text(content)

            cur.execute("""
            INSERT INTO files(path, mtime, size, sha, content)
            VALUES(?,?,?,?,?)
            ON CONFLICT(path) DO UPDATE SET
              mtime=excluded.mtime,
              size=excluded.size,
              sha=excluded.sha,
              content=excluded.content
            """, (rel, st.st_mtime, st.st_size, sha, content))
            count += 1
        except Exception:
            continue

    con.commit()
    con.close()
    return count

def search(db_path: str, q: str, limit: int = 10):
    if not Path(db_path).exists():
        return []
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    q2 = f"%{q}%"
    cur.execute("""
        SELECT path, substr(content, 1, 1200)
        FROM files
        WHERE path LIKE ? OR content LIKE ?
        LIMIT ?
    """, (q2, q2, limit))
    rows = cur.fetchall()
    con.close()
    return [{"path": r[0], "snippet": r[1]} for r in rows]
