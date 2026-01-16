# /home/oai/sovereign_dashboard_full.py
#!/usr/bin/env python3
"""
Sovereign Dashboard (Full) - Secure-by-default Termux-ready Dashboard

Features
- AI Console at top (OpenAI optional; fallback stub)
- System Resources (top-right)
- Global Chat between System Resources and Autonomous Telegram Bot
- Autonomous Telegram Bot panel (managed via status placeholders)
- Terminal panel with SAFE allowlisted commands, no shell, workspace sandbox
- File System panel under Terminal (sandboxed workspace only)
- Logs panel under File System
- Blockchain Intelligence panel (market + chains intel via CoinGecko)
- Wallet panel under Blockchain (user wallets + admin controls + verification workflow)
- Paper Trading module (demo DEX/CEX placeholders)
- Social links + widgets
- Customizable widget layout (drag/drop via GridStack) + per-user layout saved in SQLite
- Socket.IO for live updates (system metrics + logs + chat)

Run:
  export SOVEREIGN_API_KEY="set-a-long-random-key"
  export SOVEREIGN_ADMIN_USER="admin"
  export SOVEREIGN_ADMIN_PASS="change-me"
  export SOVEREIGN_WALLET_KEY="32-byte-base64-fernet-key"  # optional; auto-generated if missing (stored in DB)
  export OPENAI_API_KEY="..."  # optional
  python sovereign_dashboard_full.py

Default bind:
  http://127.0.0.1:5000
"""

from __future__ import annotations

import base64
import dataclasses
import functools
import hashlib
import io
import json
import logging
import os
# Termux note: Werkzeug is used for local dev. We silence the noisy production warning.
os.environ.setdefault('WERKZEUG_PROD_WARNING', '0')

import re
import secrets
import shlex
import sqlite3
import subprocess
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import psutil
import requests
from cryptography.fernet import Fernet
from flask import (
    Flask,
    Response,
    jsonify,
    redirect,
    render_template,
    render_template_string,
    request,
    session,
    url_for,
)
from flask_socketio import SocketIO, emit


# -----------------------------
# Config
# -----------------------------
APP_NAME = "Sovereign Dashboard Full"
APP_VERSION = "4.0.0-secure"

DEFAULT_HOST = os.getenv("SOVEREIGN_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.environ.get('PORT', os.environ.get('DASH_PORT', '5000')))
SOVEREIGN_API_KEY = os.getenv("SOVEREIGN_API_KEY", "")
ADMIN_USER = os.getenv("SOVEREIGN_ADMIN_USER", "admin")
ADMIN_PASS = os.getenv("SOVEREIGN_ADMIN_PASS", "change-me")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

HOME = Path.home()
BASE_DIR = Path(__file__).resolve().parent
SOVEREIGN_HOME = Path(os.getenv("SOVEREIGN_HOME", str(HOME / "sovereign_ai_master"))).resolve()
WORKSPACE = Path(os.getenv("SOVEREIGN_WORKSPACE", str(SOVEREIGN_HOME / "workspace"))).resolve()
LOG_DIR = Path(os.getenv("SOVEREIGN_LOG_DIR", str(SOVEREIGN_HOME / "logs"))).resolve()
DB_PATH = Path(os.getenv("SOVEREIGN_DB", str(SOVEREIGN_HOME / "dashboard.db"))).resolve()

WORKSPACE.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)
SOVEREIGN_HOME.mkdir(parents=True, exist_ok=True)

SERVER_LOG_FILE = LOG_DIR / "dashboard_server.log"

# Terminal safety
ALLOWED_COMMANDS = {
    "pwd",
    "ls",
    "cat",
    "head",
    "tail",
    "whoami",
    "id",
    "uname",
    "date",
    "python",
    "python3",
    "pip",
    "pip3",
    "git",
    "find",
    "grep",
    "wc",
    "echo",
    "touch",
    "mkdir",
    "rm",
    "cp",
    "mv",
    "sed",
}
FORBIDDEN_SHELL_CHARS = set(";|&><`$\\\n\r")


# -----------------------------
# Small utilities
# -----------------------------
def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def log_line(level: str, msg: str, extra: Optional[Dict[str, Any]] = None) -> None:
    record = {
        "ts": utc_now_iso(),
        "level": level.upper(),
        "msg": msg,
        "extra": extra or {},
    }
    line = json.dumps(record, ensure_ascii=False)
    try:
        SERVER_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with SERVER_LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def require_api_key(fn):
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        # Browser session auth is primary; API key protects server-to-server use.
        if session.get("user_id"):
            return fn(*args, **kwargs)

        if not SOVEREIGN_API_KEY:
            return jsonify({"error": "Server misconfigured: SOVEREIGN_API_KEY not set"}), 500
        provided = request.headers.get("X-API-Key", "")
        if provided != SOVEREIGN_API_KEY:
            return jsonify({"error": "Unauthorized"}), 401
        return fn(*args, **kwargs)

    return wrapper


def require_login(fn):
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("user_id"):
            return jsonify({"error": "Login required"}), 401
        return fn(*args, **kwargs)

    return wrapper


def require_admin(fn):
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("user_id"):
            return jsonify({"error": "Login required"}), 401
        if not session.get("is_admin"):
            return jsonify({"error": "Admin required"}), 403
        return fn(*args, **kwargs)

    return wrapper


def normalize_rel_path(p: str) -> Path:
    """
    Workspace-sandboxed paths only.
    """
    p = p.strip()
    if not p:
        return WORKSPACE
    # forbid absolute paths or traversal
    if p.startswith("/") or p.startswith(".."):
        raise ValueError("Path must be workspace-relative")
    # remove leading "./"
    p = re.sub(r"^\./+", "", p)
    target = (WORKSPACE / p).resolve()
    if WORKSPACE not in target.parents and target != WORKSPACE:
        raise ValueError("Path escapes workspace")
    return target


# -----------------------------
# SQLite store
# -----------------------------
def db_connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def db_init() -> None:
    conn = db_connect()
    cur = conn.cursor()

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT UNIQUE NOT NULL,
          email TEXT,
          password_hash TEXT NOT NULL,
          is_admin INTEGER NOT NULL DEFAULT 0,
          is_verified INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          last_login_at TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS wallets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          chain TEXT NOT NULL,
          address TEXT NOT NULL,
          enc_private_key TEXT NOT NULL,
          created_at TEXT NOT NULL,
          is_frozen INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(user_id) REFERENCES users(id)
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS layouts (
          user_id INTEGER PRIMARY KEY,
          layout_json TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY(user_id) REFERENCES users(id)
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS social_links (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          platform TEXT NOT NULL,
          url TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY(user_id) REFERENCES users(id)
        )
        """
    )
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS verification_requests (
          user_id INTEGER PRIMARY KEY,
          requested_at TEXT NOT NULL,
          note TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          FOREIGN KEY(user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS server_secrets (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
        """
    )
    conn.commit()

    # Ensure admin exists
    admin_hash = sha256_hex(f"{ADMIN_USER}:{ADMIN_PASS}")
    cur.execute("SELECT id FROM users WHERE username = ?", (ADMIN_USER,))
    row = cur.fetchone()
    if not row:
        cur.executescript(
            """
            INSERT INTO users(username, email, password_hash, is_admin, is_verified, created_at)
            VALUES(?, ?, ?, 1, 1, ?)
            """,
            (ADMIN_USER, "admin@local", admin_hash, utc_now_iso()),
        )
        conn.commit()

    conn.close()


def db_get_secret(key: str) -> Optional[str]:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT value FROM server_secrets WHERE key = ?", (key,))
    row = cur.fetchone()
    conn.close()
    return row["value"] if row else None


