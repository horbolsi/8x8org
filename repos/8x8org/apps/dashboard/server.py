"""
apps/dashboard/server.py

Sovereign Dashboard server (portable: Replit + Termux).
- Flask + Flask-SocketIO
- SQLite storage
- Minimal, stable schema init
- Admin bootstrap
- System status endpoint

This file is intentionally "boring": correctness + portability > complexity.
"""

from __future__ import annotations

import json
import os
import sqlite3
import time
import traceback
from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

try:
    import psutil
except ImportError:
    psutil = None

import requests
from cryptography.fernet import Fernet
from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_from_directory, Blueprint, render_template
from flask_socketio import SocketIO, emit

# Legacy full dashboard (pre-YouWare SPA) served at /legacy
legacy_bp = Blueprint("legacy", __name__)

@legacy_bp.get("/legacy")
def legacy_dashboard():
    return render_template("sovereign_full_legacy.html")


# Vite/YouWare build assets
ASSETS_DIR = os.path.join(os.path.dirname(__file__), 'static', 'assets')

assets_bp = Blueprint("assets_bp", __name__)

@assets_bp.get("/assets/<path:filename>")
def serve_assets(filename):
    return send_from_directory(ASSETS_DIR, filename)



APP_NAME = "Sovereign Dashboard"
APP_VERSION = "4.0.1-portable"

# Load .env if present (works on Replit + Termux)
load_dotenv()


def utc_now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def sha256_hex(s: str) -> str:
    return sha256(s.encode("utf-8")).hexdigest()


def _repo_root() -> Path:
    # repos/8x8org/apps/dashboard/server.py -> repo root is 3 parents up
    return Path(__file__).resolve().parents[2]


def _workspace_root() -> Path:
    # Prefer explicit env if user sets it
    env = os.getenv("WORKSPACE_ROOT", "").strip()
    if env:
        return Path(env).expanduser().resolve()
    # If running from the workspace-mirror repo, this is okay; else fallback to repo root.
    return _repo_root().resolve()


def _projects_dir() -> Path:
    # Mirror your Termux convention but stay portable on Replit.
    ws = _workspace_root()
    p = ws / "projects" / "sovereign_ai_master"
    p.mkdir(parents=True, exist_ok=True)
    (p / "logs").mkdir(parents=True, exist_ok=True)
    return p


def _db_path() -> Path:
    return _projects_dir() / "dashboard.db"


def _log_path() -> Path:
    return _projects_dir() / "logs" / "dashboard_server.log"


def log_line(level: str, msg: str) -> None:
    line = f"{utc_now_iso()} [{level}] {msg}\n"
    try:
        _log_path().parent.mkdir(parents=True, exist_ok=True)
        _log_path().write_text(_log_path().read_text(encoding="utf-8", errors="ignore") + line, encoding="utf-8")
    except Exception:
        # Last resort: don't crash logging
        pass
    print(line, end="")


def db_connect() -> sqlite3.Connection:
    dbp = _db_path()
    dbp.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(dbp), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


ADMIN_USER = os.getenv("ADMIN_USER", "admin").strip() or "admin"
ADMIN_PASS = os.getenv("ADMIN_PASS", "admin").strip() or "admin"


def db_init() -> None:
    """
    Initialize SQLite schema and ensure an admin user exists.
    Portable, SQLite-safe SQL only.
    """
    conn = db_connect()
    try:
        cur = conn.cursor()
        cur.executescript(
            """
            PRAGMA foreign_keys = OFF;

            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT UNIQUE NOT NULL,
              email TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              is_admin INTEGER NOT NULL DEFAULT 0,
              is_verified INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS server_secrets (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS user_layout (
              user_id INTEGER PRIMARY KEY,
              layout_json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS social_links (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              platform TEXT NOT NULL,
              url TEXT NOT NULL,
              created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS verification_requests (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending'
            );
            """
        )
        conn.commit()

        admin_hash = sha256_hex(f"{ADMIN_USER}:{ADMIN_PASS}")
        cur.execute("SELECT id FROM users WHERE username = ?", (ADMIN_USER,))
        row = cur.fetchone()
        if not row:
            cur.execute(
                "INSERT INTO users(username, email, password_hash, is_admin, is_verified, created_at) "
                "VALUES(?, ?, ?, 1, 1, ?)",
                (ADMIN_USER, "admin@local", admin_hash, utc_now_iso()),
            )
            conn.commit()
            log_line("INFO", f"Bootstrapped admin user '{ADMIN_USER}'")
    finally:
        conn.close()


