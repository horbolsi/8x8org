# 8x8org Workflow (Termux-first)

## Canonical entrypoints
- Dashboard: `python apps/dashboard/server.py`
- Bot: `python services/bot/telegram_webapp_bot.py`

## One command dev tool
- `./tools/dev status`
- `./tools/dev dash:start` (runs in background, log in `runtime/dashboard.out`)
- `./tools/dev dash:stop`
- `./tools/dev bot:start`
- `./tools/dev bot:stop`

## Editing on phone
Your repo lives in:
`/storage/emulated/0/Workspace/repos/8x8org`

Use Samsung Files to edit, then restart:
`./tools/dev dash:stop && ./tools/dev dash:start`

## Notes
- Keep runtime outputs in `runtime/`
- Keep old experiments in `archive/`