def db_set_secret(key: str, value: str) -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO server_secrets(key, value, updated_at)
        VALUES(?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at
        """,
        (key, value, utc_now_iso()),
    )
    conn.commit()
    conn.close()


def wallet_fernet() -> Fernet:
    """
    Encryption key for storing private keys at rest.
    Prefer env var; else persist generated key in DB (local device).
    """
    env_key = os.getenv("SOVEREIGN_WALLET_KEY", "").strip()
    if env_key:
        try:
            Fernet(env_key.encode("utf-8"))
            return Fernet(env_key.encode("utf-8"))
        except Exception:
            log_line("WARN", "Invalid SOVEREIGN_WALLET_KEY; generating local key")
    stored = db_get_secret("wallet_fernet_key")
    if stored:
        return Fernet(stored.encode("utf-8"))

    new_key = Fernet.generate_key().decode("utf-8")
    db_set_secret("wallet_fernet_key", new_key)
    log_line("WARN", "Generated local wallet key (stored in DB). Set SOVEREIGN_WALLET_KEY for portability.")
    return Fernet(new_key.encode("utf-8"))


FERNET = None  # init after db_init


# -----------------------------
# Market / chain intelligence (CoinGecko)
# -----------------------------
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
    r = requests.get(
        url,
        timeout=timeout,
        headers={"User-Agent": f"{APP_NAME}/{APP_VERSION}"},
    )
    r.raise_for_status()
    return r.json()


def coingecko_market_overview() -> Dict[str, Any]:
    """
    Market overview: global stats, top markets, trending, DeFi.
    Cached briefly to reduce API hits.
    """
    cached = cache_get("cg_overview")
    if cached:
        return cached

    global_url = "https://api.coingecko.com/api/v3/global"
    markets_url = (
        "https://api.coingecko.com/api/v3/coins/markets?"
        "vs_currency=usd&order=market_cap_desc&per_page=20&page=1&sparkline=false&price_change_percentage=1h,24h,7d"
    )
    trending_url = "https://api.coingecko.com/api/v3/search/trending"
    defi_url = "https://api.coingecko.com/api/v3/global/decentralized_finance_defi"

    out: Dict[str, Any] = {"ts": utc_now_iso()}

    try:
        out["global"] = fetch_json(global_url)
    except Exception as e:
        out["global"] = {"error": str(e)}

    try:
        out["top"] = fetch_json(markets_url)
    except Exception as e:
        out["top"] = {"error": str(e)}

    try:
        out["trending"] = fetch_json(trending_url)
    except Exception as e:
        out["trending"] = {"error": str(e)}

    try:
        out["defi"] = fetch_json(defi_url)
    except Exception as e:
        out["defi"] = {"error": str(e)}

    cache_set("cg_overview", out)
    return out


def coingecko_intel() -> Dict[str, Any]:
    """
    Enriched market intelligence derived from CoinGecko data.
    Returns: dominance, top gainers/losers (24h), volatility hints, narratives seed.
    """
    data = coingecko_market_overview()
    g = (data.get("global") or {}).get("data") or {}
    top = data.get("top") or []
    if isinstance(top, dict) and top.get("error"):
        top_list = []
    else:
        top_list = top if isinstance(top, list) else []

    # compute 24h gainers/losers from top list
    def pct(x):
        try:
            return float(x or 0.0)
        except Exception:
            return 0.0

    ranked = []
    for c in top_list:
        ranked.append(
            {
                "symbol": (c.get("symbol") or "").upper(),
                "name": c.get("name"),
                "price": c.get("current_price"),
                "mc": c.get("market_cap"),
                "rank": c.get("market_cap_rank"),
                "chg1h": pct(c.get("price_change_percentage_1h_in_currency")),
                "chg24h": pct(c.get("price_change_percentage_24h_in_currency") or c.get("price_change_percentage_24h")),
                "chg7d": pct(c.get("price_change_percentage_7d_in_currency")),
                "vol": c.get("total_volume"),
            }
        )

    gainers = sorted(ranked, key=lambda x: x["chg24h"], reverse=True)[:5]
    losers = sorted(ranked, key=lambda x: x["chg24h"])[:5]

    # dominance + high level stats
    dom = g.get("market_cap_percentage") or {}
    btc_dom = float(dom.get("btc") or 0.0)
    eth_dom = float(dom.get("eth") or 0.0)

    defi = (data.get("defi") or {}).get("data") or {}

    intel = {
        "ts": data.get("ts"),
        "global": {
            "total_market_cap_usd": (g.get("total_market_cap") or {}).get("usd"),
            "total_volume_usd": (g.get("total_volume") or {}).get("usd"),
            "mc_change_24h_pct": g.get("market_cap_change_percentage_24h_usd"),
            "btc_dominance_pct": btc_dom,
            "eth_dominance_pct": eth_dom,
            "active_cryptos": g.get("active_cryptocurrencies"),
            "markets": g.get("markets"),
        },
        "defi": {
            "defi_mc_usd": defi.get("defi_market_cap"),
            "defi_vol_24h_usd": defi.get("defi_volume_24h"),
            "defi_mc_pct": defi.get("defi_market_cap_percentage"),
            "defi_to_eth_ratio": defi.get("defi_to_eth_ratio"),
        },
        "top_gainers_24h": gainers,
        "top_losers_24h": losers,
        "trending": [
            (x.get("item") or {}).get("name")
            for x in ((data.get("trending") or {}).get("coins") or [])[:10]
        ],
        "narrative_seed": (
            "Use dominance shifts, DeFi MC%, and top gainers/losers to infer rotation, risk-on/off, "
            "and narrative momentum (memes, L2s, AI, DePIN, RWA, etc.)."
        ),
    }
    cache_set("cg_intel", intel)
    return intel

# -----------------------------
# Wallet creation (educational)
# -----------------------------
def generate_eth_wallet_educational() -> Tuple[str, str]:
    """
    Educational-only: deterministic-ish address derivation from random secret.
    Not a real secp256k1 wallet generator; this is a demo placeholder.
    """
    priv = secrets.token_hex(32)
    addr = "0x" + hashlib.sha256(priv.encode("utf-8")).hexdigest()[:40]
    return addr, priv


def generate_btc_wallet_educational() -> Tuple[str, str]:
    priv = secrets.token_hex(32)
    # Just a display address placeholder, not a real Base58Check address.
    addr = "btc_" + hashlib.sha256(priv.encode("utf-8")).hexdigest()[:34]
    return addr, priv


# -----------------------------
# Safe terminal executor
# -----------------------------
def validate_command_tokens(tokens: List[str]) -> None:
    if not tokens:
        raise ValueError("Empty command")
    cmd = tokens[0]
    if cmd not in ALLOWED_COMMANDS:
        raise ValueError(f"Command not allowed: {cmd}")

    raw = " ".join(tokens)
    if any(ch in FORBIDDEN_SHELL_CHARS for ch in raw):
        raise ValueError("Forbidden shell characters detected")

    # forbid pipes/redirection forms (even if chars missed)
    for t in tokens:
        if any(ch in t for ch in ["|", ">", "<", ";", "&", "`", "$"]):
            raise ValueError("Forbidden token detected")

    # workspace-only file args for mutating commands
    mutating = {"rm", "mv", "cp", "touch", "mkdir", "sed"}
    if cmd in mutating:
        for arg in tokens[1:]:
            if arg.startswith("-"):
                continue
            # normalize path and enforce workspace
            _ = normalize_rel_path(arg)


def run_safe_command(command: str) -> Dict[str, Any]:
    tokens = shlex.split(command.strip())
    validate_command_tokens(tokens)

    # enforce workspace as cwd
    cwd = str(WORKSPACE)

    # map common "ls" usage: default to workspace root
    if tokens[0] == "ls" and len(tokens) == 1:
        tokens.append(".")

    # normalize file arguments to workspace-relative
    norm_tokens = [tokens[0]]
    for arg in tokens[1:]:
        if arg.startswith("-"):
            norm_tokens.append(arg)
            continue
        if tokens[0] in {"pwd", "whoami", "id", "uname", "date", "echo"}:
            norm_tokens.append(arg)
            continue
        try:
            p = normalize_rel_path(arg)
            norm_tokens.append(str(p))
        except Exception:
            # allow non-path args (like grep pattern)
            norm_tokens.append(arg)

    started = time.time()
    proc = subprocess.run(
        norm_tokens,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=12,
        shell=False,
    )
    elapsed = time.time() - started

    return {
        "cmd": command,
        "argv": norm_tokens,
        "returncode": proc.returncode,
        "stdout": proc.stdout[-20000:],
        "stderr": proc.stderr[-20000:],
        "elapsed_ms": int(elapsed * 1000),
    }


# -----------------------------
# Flask app
# -----------------------------
app = Flask(__name__, template_folder=str(BASE_DIR / 'templates'))
app.secret_key = os.getenv("SOVEREIGN_FLASK_SECRET", secrets.token_hex(32))
socketio = SocketIO(app, async_mode='threading', cors_allowed_origins='*', logger=False, engineio_logger=False)  # no wildcard cors


# -----------------------------
# Background broadcaster
# -----------------------------
def system_snapshot() -> Dict[str, Any]:
    try:
        cpu = psutil.cpu_percent(interval=0.2)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage(str(WORKSPACE))
        net = psutil.net_io_counters()
        return {
            "ts": utc_now_iso(),
            "cpu_percent": cpu,
            "mem_percent": mem.percent,
            "mem_used": mem.used,
            "mem_total": mem.total,
            "disk_percent": disk.percent,
            "disk_used": disk.used,
            "disk_total": disk.total,
            "proc_count": len(psutil.pids()),
            "net": {"bytes_sent": net.bytes_sent, "bytes_recv": net.bytes_recv},
        }
    except Exception as e:
        return {"ts": utc_now_iso(), "error": str(e)}


def broadcaster_loop():
    while True:
        try:
            socketio.emit("system_update", system_snapshot())
        except Exception:
            pass
        time.sleep(2)


# -----------------------------
# Auth
# -----------------------------
def db_user_by_username(username: str) -> Optional[sqlite3.Row]:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE username = ?", (username,))
    row = cur.fetchone()
    conn.close()
    return row


def db_user_by_id(uid: int) -> Optional[sqlite3.Row]:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE id = ?", (uid,))
    row = cur.fetchone()
    conn.close()
    return row


def db_create_user(username: str, email: str, password: str) -> int:
    conn = db_connect()
    cur = conn.cursor()
    pw_hash = sha256_hex(f"{username}:{password}")
    cur.execute(
        """
        INSERT INTO users(username, email, password_hash, is_admin, is_verified, created_at)
        VALUES(?, ?, ?, 0, 0, ?)
        """,
        (username, email, pw_hash, utc_now_iso()),
    )
    conn.commit()
    uid = int(cur.lastrowid)
    conn.close()
    return uid


def db_set_user_verified(uid: int, verified: bool) -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("UPDATE users SET is_verified=? WHERE id=?", (1 if verified else 0, uid))
    conn.commit()
    conn.close()


def db_set_last_login(uid: int) -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("UPDATE users SET last_login_at=? WHERE id=?", (utc_now_iso(), uid))
    conn.commit()
    conn.close()


# -----------------------------
# Layout store
# -----------------------------
def db_get_layout(uid: int) -> Optional[Dict[str, Any]]:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT layout_json FROM layouts WHERE user_id=?", (uid,))
    row = cur.fetchone()
    conn.close()
    if not row:
        return None
    try:
        return json.loads(row["layout_json"])
    except Exception:
        return None


def db_set_layout(uid: int, layout: Dict[str, Any]) -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO layouts(user_id, layout_json, updated_at)
        VALUES(?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET layout_json=excluded.layout_json, updated_at=excluded.updated_at
        """,
        (uid, json.dumps(layout), utc_now_iso()),
    )
    conn.commit()
    conn.close()


