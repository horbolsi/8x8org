PATCH064 - Full Merge (source_code(2).zip + patch063_full_merge)

What this patch installs
- apps/dashboard/frontend : full Vite frontend source (merged)
- apps/dashboard/templates/sovereign_full.html : SPA entry (from dist/index.html) with /assets fix
- apps/dashboard/static/assets/* : built assets
- apps/dashboard/static/yw_manifest.json : optional build manifest
- scripts/build_spa_frontend.sh : safe Termux build (builds in internal tmp to avoid EACCES symlink)
- patches/fix064_apply_full_merge.sh : installer that backs up + patches server routes for /assets and /

How to apply
1) Copy patch064_full_merge.zip into repo: patches/patch064_full_merge.zip
2) Run:
   bash patches/fix064_apply_full_merge.sh
3) Start:
   python sovereign_dashboard_full.py

Notes
- If you see 404 requests like /assets/assets/..., the installer rewrites sovereign_full.html to fix it.
- If npm build fails on shared storage, run: bash scripts/build_spa_frontend.sh