def db_get_secret(key: str) -> Optional[str]:
    conn = db_connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT value FROM server_secrets WHERE key = ?", (key,))
        row = cur.fetchone()
        return str(row["value"]) if row else None
    finally:
        conn.close()


def db_set_secret(key: str, value: str) -> None:
    conn = db_connect()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO server_secrets(key, value, updated_at)
            VALUES(?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
              value=excluded.value,
              updated_at=excluded.updated_at
            """,
            (key, value, utc_now_iso()),
        )
        conn.commit()
    finally:
        conn.close()


def wallet_fernet() -> Fernet:
    """
    Encryption key for storing secrets at rest.
    Prefer env var SOVEREIGN_WALLET_KEY; else store a generated one in DB.
    """
    env_key = os.getenv("SOVEREIGN_WALLET_KEY", "").strip()
    if env_key:
        try:
            return Fernet(env_key.encode("utf-8"))
        except Exception:
            log_line("WARN", "Invalid SOVEREIGN_WALLET_KEY; falling back to DB key")

    stored = db_get_secret("wallet_fernet_key")
    if stored:
        return Fernet(stored.encode("utf-8"))

    new_key = Fernet.generate_key().decode("utf-8")
    db_set_secret("wallet_fernet_key", new_key)
    log_line("WARN", "Generated local wallet key (stored in DB). Set SOVEREIGN_WALLET_KEY for portability.")
    return Fernet(new_key.encode("utf-8"))


@dataclass
class CacheEntry:
    ts: float
    data: Any


CACHE: Dict[str, CacheEntry] = {}
CACHE_TTL_SECONDS = 45.0


def cache_get(key: str) -> Optional[Any]:
    ent = CACHE.get(key)
    if not ent:
        return None
    if time.time() - ent.ts > CACHE_TTL_SECONDS:
        return None
    return ent.data


def cache_set(key: str, data: Any) -> None:
    CACHE[key] = CacheEntry(ts=time.time(), data=data)


def fetch_json(url: str, timeout: float = 10.0) -> Any:
    try:
        r = requests.get(
            url,
            timeout=timeout,
            headers={"User-Agent": f"{APP_NAME}/{APP_VERSION}"},
        )
        r.raise_for_status()
        return r.json()
    except Exception:
        return {}


def system_status():
    """
    Best-effort system status for Termux/Android/Replit.
    """
    import os, shutil, time
    st = {
        "app": {
            "name": os.getenv("APP_NAME", "Sovereign Dashboard"),
            "version": os.getenv("APP_VERSION", "4.0.1-portable"),
        },
        "time_utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
        "replit": os.getenv("REPLIT_DEV_DOMAIN") is not None,
        "warnings": [],

        # flat fields (used by sockets + new dashboard template)
        "cpu_percent": None,
        "mem_percent": None,
        "disk_percent": None,
        "proc_count": None,
        "net": {"bytes_sent": None, "bytes_recv": None},

        # nested fields (older home() html expects these)
        "cpu": {"percent": None},
        "mem": {"percent": None, "total": None, "available": None},
        "disk": {"percent": None, "total": None, "free": None},
    }

    # CPU
    if psutil:
        try:
            pct = psutil.cpu_percent(interval=0.0)
            st["cpu_percent"] = pct
            st["cpu"]["percent"] = pct
        except Exception as e:
            st["warnings"].append("cpu:" + type(e).__name__)

    # Memory
    if psutil:
        try:
            vm = psutil.virtual_memory()
            st["mem_percent"] = vm.percent
            st["mem"]["percent"] = vm.percent
            st["mem"]["total"] = int(getattr(vm, "total", 0) or 0)
            st["mem"]["available"] = int(getattr(vm, "available", 0) or 0)
        except Exception as e:
            st["warnings"].append("mem:" + type(e).__name__)

    # Disk (use shutil: works better on Android)
    try:
        du = shutil.disk_usage(os.getcwd())
        dp = round((1 - (du.free / du.total)) * 100, 1) if du.total else None
        st["disk_percent"] = dp
        st["disk"]["percent"] = dp
        st["disk"]["total"] = int(du.total)
        st["disk"]["free"] = int(du.free)
    except Exception as e:
        st["warnings"].append("disk:" + type(e).__name__)

    # Process count
    if psutil:
        try:
            st["proc_count"] = len(psutil.pids())
        except Exception as e:
            st["warnings"].append("proc:" + type(e).__name__)

    # Net
    if psutil:
        try:
            nio = psutil.net_io_counters()
            st["net"] = {"bytes_sent": int(nio.bytes_sent), "bytes_recv": int(nio.bytes_recv)}
        except Exception as e:
            st["warnings"].append("net:" + type(e).__name__)

    return st


def create_app() -> Tuple[Flask, SocketIO]:
    app = Flask(__name__)
    app.register_blueprint(legacy_bp)

# Legacy full dashboard (pre-YouWare SPA)

    app.register_blueprint(assets_bp)

    # --- ensure create_app returns (app, socketio) ---

    # Home page
    @app.get("/")
    def home():
        # Prefer the YouWare/Vite template; fallback to legacy
        try:
            return render_template("sovereign_full.html")
        except Exception:
            return render_template("dashboard.html")

    return app, locals().get('socketio')





def main() -> None:
    """
    Entry point used by sovereign_dashboard_full.py.
    Env:
      PORT (default 5000)
      HOST (default 127.0.0.1)
    """
    host = os.getenv("SOVEREIGN_HOST", "0.0.0.0").strip() or "0.0.0.0"
    port = int(os.getenv("SOVEREIGN_PORT", os.getenv("PORT", "5000")))

    # Update WEBAPP_URL if on Replit
    replit_domain = os.getenv("REPLIT_DEV_DOMAIN")
    if replit_domain:
        webapp_url = f"https://{replit_domain}"
        # Only log it, don't overwrite .env to avoid leaks, but the app can use it
        log_line("INFO", f"Replit detected, WEBAPP_URL set to {webapp_url}")

    db_init()
    wallet_fernet()  # ensure key exists early

    app, socketio = create_app()

    log_line("INFO", f"✅ {APP_NAME} v{APP_VERSION}")
    log_line("INFO", f"   Workspace: {_workspace_root()}")
    log_line("INFO", f"   DB: {_db_path()}")
    log_line("INFO", f"   Logs: {_log_path()}")
    log_line("INFO", f"   URL: http://{host}:{port}")

    try:
        # SocketIO may be unavailable on some platforms (Termux/Replit)
        if socketio is None:
            app.run(host=host, port=port, debug=False)
        else:
            socketio.run(app, host=host, port=port, debug=False)

    except Exception:
        log_line("ERROR", "Server crashed:\n" + traceback.format_exc())
        raise


if __name__ == "__main__":
    main()


# --- PATCH064: routes helper (idempotent) ---
def register_patch064_routes(app):
    """Ensure root and /assets for the SPA without breaking existing routes."""
    from pathlib import Path
    assets_dir = Path(__file__).resolve().parent / 'static' / 'assets'

    has_assets = any(r.rule.startswith('/assets/') for r in app.url_map.iter_rules())
    if not has_assets:
        @app.get('/assets/<path:filename>')
        def patch064_assets(filename):
            return send_from_directory(str(assets_dir), filename)

    has_root = any(r.rule == '/' for r in app.url_map.iter_rules())
    if not has_root:
        @app.get('/')
        def patch064_root():
            return render_template('sovereign_full.html')