# -----------------------------
# Wallet store
# -----------------------------
def db_user_wallets(uid: int) -> List[Dict[str, Any]]:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT * FROM wallets WHERE user_id=? ORDER BY id DESC", (uid,))
    rows = cur.fetchall()
    conn.close()
    out = []
    for r in rows:
        out.append(
            {
                "id": r["id"],
                "chain": r["chain"],
                "address": r["address"],
                "created_at": r["created_at"],
                "is_frozen": bool(r["is_frozen"]),
            }
        )
    return out


def db_create_wallet(uid: int, chain: str, address: str, private_key_plain: str) -> int:
    enc = FERNET.encrypt(private_key_plain.encode("utf-8")).decode("utf-8")
    conn = db_connect()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO wallets(user_id, chain, address, enc_private_key, created_at, is_frozen)
        VALUES(?, ?, ?, ?, ?, 0)
        """,
        (uid, chain, address, enc, utc_now_iso()),
    )
    conn.commit()
    wid = int(cur.lastrowid)
    conn.close()
    return wid


def db_admin_set_wallet_frozen(wallet_id: int, frozen: bool) -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("UPDATE wallets SET is_frozen=? WHERE id=?", (1 if frozen else 0, wallet_id))
    conn.commit()
    conn.close()


# -----------------------------
# Social links


def db_request_verification(uid: int, note: str = "") -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO verification_requests(user_id, requested_at, note, status)
        VALUES(?, ?, ?, 'pending')
        ON CONFLICT(user_id) DO UPDATE SET requested_at=excluded.requested_at, note=excluded.note, status='pending'
        """,
        (uid, utc_now_iso(), note[:400]),
    )
    conn.commit()
    conn.close()

def db_pending_verifications() -> list[dict]:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute(
        """
        SELECT u.id, u.username, vr.requested_at, vr.note
        FROM verification_requests vr
        JOIN users u ON u.id = vr.user_id
        WHERE vr.status='pending'
        ORDER BY vr.requested_at DESC
        LIMIT 200
        """
    )
    rows = cur.fetchall()
    conn.close()
    return [dict(r) for r in rows]

def db_mark_verification_done(uid: int) -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("UPDATE verification_requests SET status='done' WHERE user_id=?", (uid,))
    conn.commit()
    conn.close()


# -----------------------------
def db_list_social(uid: int) -> List[Dict[str, str]]:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT platform,url FROM social_links WHERE user_id=? ORDER BY id DESC", (uid,))
    rows = cur.fetchall()
    conn.close()
    return [{"platform": r["platform"], "url": r["url"]} for r in rows]


def db_add_social(uid: int, platform: str, url: str) -> None:
    conn = db_connect()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO social_links(user_id, platform, url, created_at) VALUES(?,?,?,?)",
        (uid, platform, url, utc_now_iso()),
    )
    conn.commit()
    conn.close()


# -----------------------------
# AI (optional OpenAI)
# -----------------------------
def ai_reply(prompt: str) -> str:
    prompt = (prompt or "").strip()
    if not prompt:
        return "Say something 🙂"

    # If OpenAI key exists, try OpenAI SDK v1+ (best effort)
    if OPENAI_API_KEY:
        try:
            from openai import OpenAI  # type: ignore

            client = OpenAI(api_key=OPENAI_API_KEY)
            resp = client.chat.completions.create(
                model=os.getenv("SOVEREIGN_AI_MODEL", "gpt-4o-mini"),
                messages=[
                    {"role": "system", "content": "You are Sovereign AI. Be helpful, concise, safe."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=600,
            )
            return resp.choices[0].message.content or ""
        except Exception as e:
            log_line("WARN", "OpenAI call failed; using stub", {"err": str(e)})

    # Stub fallback
    if "error" in prompt.lower() or "traceback" in prompt.lower():
        return "Paste the exact error + the command you ran. I’ll help debug and propose a safe fix."
    if "code" in prompt.lower():
        return "Tell me your language + goal. I’ll generate code and a minimal command sequence to run it in the terminal."
    return f"🤖 Sovereign AI (offline): I got: “{prompt[:180]}”. Ask for code, debugging, or a step-by-step plan."


# -----------------------------
# HTML (Grid layout with required placement)
# -----------------------------
PAGE_HTML = r"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>{{app_name}} • v{{app_version}}</title>

  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdn.jsdelivr.net/npm/gridstack@10.1.1/dist/gridstack-all.js"></script>
  <link href="https://cdn.jsdelivr.net/npm/gridstack@10.1.1/dist/gridstack.min.css" rel="stylesheet"/>

  <script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>

  <style>
    :root {
      --bg: #0b1020;
      --card: rgba(255,255,255,0.06);
      --border: rgba(255,255,255,0.10);
      --text: #e5e7eb;
      --muted: rgba(229,231,235,0.7);
      --accent: #8b5cf6;
      --accent2: #22c55e;
    }
    body { background: radial-gradient(1200px 600px at 10% 0%, rgba(139,92,246,0.25), transparent),
                   radial-gradient(900px 500px at 90% 10%, rgba(34,197,94,0.18), transparent),
                   var(--bg);
           color: var(--text); }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 18px; }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }
    .btn { border: 1px solid var(--border); border-radius: 12px; padding: 8px 12px; background: rgba(255,255,255,0.06); }
    .btn:hover { background: rgba(255,255,255,0.10); }
    .pill { border: 1px solid var(--border); border-radius: 999px; padding: 2px 10px; font-size: 12px; color: var(--muted); }
    .terminal { background: rgba(0,0,0,0.35); border-radius: 14px; border: 1px solid rgba(255,255,255,0.10); }
    .scroll { overflow: auto; }
    .gridstack-wrap { max-width: 1500px; margin: 0 auto; padding: 18px; }
    .gs-item-content { padding: 12px; }
    .section-title { font-weight: 700; letter-spacing: 0.02em; display:flex; align-items:center; gap:10px; }
    .subtle { color: var(--muted); }

    /* unlimited vertical scrolling (gridstack grows) */
    .grid-stack { min-height: 1200px; }
  </style>
</head>
<body>
  <div class="gridstack-wrap">
    <header class="mb-4 flex items-center justify-between">
      <div class="flex items-center gap-3">
        <div class="text-2xl font-extrabold">🚀 Sovereign</div>
        <div class="pill">Dashboard • {{app_version}}</div>
        <div class="pill" id="whoamiPill">guest</div>
        <div class="pill" id="verifyPill">unverified</div>
      </div>

      <div class="flex items-center gap-2">
        <button class="btn" onclick="toggleEdit()" id="editBtn">🔧 Layout: Locked</button>
        <button class="btn" onclick="saveLayout()">💾 Save Layout</button>
        <button class="btn" onclick="resetLayout()">↩ Reset</button>
        <button class="btn" onclick="logout()">🚪 Logout</button>
      </div>
    </header>

    <!-- GridStack -->
    <div class="grid-stack"></div>

    <footer class="mt-4 subtle text-sm">
      Security: Terminal is allowlisted • File ops are workspace-sandboxed • No public bind by default.
    </footer>
  </div>

