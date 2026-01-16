# Workspace Mirror (Android/Termux)

This repository mirrors my Android shared storage workspace structure:

- `repos/` — source code repositories (main project: `repos/8x8org`)
- `projects/` — runtime/project data (usually not committed)
- `logs/` — logs (not committed)

## Main app: 8x8org Sovereign Dashboard

Path: `repos/8x8org`

### Quick start (Termux)
```bash
cd ~/storage/shared/Workspace/repos/8x8org

python -m venv ~/.venvs/8x8org
source ~/.venvs/8x8org/bin/activate
pip install -r requirements.txt

./tools/dev dash:start
./tools/dev open
```

### Update the GitHub mirror
From the Workspace root:
```bash
cd ~/storage/shared/Workspace
git add -A
git commit -m "update"
git push
```

## Notes
- Secrets and SSH keys should never be committed.
- Large runtime logs and databases are ignored by `.gitignore`.
