import os, sqlite3, hashlib
from pathlib import Path

DEFAULT_EXCLUDES = {
    ".git", ".venv", "node_modules", "__pycache__", ".pytest_cache",
    "dist", "build", ".mypy_cache", ".cache", ".idea", ".vscode"
}

TEXT_EXTS = {
    ".py",".js",".ts",".tsx",".json",".md",".txt",".sh",".html",".css",
    ".yml",".yaml",".toml",".ini",".env.example",".sql",".graphql"
}

def _sha(text: str) -> str:
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
    cur.execute("CREATE INDEX IF NOT EXISTS idx_path ON files(path);")
    con.commit()
    con.close()

def index_workspace(root: str, db_path: str, max_bytes: int, extra_excludes=None):
    rootp = Path(root).resolve()
    exclude = set(extra_excludes or []) | DEFAULT_EXCLUDES
    init_db(db_path)

    con = sqlite3.connect(db_path)
    cur = con.cursor()
    count = 0

    for p in rootp.rglob("*"):
        try:
            if p.is_dir():
                if p.name in exclude:
                    continue
                continue

            # skip excluded dirs
            if any(part in exclude for part in p.parts):
                continue

            # only index text-like extensions
            ext = p.suffix.lower()
            if ext not in TEXT_EXTS:
                continue

            st = p.stat()
            rel = str(p.relative_to(rootp))

            if st.st_size > max_bytes:
                content = f"[SKIPPED large file: {st.st_size} bytes]"
            else:
                content = p.read_text(errors="ignore")

            sha = _sha(content)

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

def search(db_path: str, q: str, limit: int = 12):
    if not Path(db_path).exists():
        return []
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    q2 = f"%{q}%"
    cur.execute("""
      SELECT path, substr(content, 1, 1400)
      FROM files
      WHERE path LIKE ? OR content LIKE ?
      LIMIT ?
    """, (q2, q2, limit))
    rows = cur.fetchall()
    con.close()
    return [{"path": r[0], "snippet": r[1]} for r in rows]