<script>
  const socket = io({transports: ['websocket']});
  let grid;
  let editMode = false;

  // -------- Helpers
  function qs(sel){ return document.querySelector(sel); }
  function esc(s){ return (s||"").replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m])); }

  // -------- Widgets (required placement order)
  // AI on top; Global chat between System and Telegram; Terminal -> File System -> Logs;
  // Blockchain Intelligence above Wallet
  const DEFAULT_LAYOUT = [
    {id:"ai", x:0, y:0, w:12, h:5},
    {id:"sys", x:12, y:0, w:6, h:4},
    {id:"gchat", x:12, y:4, w:6, h:4},
    {id:"tbot", x:12, y:8, w:6, h:4},

    {id:"chainintel", x:0, y:5, w:12, h:6},
    {id:"wallet", x:0, y:11, w:12, h:6},
    {id:"trade", x:0, y:17, w:12, h:6},
    {id:"social", x:0, y:23, w:12, h:5},

    {id:"terminal", x:12, y:12, w:6, h:6},
    {id:"files", x:12, y:18, w:6, h:6},
    {id:"logs", x:12, y:24, w:6, h:6},
    {id:"repo", x:12, y:30, w:6, h:5},
  ];

  // -------- Render widgets
  function widgetHTML(id){
    if(id === "ai") return `
      <div class="card h-full">
        <div class="section-title mb-2">🧠 AI Console <span class="pill">central brain</span></div>
        <div class="terminal p-3 h-[240px] scroll mono text-sm" id="aiOut">> Sovereign AI ready.</div>
        <div class="mt-2 flex gap-2">
          <input class="w-full bg-black/20 border border-white/10 rounded-xl p-2 mono" id="aiIn" placeholder="Ask AI for code, debugging, plans..." />
          <button class="btn" onclick="aiSend()">Send</button>
        </div>
        <div class="mt-2 subtle text-xs">
          Tip: Ask for code → click “Run in Terminal” on the response blocks (coming next iteration).
        </div>
      </div>
    `;

    if(id === "sys") return `
      <div class="card h-full">
        <div class="section-title mb-2">📊 System Resources</div>
        <div class="grid grid-cols-2 gap-2 text-sm">
          <div class="card p-3">
            <div class="subtle">CPU</div>
            <div class="text-2xl font-bold" id="cpuPct">0%</div>
          </div>
          <div class="card p-3">
            <div class="subtle">Memory</div>
            <div class="text-2xl font-bold" id="memPct">0%</div>
          </div>
          <div class="card p-3">
            <div class="subtle">Disk</div>
            <div class="text-2xl font-bold" id="diskPct">0%</div>
          </div>
          <div class="card p-3">
            <div class="subtle">Processes</div>
            <div class="text-2xl font-bold" id="procCnt">0</div>
          </div>
        </div>
        <div class="mt-2 subtle text-xs mono" id="netStats">net: -</div>
      </div>
    `;

    if(id === "gchat") return `
      <div class="card h-full">
        <div class="section-title mb-2">🌐 Global Chat <span class="pill">community</span></div>
        <div class="terminal p-3 h-[220px] scroll mono text-sm" id="gcOut">> Connected.</div>
        <div class="mt-2 flex gap-2">
          <input class="w-full bg-black/20 border border-white/10 rounded-xl p-2 mono" id="gcIn" placeholder="Say hi..." />
          <button class="btn" onclick="gcSend()">Send</button>
        </div>
      </div>
    `;

    if(id === "tbot") return `
      <div class="card h-full">
        <div class="section-title mb-2">🤖 Autonomous Telegram Bot</div>
        <div class="subtle text-sm">
          This panel shows status + allows opt-in connection. Actual bot process management is intentionally separated for safety.
        </div>
        <div class="mt-3 card p-3 text-sm">
          <div class="flex items-center justify-between">
            <div>Bot Status</div>
            <div class="pill" id="tbotStatus">offline</div>
          </div>
          <div class="mt-2 grid grid-cols-2 gap-2">
            <button class="btn" onclick="tbotPing()">🔍 Ping</button>
            <button class="btn" onclick="tbotHowTo()">✅ Setup Steps</button>
          </div>
          <div class="mt-2 terminal p-2 mono text-xs h-[120px] scroll" id="tbotOut">> not connected</div>
        </div>
      </div>
    `;

    if(id === "terminal") return `
      <div class="card h-full">
        <div class="section-title mb-2">🧩 Terminal <span class="pill">workspace sandbox</span></div>
        <div class="terminal p-3 h-[240px] scroll mono text-sm" id="termOut">> cwd: workspace</div>
        <div class="mt-2 flex gap-2">
          <input class="w-full bg-black/20 border border-white/10 rounded-xl p-2 mono" id="termIn" placeholder="Allowed: ls, cat, git, python, pip ... (no pipes/redirection)" />
          <button class="btn" onclick="termRun()">Run</button>
        </div>
        <div class="mt-2 subtle text-xs">
          Restricted execution: allowlisted commands only • workspace paths only • no shell metacharacters.
        </div>
      </div>
    `;

    if(id === "files") return `
      <div class="card h-full">
        <div class="section-title mb-2">📁 File System <span class="pill">under terminal</span></div>
        <div class="flex gap-2 mb-2">
          <input class="w-full bg-black/20 border border-white/10 rounded-xl p-2 mono text-sm" id="fsPath" value="." />
          <button class="btn" onclick="fsList()">Go</button>
          <button class="btn" onclick="fsUp()">Up</button>
        </div>
        <div class="terminal p-2 mono text-sm h-[260px] scroll" id="fsOut">Loading...</div>
      </div>
    `;

    if(id === "logs") return `
      <div class="card h-full">
        <div class="section-title mb-2">🧾 Logs <span class="pill">under filesystem</span></div>
        <div class="terminal p-2 mono text-xs h-[300px] scroll" id="logOut">> logs</div>
        <div class="mt-2 flex gap-2">
          <button class="btn" onclick="logRefresh()">Refresh</button>
          <button class="btn" onclick="logClearView()">Clear view</button>
        </div>
      </div>
    `;

    if(id === "repo") return `
      <div class="card h-full">
        <div class="section-title mb-2">🗂 Repo / DB Link <span class="pill">workspace</span></div>
        <div class="subtle text-sm mb-2">Git + workspace metadata. Use AI → run commands → files/logs reflect changes.</div>
        <div class="terminal p-2 mono text-xs h-[200px] scroll" id="repoOut">> repo status</div>
        <div class="mt-2 flex gap-2">
          <button class="btn" onclick="repoStatus()">git status</button>
          <button class="btn" onclick="repoTree()">ls -la</button>
        </div>
      </div>
    `;

    if(id === "chainintel") return `
      <div class="card h-full">
        <div class="section-title mb-2">⛓️ Blockchain Intelligence <span class="pill">markets + chain</span></div>

        <div class="grid grid-cols-3 gap-2">
          <div class="card p-3">
            <div class="subtle text-sm">Global Market Cap</div>
            <div class="text-xl font-bold" id="mkCap">-</div>
            <div class="subtle text-xs" id="mkCapChg">-</div>
          </div>
          <div class="card p-3">
            <div class="subtle text-sm">24h Volume</div>
            <div class="text-xl font-bold" id="mkVol">-</div>
            <div class="subtle text-xs" id="btcDom">-</div>
          </div>
          <div class="card p-3">
            <div class="subtle text-sm">Trending</div>
            <div class="text-sm mono scroll h-[54px]" id="trend">-</div>
          </div>
        </div>

        <div class="mt-3 grid grid-cols-2 gap-3">
          <div class="card p-3">
            <div class="flex items-center justify-between mb-2">
              <div class="font-semibold">Top Assets</div>
              <button class="btn text-sm" onclick="chainRefresh()">Refresh</button>
            </div>
            <div class="terminal p-2 mono text-xs h-[240px] scroll" id="topCoins">Loading...</div>
          </div>

          <div class="card p-3">
            <div class="font-semibold mb-2">Market Intelligence (AI)</div>
            <div class="subtle text-sm mb-2">
              Summaries + insights about market structure, volatility, narratives, and on-chain themes.
            </div>
            <div class="terminal p-2 mono text-xs h-[240px] scroll" id="intelOut">> Fetching intelligence...</div>
            <div class="mt-2 flex gap-2">
              <button class="btn text-sm" onclick="intelExplain()">Explain market</button>
              <button class="btn text-sm" onclick="intelRisks()">Risk notes</button>
            </div>
          </div>
        </div>
      </div>
    `;

    if(id === "wallet") return `
      <div class="card h-full">
        <div class="section-title mb-2">👛 Wallet <span class="pill">users under intelligence</span></div>

        <div class="grid grid-cols-3 gap-2 mb-3">
          <div class="card p-3">
            <div class="subtle text-sm">Account</div>
            <div class="text-sm" id="acctStatus">-</div>
          </div>
          <div class="card p-3">
            <div class="subtle text-sm">Verification</div>
            <div class="text-sm" id="verStatus">-</div>
          </div>
          <div class="card p-3">
            <div class="subtle text-sm">Wallets</div>
            <div class="text-sm" id="walletCount">-</div>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div class="card p-3">
            <div class="font-semibold mb-2">User Wallets</div>
            <div class="terminal p-2 mono text-xs h-[240px] scroll" id="walletOut">Loading...</div>
            <div class="mt-2 flex gap-2">
              <button class="btn text-sm" onclick="walletRefresh()">Refresh</button>
              <button class="btn text-sm" onclick="walletCreate()">Create Wallet (requires verification)</button>
            </div>
            <div class="mt-2 subtle text-xs">
              Verification flow: Create account → request verification → admin approves → wallet creation enabled → trading enabled.
            </div>
          </div>

          <div class="card p-3">
            <div class="font-semibold mb-2">Admin Controls</div>
            <div class="subtle text-sm mb-2">
              Admin can approve users and freeze/unfreeze wallets.
            </div>
            <div class="terminal p-2 mono text-xs h-[240px] scroll" id="adminOut">> admin panel</div>
            <div class="mt-2 flex gap-2">
              <button class="btn text-sm" onclick="adminUsers()">List Users</button>
              <button class="btn text-sm" onclick="adminWallets()">List Wallets</button>
            </div>
          </div>
        </div>
      </div>
    `;

    if(id === "trade") return `
      <div class="card h-full">
        <div class="section-title mb-2">📈 Trading <span class="pill">paper mode</span></div>
        <div class="subtle text-sm mb-2">
          This is a demo trading module: price feed + paper orders. DEX/CEX connectors are placeholders until you plug APIs (ccxt / 0x / 1inch etc).
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div class="card p-3">
            <div class="font-semibold mb-2">Price Feed</div>
            <div class="terminal p-2 mono text-xs h-[240px] scroll" id="tradePrices">Loading...</div>
            <div class="mt-2 flex gap-2">
              <button class="btn text-sm" onclick="tradeRefresh()">Refresh</button>
              <button class="btn text-sm" onclick="tradePlan()">Ask AI strategy</button>
            </div>
          </div>
          <div class="card p-3">
            <div class="font-semibold mb-2">Paper Orders</div>
            <div class="flex gap-2 mb-2">
              <input class="w-1/3 bg-black/20 border border-white/10 rounded-xl p-2 mono text-sm" id="ordSymbol" placeholder="BTC" value="BTC"/>
              <input class="w-1/3 bg-black/20 border border-white/10 rounded-xl p-2 mono text-sm" id="ordSide" placeholder="BUY/SELL" value="BUY"/>
              <input class="w-1/3 bg-black/20 border border-white/10 rounded-xl p-2 mono text-sm" id="ordQty" placeholder="Qty" value="0.01"/>
            </div>
            <button class="btn text-sm" onclick="placePaper()">Place Paper Order</button>
            <div class="terminal p-2 mono text-xs h-[200px] scroll mt-2" id="paperOut">> paper ledger</div>
          </div>
        </div>
      </div>
    `;

    if(id === "social") return `
      <div class="card h-full">
        <div class="section-title mb-2">👥 Social Platforms <span class="pill">custom</span></div>
        <div class="grid grid-cols-2 gap-3">
          <div class="card p-3">
            <div class="font-semibold mb-2">Add / Update</div>
            <div class="flex gap-2 mb-2">
              <input class="w-1/3 bg-black/20 border border-white/10 rounded-xl p-2 mono text-sm" id="socPlat" placeholder="twitter"/>
              <input class="w-2/3 bg-black/20 border border-white/10 rounded-xl p-2 mono text-sm" id="socUrl" placeholder="https://..."/>
            </div>
            <button class="btn text-sm" onclick="socialAdd()">Add</button>
            <div class="mt-2 subtle text-xs">Users can place this widget anywhere using Layout edit mode.</div>
          </div>
          <div class="card p-3">
            <div class="font-semibold mb-2">Your Links</div>
            <div class="terminal p-2 mono text-xs h-[160px] scroll" id="socOut">Loading...</div>
            <button class="btn text-sm mt-2" onclick="socialRefresh()">Refresh</button>
          </div>
        </div>
      </div>
    `;

    return `<div class="card h-full"><div class="section-title mb-2">${esc(id)}</div></div>`;
  }

  // -------- Grid init
  function buildGrid(layout){
    const el = qs(".grid-stack");
    el.innerHTML = "";
    grid = GridStack.init({
      float: true,
      cellHeight: 80,
      margin: 10,
      disableOneColumnMode: false,
      draggable: {handle: ".section-title"},
      resizable: {handles: "e, se, s, sw, w"}
    }, el);

    layout.forEach(w => {
      const node = document.createElement("div");
      node.className = "grid-stack-item";
      node.setAttribute("gs-id", w.id);
      node.setAttribute("gs-x", w.x);
      node.setAttribute("gs-y", w.y);
      node.setAttribute("gs-w", w.w);
      node.setAttribute("gs-h", w.h);
      node.innerHTML = `<div class="grid-stack-item-content gs-item-content">${widgetHTML(w.id)}</div>`;
      el.appendChild(node);
    });

    grid.load(layout);
    grid.enableMove(editMode);
    grid.enableResize(editMode);

    // initial data pulls
    chainRefresh();
    walletRefresh();
    socialRefresh();
    tradeRefresh();
    repoStatus();
    fsList();
    logRefresh();
    whoami();
  }

  function currentLayout(){
    const items = [];
    grid.engine.nodes.forEach(n => {
      items.push({id: n.el.getAttribute("gs-id"), x:n.x, y:n.y, w:n.w, h:n.h});
    });
    // stable sort by y then x
    items.sort((a,b)=> (a.y-b.y) || (a.x-b.x));
    return items;
  }

  function toggleEdit(){
    editMode = !editMode;
    grid.enableMove(editMode);
    grid.enableResize(editMode);
    qs("#editBtn").textContent = editMode ? "🔧 Layout: Editable" : "🔧 Layout: Locked";
  }

  async function saveLayout(){
    const layout = currentLayout();
    const r = await fetch("/api/layout/save", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({layout})});
    const j = await r.json();
    toast("Layout saved");
  }

  async function resetLayout(){
    await fetch("/api/layout/reset", {method:"POST"});
    buildGrid(DEFAULT_LAYOUT);
    toast("Layout reset");
  }

  function toast(msg){
    const out = qs("#logOut");
    if(out) out.textContent += `\n> ${msg}`;
  }

  async function logout(){
    await fetch("/logout", {method:"POST"});
    location.href = "/login";
  }

  // -------- Socket events
  socket.on("system_update", (data) => {
    if(qs("#cpuPct")) qs("#cpuPct").textContent = `${data.cpu_percent ?? 0}%`;
    if(qs("#memPct")) qs("#memPct").textContent = `${data.mem_percent ?? 0}%`;
    if(qs("#diskPct")) qs("#diskPct").textContent = `${data.disk_percent ?? 0}%`;
    if(qs("#procCnt")) qs("#procCnt").textContent = `${data.proc_count ?? 0}`;
    if(qs("#netStats")) qs("#netStats").textContent = `net sent=${data.net?.bytes_sent ?? 0} recv=${data.net?.bytes_recv ?? 0}`;
  });

  socket.on("log_push", (rec) => {
    const out = qs("#logOut");
    if(!out) return;
    out.textContent += `\n> [${rec.level}] ${rec.msg}`;
    out.scrollTop = out.scrollHeight;
  });

  socket.on("global_chat", (m) => {
    const out = qs("#gcOut");
    if(!out) return;
    out.textContent += `\n${m.ts} ${m.user}: ${m.text}`;
    out.scrollTop = out.scrollHeight;
  });

  // -------- AI
  async function aiSend(){
    const inp = qs("#aiIn");
    const out = qs("#aiOut");
    const text = (inp.value || "").trim();
    if(!text) return;
    out.textContent += `\n> you: ${text}`;
    inp.value = "";
    const r = await fetch("/api/ai/chat", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({prompt:text})});
    const j = await r.json();
    out.textContent += `\n> ai: ${j.response}`;
    out.scrollTop = out.scrollHeight;
  }

  // -------- Global Chat
  async function gcSend(){
    const inp = qs("#gcIn");
    const text = (inp.value || "").trim();
    if(!text) return;
    inp.value = "";
    socket.emit("global_chat_send", {text});
  }

  // -------- Telegram bot panel (status only)
  async function tbotPing(){
    const r = await fetch("/api/tbot/ping");
    const j = await r.json();
    qs("#tbotStatus").textContent = j.status || "unknown";
    qs("#tbotOut").textContent += `\n> ${JSON.stringify(j)}`;
  }
  function tbotHowTo(){
    qs("#tbotOut").textContent += `\n> Steps:
> 1) Create bot via @BotFather
> 2) Set TELEGRAM_BOT_TOKEN in env
> 3) Run bot process separately (recommended)
> 4) Connect status endpoints here (next iteration can manage PM2 safely)
`;
  }

  // -------- Terminal
  async function termRun(){
    const inp = qs("#termIn");
    const out = qs("#termOut");
    const cmd = (inp.value||"").trim();
    if(!cmd) return;
    inp.value = "";
    out.textContent += `\n$ ${cmd}`;
    const r = await fetch("/api/terminal/exec", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({cmd})});
    const j = await r.json();
    if(j.error){
      out.textContent += `\n! ${j.error}`;
    } else {
      if(j.stdout) out.textContent += `\n${j.stdout}`;
      if(j.stderr) out.textContent += `\n${j.stderr}`;
      out.textContent += `\n(rc=${j.returncode}, ${j.elapsed_ms}ms)`;
      // refresh dependent panels
      fsList();
      repoStatus();
      logRefresh();
    }
    out.scrollTop = out.scrollHeight;
  }

  // -------- Files
  async function fsList(){
    const path = (qs("#fsPath")?.value || ".").trim();
    const r = await fetch("/api/fs/list?path=" + encodeURIComponent(path));
    const j = await r.json();
    const out = qs("#fsOut");
    if(j.error){ out.textContent = `> error: ${j.error}`; return; }
    out.textContent = `> ${j.cwd}\n`;
    j.items.forEach(it => {
      out.textContent += `${it.type==="dir" ? "📁" : "📄"} ${it.name}  (${it.size} bytes)\n`;
    });
  }
  function fsUp(){
    const inp = qs("#fsPath");
    const p = (inp.value||".").replace(/\/+$/,"");
    if(p === "." || p === "") { inp.value = "."; fsList(); return; }
    const parts = p.split("/").filter(Boolean);
    parts.pop();
    inp.value = parts.length ? parts.join("/") : ".";
    fsList();
  }

  // -------- Logs
  async function logRefresh(){
    const r = await fetch("/api/logs/tail?lines=160");
    const j = await r.json();
    const out = qs("#logOut");
    if(j.error){ out.textContent = `> error: ${j.error}`; return; }
    out.textContent = j.lines.join("\n");
    out.scrollTop = out.scrollHeight;
  }
  function logClearView(){
    qs("#logOut").textContent = "> cleared";
  }

  // -------- Repo panel
  async function repoStatus(){
    const r = await fetch("/api/repo/status");
    const j = await r.json();
    qs("#repoOut").textContent = j.text || JSON.stringify(j);
  }
  async function repoTree(){
    const r = await fetch("/api/fs/list?path=.");
    const j = await r.json();
    qs("#repoOut").textContent = JSON.stringify(j, null, 2);
  }

  // -------- Chain intelligence
  function fmtUSD(n){
    if(n == null) return "-";
    const x = Number(n);
    if(!isFinite(x)) return "-";
    if(x >= 1e12) return (x/1e12).toFixed(2)+"T";
    if(x >= 1e9) return (x/1e9).toFixed(2)+"B";
    if(x >= 1e6) return (x/1e6).toFixed(2)+"M";
    return x.toFixed(2);
  }

  async function chainRefresh(){
    const r = await fetch("/api/chain/overview");
    const j = await r.json();
    if(j.error) return;

    const g = j.global?.data || {};
    qs("#mkCap").textContent = "$" + fmtUSD(g.total_market_cap?.usd);
    qs("#mkVol").textContent = "$" + fmtUSD(g.total_volume?.usd);
    qs("#mkCapChg").textContent = `MC 24h: ${Number(g.market_cap_change_percentage_24h_usd || 0).toFixed(2)}%`;
    qs("#btcDom").textContent = `BTC dom: ${Number(g.market_cap_percentage?.btc || 0).toFixed(2)}%`;

    const trendCoins = (j.trending?.coins || []).slice(0, 7).map(c => c.item?.name).filter(Boolean);
    qs("#trend").textContent = trendCoins.length ? trendCoins.join(", ") : "-";

    const top = (j.top || []);
    let txt = "";
    top.forEach(c => {
      txt += `${c.market_cap_rank}. ${c.symbol.toUpperCase()}  $${c.current_price}  24h:${(c.price_change_percentage_24h||0).toFixed(2)}%  mc:$${fmtUSD(c.market_cap)}\n`;
    });
    qs("#topCoins").textContent = txt || "No data";

    // seed intel panel
    qs("#intelOut").textContent = `> Market snapshot:
> Total MC: $${fmtUSD(g.total_market_cap?.usd)}
> 24h Vol: $${fmtUSD(g.total_volume?.usd)}
> BTC Dom: ${(g.market_cap_percentage?.btc||0).toFixed(2)}%
> Ask AI below for narrative + risk notes.`;
  }

  async function intelExplain(){
    const seed = qs("#intelOut").textContent.slice(-1200);
    const r = await fetch("/api/ai/chat", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({prompt:
      "Summarize current crypto market conditions from this snapshot and suggest what to watch next:\\n" + seed
    })});
    const j = await r.json();
    qs("#intelOut").textContent += `\n\n> AI: ${j.response}`;
  }

  async function intelRisks(){
    const r = await fetch("/api/ai/chat", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({prompt:
      "List major risks users should consider in crypto markets (volatility, custody, scams) and 5 safety rules."
    })});
    const j = await r.json();
    qs("#intelOut").textContent += `\n\n> AI: ${j.response}`;
  }

  // -------- Wallet panel
  async function whoami(){
    const r = await fetch("/api/me");
    const j = await r.json();
    qs("#whoamiPill").textContent = j.username ? `@${j.username}` : "guest";
    qs("#verifyPill").textContent = j.is_verified ? "verified" : "unverified";
    qs("#acctStatus").textContent = j.username ? `@${j.username}` : "-";
    qs("#verStatus").textContent = j.is_verified ? "✅ Verified" : "⏳ Pending (request admin approval)";
  }

  async function walletRefresh(){
    const r = await fetch("/api/wallet/list");
    const j = await r.json();
    const out = qs("#walletOut");
    if(j.error){ out.textContent = `> error: ${j.error}`; return; }
    qs("#walletCount").textContent = `${(j.wallets||[]).length}`;
    out.textContent = "> Your wallets:\n";
    (j.wallets||[]).forEach(w => {
      out.textContent += `- #${w.id} ${w.chain} ${w.address} frozen=${w.is_frozen}\n`;
    });
    if(!(j.wallets||[]).length) out.textContent += "- none\n";
    whoami();
  }

  async function walletCreate(){
    const chain = prompt("Chain? (eth/btc)","eth");
    if(!chain) return;
    const r = await fetch("/api/wallet/create", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({chain})});
    const j = await r.json();
    if(j.error) alert(j.error);
    walletRefresh();
    logRefresh();
  }

  async function adminUsers(){
    const r = await fetch("/api/admin/users");
    const j = await r.json();
    qs("#adminOut").textContent = JSON.stringify(j, null, 2);
    if(j.users && j.users.length){
      const uid = prompt("Approve a user? Enter user_id or cancel","");
      if(uid){
        await fetch("/api/admin/verify_user", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({user_id:Number(uid), verified:true})});
        toast("User verified");
      }
    }
  }

  async function adminWallets(){
    const r = await fetch("/api/admin/wallets");
    const j = await r.json();
    qs("#adminOut").textContent = JSON.stringify(j, null, 2);
    const wid = prompt("Freeze/unfreeze wallet? Enter wallet_id or cancel","");
    if(wid){
      const action = prompt("Type freeze or unfreeze","freeze");
      await fetch("/api/admin/wallet_freeze", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({wallet_id:Number(wid), frozen: action==="freeze"})});
      toast("Wallet updated");
      walletRefresh();
    }
  }

  // -------- Trading
  let paperLedger = [];
  async function tradeRefresh(){
    const r = await fetch("/api/chain/prices");
    const j = await r.json();
    const out = qs("#tradePrices");
    if(j.error){ out.textContent = `> error: ${j.error}`; return; }
    let txt = "> Prices (USD):\n";
    (j.items||[]).forEach(p => {
      txt += `- ${p.symbol}: $${p.price}  24h:${p.chg24h}%\n`;
    });
    out.textContent = txt;
  }
  async function tradePlan(){
    const snap = qs("#tradePrices").textContent.slice(-1200);
    const r = await fetch("/api/ai/chat", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({prompt:
      "Given this price snapshot, propose a conservative paper-trading plan (not financial advice). Include risk controls:\\n" + snap
    })});
    const j = await r.json();
    qs("#paperOut").textContent += `\n> AI Plan: ${j.response}\n`;
  }
  function placePaper(){
    const sym = (qs("#ordSymbol").value||"").toUpperCase().trim();
    const side = (qs("#ordSide").value||"BUY").toUpperCase().trim();
    const qty = (qs("#ordQty").value||"").trim();
    const rec = {ts:new Date().toISOString(), sym, side, qty};
    paperLedger.push(rec);
    qs("#paperOut").textContent = "> paper ledger\n" + paperLedger.map(x => `${x.ts} ${x.side} ${x.qty} ${x.sym}`).join("\n");
  }

  // -------- Social
  async function socialRefresh(){
    const r = await fetch("/api/social/list");
    const j = await r.json();
    const out = qs("#socOut");
    if(j.error){ out.textContent = `> error: ${j.error}`; return; }
    out.textContent = "> links:\n";
    (j.links||[]).forEach(l => out.textContent += `- ${l.platform}: ${l.url}\n`);
    if(!(j.links||[]).length) out.textContent += "- none\n";
  }
  async function socialAdd(){
    const platform = (qs("#socPlat").value||"").trim();
    const url = (qs("#socUrl").value||"").trim();
    if(!platform || !url) return alert("platform + url required");
    await fetch("/api/social/add", {method:"POST", headers:{'Content-Type':'application/json'}, body: JSON.stringify({platform, url})});
    qs("#socPlat").value = ""; qs("#socUrl").value = "";
    socialRefresh();
  }

  // -------- Init: load server layout if present
  async function init(){
    const r = await fetch("/api/layout/load");
    const j = await r.json();
    if(j.layout && j.layout.length){
      buildGrid(j.layout);
    } else {
      buildGrid(DEFAULT_LAYOUT);
    }
  }
  init();
