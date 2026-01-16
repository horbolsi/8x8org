#!/data/data/com.termux/files/usr/bin/bash
set -e

cd ~/storage/shared/Workspace

# Write README.md safely without heredocs
: > README.md
printf "%s\n" "# Workspace Mirror (Android/Termux)" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "This repository mirrors my Android shared storage workspace structure:" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "- \`repos/\` — source code repositories (main project: \`repos/8x8org\`)" >> README.md
printf "%s\n" "- \`projects/\` — runtime/project data (usually not committed)" >> README.md
printf "%s\n" "- \`logs/\` — logs (not committed)" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "## Main app: 8x8org Sovereign Dashboard" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "Path: \`repos/8x8org\`" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "### Quick start (Termux)" >> README.md
printf "%s\n" "\`\`\`bash" >> README.md
printf "%s\n" "cd ~/storage/shared/Workspace/repos/8x8org" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "python -m venv ~/.venvs/8x8org" >> README.md
printf "%s\n" "source ~/.venvs/8x8org/bin/activate" >> README.md
printf "%s\n" "pip install -r requirements.txt" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "./tools/dev dash:start" >> README.md
printf "%s\n" "./tools/dev open" >> README.md
printf "%s\n" "\`\`\`" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "### Update the GitHub mirror" >> README.md
printf "%s\n" "From the Workspace root:" >> README.md
printf "%s\n" "\`\`\`bash" >> README.md
printf "%s\n" "cd ~/storage/shared/Workspace" >> README.md
printf "%s\n" "git add -A" >> README.md
printf "%s\n" "git commit -m \"update\"" >> README.md
printf "%s\n" "git push" >> README.md
printf "%s\n" "\`\`\`" >> README.md
printf "%s\n" "" >> README.md
printf "%s\n" "## Notes" >> README.md
printf "%s\n" "- Secrets and SSH keys should never be committed." >> README.md
printf "%s\n" "- Large runtime logs and databases are ignored by \`.gitignore\`." >> README.md

git add README.md
git commit -m "Add Workspace README" || true
git push
