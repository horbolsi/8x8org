Patch 063 - Merge legacy dashboard (patch060) + SPA source (patch061)

What it does:
- Restores the legacy 'full' dashboard as the default at /
- Adds a new SPA frontend at /spa (build with scripts/build_spa_frontend.sh)
- Serves legacy assets at /assets/* and SPA assets at /spa_assets/*

Usage (from repo root):
  bash patches/fix063_apply_full_merge.sh
  bash scripts/build_spa_frontend.sh   # optional, to build /spa
  python sovereign_dashboard_full.py