</script>
</body>
</html>
"""


LOGIN_HTML = r"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <script src="https://cdn.tailwindcss.com"></script>
  <title>Login • Sovereign</title>
  <style>
    body { background: #0b1020; color: #e5e7eb; }
    .card { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.10); border-radius: 18px; }
  </style>
</head>
<body class="min-h-screen flex items-center justify-center p-6">
  <div class="card p-6 w-full max-w-lg">
    <div class="text-2xl font-extrabold mb-2">🚀 Sovereign</div>
    <div class="text-sm opacity-80 mb-4">Login or create an account. Verification unlocks wallet + trading.</div>

    {% if error %}
      <div class="mb-3 p-3 bg-red-500/20 border border-red-500/30 rounded-xl">{{error}}</div>
    {% endif %}

    <form method="POST" action="/login" class="space-y-3">
      <input name="username" class="w-full p-3 rounded-xl bg-black/20 border border-white/10" placeholder="username" required />
      <input name="password" type="password" class="w-full p-3 rounded-xl bg-black/20 border border-white/10" placeholder="password" required />
      <button class="w-full p-3 rounded-xl bg-purple-600 hover:bg-purple-700 font-semibold">Login</button>
    </form>

    <div class="my-4 opacity-60 text-center">or</div>

    <form method="POST" action="/register" class="space-y-3">
      <input name="username" class="w-full p-3 rounded-xl bg-black/20 border border-white/10" placeholder="new username" required />
      <input name="email" class="w-full p-3 rounded-xl bg-black/20 border border-white/10" placeholder="email (optional)" />
      <input name="password" type="password" class="w-full p-3 rounded-xl bg-black/20 border border-white/10" placeholder="new password" required />
      <button class="w-full p-3 rounded-xl bg-green-600 hover:bg-green-700 font-semibold">Create Account</button>
    </form>

    <div class="mt-4 text-xs opacity-70">
      Admin default user: <span class="font-mono">{{admin_user}}</span> (set env vars to change).
    </div>
  </div>
</body>
</html>
"""


