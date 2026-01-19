#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

echo "==============================================="
echo "⚡ Installing Sovereign Local AI Dev Stack"
echo "   Termux + Workspace-Aware AI + Tools"
echo "==============================================="

# --- Termux safety ---
if [[ -z "${PREFIX:-}" || "$PREFIX" != /data/data/com.termux/* ]]; then
  echo "⚠️ This script is designed for Termux."
  echo "If you're on Replit/Linux, it will still work, but packages differ."
fi

# --- Updates ---
echo ""
echo "✅ Updating Termux packages..."
pkg update -y && pkg upgrade -y

# --- Core dev tools ---
echo ""
echo "✅ Installing core tools..."
pkg install -y \
  python git openssh curl wget unzip zip tar \
  clang make cmake ninja pkg-config \
  nodejs-lts \
  sqlite jq \
  ripgrep fd tree \
  tmux htop procps \
  openssl libffi

# --- Python venv ---
echo ""
echo "✅ Creating Python venv: ~/.venvs/sovereign-ai"
mkdir -p ~/.venvs
python -m venv ~/.venvs/sovereign-ai
# shellcheck disable=SC1091
source ~/.venvs/sovereign-ai/bin/activate

echo ""
echo "✅ Installing Python packages (dashboard backend + tools)..."
python -m pip install --no-input --upgrade \
  fastapi uvicorn[standard] jinja2 python-multipart aiofiles websockets \
  psutil watchdog rich python-dotenv requests \
  gitpython

# --- Optional: better CLI extras ---
python -m pip install --no-input --upgrade \
  httpx pydantic

# --- Workspace tools folder ---
mkdir -p ~/workspace/tools
cd ~/workspace/tools

# --- Install llama.cpp (local offline LLM engine) ---
echo ""
echo "✅ Installing llama.cpp (local offline AI engine)..."
if [[ ! -d llama.cpp ]]; then
  git clone --depth 1 https://github.com/ggerganov/llama.cpp.git
fi
cd llama.cpp

echo ""
echo "✅ Building llama.cpp..."
make -j2 || make

echo ""
echo "✅ llama.cpp built successfully."
echo "Binary locations:"
echo "  ./llama-server"
echo "  ./main"

# --- Create models folder ---
mkdir -p ~/workspace/models

echo ""
echo "==============================================="
echo "✅ INSTALL COMPLETE"
echo "Next steps:"
echo ""
echo "1) Put a GGUF model here:"
echo "   ~/workspace/models/"
echo ""
echo "   Example model names you can download manually:"
echo "   - TinyLlama 1.1B Chat (GGUF)"
echo "   - Phi-2 / Phi-3 mini (GGUF)"
echo "   - Mistral 7B Instruct (GGUF) [bigger]"
echo ""
echo "2) Start local model server (example):"
echo "   cd ~/workspace/tools/llama.cpp"
echo "   ./llama-server -m ~/workspace/models/YOUR_MODEL.gguf --host 127.0.0.1 --port 8080"
echo ""
echo "3) Then build the dashboard (next script)."
echo "==============================================="
