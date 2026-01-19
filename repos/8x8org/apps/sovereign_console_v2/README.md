# Sovereign Console v2 (Unified)

This is the clean unified Sovereign Console v2 build:

## Features
- Admin/User auth with cookie session
- Workspace tree + file read/edit/save (admin)
- Upload/download (admin upload)
- Zip/unzip (admin)
- Terminal allowlist (admin)
- Search (ripgrep `rg`)
- Ollama models: list/status + pull/delete (admin)
- AI endpoints: text/chat/json/embed with AUTO model routing
- Jobs: plan/approve/run/rollback (minimal safe prototype)
- Audit log: runtime/logs/audit.jsonl

## Start
From repo root:

```bash
bash apps/sovereign_console_v2/start.sh