# -----------------------------
# Routes

@app.get("/api/status")
def api_status_compat():
    return jsonify({"status": "ok", "timestamp": utc_now_iso(), "app": APP_NAME, "version": APP_VERSION})


@app.get("/api/metrics")
def api_metrics_compat():
    return jsonify({"system": system_snapshot()})

# -----------------------------
@app.get("/login")
def login_page():
    return render_template_string(LOGIN_HTML, error=None, admin_user=ADMIN_USER)


@app.post("/login")
def login_post():
    username = (request.form.get("username") or "").strip()
    password = (request.form.get("password") or "").strip()

    user = db_user_by_username(username)
    if not user:
        return render_template_string(LOGIN_HTML, error="Invalid credentials", admin_user=ADMIN_USER)

    pw_hash = sha256_hex(f"{username}:{password}")
    if pw_hash != user["password_hash"]:
        return render_template_string(LOGIN_HTML, error="Invalid credentials", admin_user=ADMIN_USER)

    session["user_id"] = int(user["id"])
    session["username"] = user["username"]
    session["is_admin"] = bool(user["is_admin"])
    session["is_verified"] = bool(user["is_verified"])
    db_set_last_login(int(user["id"]))
    log_line("INFO", "User login", {"username": username, "is_admin": session["is_admin"]})
    return redirect(url_for("index"))


@app.post("/register")
def register_post():
    username = (request.form.get("username") or "").strip()
    email = (request.form.get("email") or "").strip()
    password = (request.form.get("password") or "").strip()

    if not re.fullmatch(r"[a-zA-Z0-9_]{3,24}", username):
        return render_template_string(LOGIN_HTML, error="Username must be 3-24 chars: letters/numbers/_", admin_user=ADMIN_USER)
    if len(password) < 8:
        return render_template_string(LOGIN_HTML, error="Password must be at least 8 chars", admin_user=ADMIN_USER)

    if db_user_by_username(username):
        return render_template_string(LOGIN_HTML, error="Username already exists", admin_user=ADMIN_USER)

    uid = db_create_user(username, email, password)
    log_line("INFO", "User registered", {"username": username, "user_id": uid})

    # auto-login
    session["user_id"] = uid
    session["username"] = username
    session["is_admin"] = False
    session["is_verified"] = False
    return redirect(url_for("index"))


@app.post("/logout")
def logout_post():
    session.clear()
    return jsonify({"ok": True})


@app.get("/")
def index():
    if not session.get("user_id"):
        return redirect(url_for("login_page"))
    return render_template("sovereign_full.html", app_name=APP_NAME, app_version=APP_VERSION)


@app.get("/api/me")
@require_login
def api_me():
    uid = int(session["user_id"])
    u = db_user_by_id(uid)
    return jsonify(
        {
            "id": uid,
            "username": u["username"] if u else session.get("username"),
            "is_admin": bool(u["is_admin"]) if u else bool(session.get("is_admin")),
            "is_verified": bool(u["is_verified"]) if u else bool(session.get("is_verified")),
        }
    )


# -------- Layout
@app.get("/api/layout/load")
@require_login
def api_layout_load():
    uid = int(session["user_id"])
    layout = db_get_layout(uid)
    return jsonify({"layout": layout.get("layout") if layout else None})


@app.post("/api/layout/save")
@require_login
def api_layout_save():
    uid = int(session["user_id"])
    data = request.get_json(force=True, silent=True) or {}
    layout = data.get("layout")
    if not isinstance(layout, list) or not layout:
        return jsonify({"error": "Invalid layout"}), 400

    # validate minimal schema
    for it in layout:
        if not isinstance(it, dict) or "id" not in it:
            return jsonify({"error": "Invalid layout item"}), 400
    db_set_layout(uid, {"layout": layout})
    log_line("INFO", "Layout saved", {"user_id": uid})
    return jsonify({"ok": True})


@app.post("/api/layout/reset")
@require_login
def api_layout_reset():
    uid = int(session["user_id"])
    db_set_layout(uid, {"layout": []})
    log_line("INFO", "Layout reset", {"user_id": uid})
    return jsonify({"ok": True})


# -------- AI
@app.post("/api/ai/chat")
@require_login
def api_ai_chat():
    data = request.get_json(force=True, silent=True) or {}
    prompt = (data.get("prompt") or "").strip()
    resp = ai_reply(prompt)
    log_line("INFO", "AI chat", {"user": session.get("username"), "prompt": prompt[:120]})
    return jsonify({"response": resp})


# -------- Terminal
@app.post("/api/terminal/exec")
@require_login
def api_terminal_exec():
    data = request.get_json(force=True, silent=True) or {}
    cmd = (data.get("cmd") or "").strip()
    if not cmd:
        return jsonify({"error": "Empty command"}), 400

    try:
        result = run_safe_command(cmd)
        log_line("INFO", "Terminal exec", {"user": session.get("username"), "cmd": cmd})
        return jsonify(result)
    except Exception as e:
        log_line("WARN", "Terminal blocked", {"user": session.get("username"), "cmd": cmd, "err": str(e)})
        return jsonify({"error": str(e)}), 400


# -------- Filesystem (workspace only)
@app.get("/api/fs/list")
@require_login
def api_fs_list():
    path = (request.args.get("path") or ".").strip()
    try:
        target = normalize_rel_path(path)
        if not target.exists():
            return jsonify({"error": "Not found"}), 404
        if not target.is_dir():
            target = target.parent

        items = []
        for p in sorted(target.iterdir(), key=lambda x: (x.is_file(), x.name.lower())):
            try:
                st = p.stat()
                items.append(
                    {
                        "name": p.name,
                        "type": "dir" if p.is_dir() else "file",
                        "size": int(st.st_size),
                        "mtime": int(st.st_mtime),
                    }
                )
            except Exception:
                continue
        rel = "." if target == WORKSPACE else str(target.relative_to(WORKSPACE))
        return jsonify({"cwd": rel, "items": items})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


# -------- Logs
@app.get("/api/logs/tail")
@require_login
def api_logs_tail():
    lines = int(request.args.get("lines") or "120")
    lines = max(20, min(lines, 1000))

    try:
        if not SERVER_LOG_FILE.exists():
            return jsonify({"lines": ["> no logs yet"]})
        data = SERVER_LOG_FILE.read_text(encoding="utf-8", errors="ignore").splitlines()[-lines:]
        return jsonify({"lines": data})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# -------- Repo status (git optional)
@app.get("/api/repo/status")
@require_login
def api_repo_status():
    # safe: use allowlisted git
    try:
        # If workspace isn't a git repo, show helpful hints
        git_dir = WORKSPACE / ".git"
        if not git_dir.exists():
            return jsonify({"text": "> workspace is not a git repo\n> run: git init\n> or clone into workspace"})
        r = run_safe_command("git status")
        txt = (r.get("stdout") or "") + ("\n" + r.get("stderr") if r.get("stderr") else "")
        return jsonify({"text": txt.strip()})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


# -------- Chain intelligence
@app.get("/api/chain/overview")
@require_login
def api_chain_overview():
    try:
        return jsonify(coingecko_market_overview())
    except Exception as e:
        return jsonify({"error": str(e)}), 502


@app.get("/api/chain/prices")
@require_login
def api_chain_prices():
    """
    Small curated watchlist for trading module (top symbols).
    """
    try:
        data = coingecko_market_overview()
        top = data.get("top", [])[:10]
        items = []
        for c in top:
            items.append(
                {
                    "symbol": c.get("symbol", "").upper(),
                    "price": c.get("current_price"),
                    "chg24h": round(float(c.get("price_change_percentage_24h") or 0.0), 2),
                }
            )
        return jsonify({"items": items, "ts": data.get("ts")})
    except Exception as e:
        return jsonify({"error": str(e)}), 502


# -------- Wallet (verification gating)
@app.get("/api/wallet/list")
@require_login
def api_wallet_list():
    uid = int(session["user_id"])
    wallets = db_user_wallets(uid)
    user = db_user_by_id(uid)
    session["is_verified"] = bool(user["is_verified"]) if user else False
    return jsonify({"wallets": wallets, "is_verified": session["is_verified"]})


@app.post("/api/wallet/create")
@require_login
def api_wallet_create():
    uid = int(session["user_id"])
    user = db_user_by_id(uid)
    if not user:
        return jsonify({"error": "User not found"}), 404
    if not bool(user["is_verified"]):
        return jsonify({"error": "Verification required. Ask admin to approve your account."}), 403

    data = request.get_json(force=True, silent=True) or {}
    chain = (data.get("chain") or "eth").lower().strip()
    if chain not in {"eth", "btc"}:
        return jsonify({"error": "Unsupported chain (eth/btc)"}), 400

    if chain == "eth":
        addr, priv = generate_eth_wallet_educational()
    else:
        addr, priv = generate_btc_wallet_educational()

    wid = db_create_wallet(uid, chain, addr, priv)
    log_line("INFO", "Wallet created", {"user_id": uid, "chain": chain, "wallet_id": wid})
    return jsonify({"ok": True, "wallet_id": wid, "address": addr, "chain": chain})


# -------- Social
@app.get("/api/social/list")
@require_login
def api_social_list():
    uid = int(session["user_id"])
    return jsonify({"links": db_list_social(uid)})


@app.post("/api/social/add")
@require_login
def api_social_add():
    uid = int(session["user_id"])
    data = request.get_json(force=True, silent=True) or {}
    platform = (data.get("platform") or "").strip().lower()
    url = (data.get("url") or "").strip()
    if not platform or not url:
        return jsonify({"error": "platform+url required"}), 400
    if len(platform) > 32 or len(url) > 400:
        return jsonify({"error": "Too long"}), 400
    db_add_social(uid, platform, url)
    log_line("INFO", "Social link added", {"user_id": uid, "platform": platform})
    return jsonify({"ok": True})


# -------- Telegram bot status (placeholder)


@app.get("/api/chain/intel")
@require_login
def api_chain_intel():
    try:
        return jsonify(coingecko_intel())
    except Exception as e:
        return jsonify({"error": str(e)}), 502

@app.post("/api/verify/request")
@require_login
def api_verify_request():
    uid = int(session["user_id"])
    try:
        db_request_verification(uid, note="")
        log_line("INFO", "Verification requested", {"user_id": uid, "username": session.get("username")})
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.get("/api/admin/pending_verifications")
@require_admin
def api_admin_pending_verifications():
    try:
        return jsonify({"items": db_pending_verifications()})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.get("/api/tbot/ping")
@require_login
def api_tbot_ping():
    token = os.getenv("TELEGRAM_BOT_TOKEN", "")
    return jsonify(
        {
            "status": "configured" if token else "offline",
            "note": "Bot process is managed separately for safety. Next iteration can integrate PM2 safely with explicit consent.",
        }
    )


# -------- Admin APIs
@app.get("/api/admin/users")
@require_admin
def api_admin_users():
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT id,username,email,is_admin,is_verified,created_at,last_login_at FROM users ORDER BY id DESC LIMIT 200")
    rows = cur.fetchall()
    conn.close()
    users = [dict(r) for r in rows]
    return jsonify({"users": users})


@app.post("/api/admin/verify_user")
@require_admin
def api_admin_verify_user():
    data = request.get_json(force=True, silent=True) or {}
    uid = int(data.get("user_id") or 0)
    verified = bool(data.get("verified"))
    if uid <= 0:
        return jsonify({"error": "user_id required"}), 400
    db_set_user_verified(uid, verified)
    if verified:
        try:
            db_mark_verification_done(uid)
        except Exception:
            pass
    log_line("INFO", "User verification updated", {"admin": session.get("username"), "user_id": uid, "verified": verified})
    return jsonify({"ok": True})


@app.get("/api/admin/wallets")
@require_admin
def api_admin_wallets():
    conn = db_connect()
    cur = conn.cursor()
    cur.execute(
        """
        SELECT w.id, w.user_id, u.username, w.chain, w.address, w.created_at, w.is_frozen
        FROM wallets w JOIN users u ON u.id=w.user_id
        ORDER BY w.id DESC LIMIT 300
        """
    )
    rows = cur.fetchall()
    conn.close()
    return jsonify({"wallets": [dict(r) for r in rows]})


@app.post("/api/admin/wallet_freeze")
@require_admin
def api_admin_wallet_freeze():
    data = request.get_json(force=True, silent=True) or {}
    wallet_id = int(data.get("wallet_id") or 0)
    frozen = bool(data.get("frozen"))
    if wallet_id <= 0:
        return jsonify({"error": "wallet_id required"}), 400
    db_admin_set_wallet_frozen(wallet_id, frozen)
    log_line("INFO", "Wallet freeze updated", {"admin": session.get("username"), "wallet_id": wallet_id, "frozen": frozen})
    return jsonify({"ok": True})


# -----------------------------
# Global chat (Socket.IO)
# -----------------------------
@socketio.on("connect")
def sio_connect():
    emit("log_push", {"level": "INFO", "msg": "socket connected"})


@socketio.on("global_chat_send")
def sio_global_chat_send(data):
    text = (data or {}).get("text", "")
    text = re.sub(r"\s+", " ", str(text)).strip()
    if not text:
        return
    user = session.get("username") or "guest"
    msg = {"ts": datetime.now().strftime("%H:%M:%S"), "user": user, "text": text[:400]}
    socketio.emit("global_chat", msg)
    log_line("INFO", "Global chat", {"user": user, "text": text[:120]})


# -----------------------------
# Boot
# -----------------------------
def main():
    global FERNET
    db_init()
    FERNET = wallet_fernet()

    # start broadcaster
    t = threading.Thread(target=broadcaster_loop, daemon=True)
    t.start()

    log_line("INFO", "Dashboard starting", {"host": DEFAULT_HOST, "port": DEFAULT_PORT})
    print(f"✅ {APP_NAME} v{APP_VERSION}")
    print(f"   Workspace: {WORKSPACE}")
    print(f"   DB: {DB_PATH}")
    print(f"   Logs: {SERVER_LOG_FILE}")
    print(f"   URL: http://{DEFAULT_HOST}:{DEFAULT_PORT}")
    logging.getLogger('engineio').setLevel(logging.ERROR)
    logging.getLogger('socketio').setLevel(logging.ERROR)
    socketio.run(app, host=DEFAULT_HOST, port=DEFAULT_PORT, debug=False, allow_unsafe_werkzeug=True, use_reloader=False)


if __name__ == "__main__":
    main()