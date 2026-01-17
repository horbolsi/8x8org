# 8x8org Workspace Mirror

## Overview

This is a multi-purpose workspace that combines two main components:

1. **Workspace Mirror Tool** - A synchronization utility for mirroring repositories, bootstrapped via shell scripts (`scripts/bootstrap_workspace_mirror.sh`) and operated through `bin/wsync`

2. **8x8org Sovereign Dashboard** - A self-hosted dashboard application featuring:
   - Flask + Flask-SocketIO backend (Python)
   - SQLite for data persistence
   - Telegram WebApp integration for bot-based access
   - Real-time system monitoring
   - Draggable widget-based UI with GridStack
   - Designed to be portable across Replit and Termux (Android terminal)

The project emphasizes portability, simplicity, and "boring" correctness over complexity.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Backend Architecture
- **Framework**: Flask 3.0.3 with Flask-SocketIO 5.3.6 for real-time communication
- **Runtime**: Eventlet 0.40.3 for async support
- **Database**: SQLite (file-based, no external database server required)
- **Security**: Cryptography library with Fernet encryption for sensitive data
- **Environment**: python-dotenv for configuration management

The backend prioritizes portability - it runs identically on Replit cloud and Termux mobile terminal without modification.

### Frontend Architecture
- **Styling**: Tailwind CSS (loaded via CDN)
- **Real-time**: Socket.IO client for live updates
- **Layout**: GridStack for draggable, saveable widget layouts
- **Icons**: Lucide React (in React components)
- **Telegram Integration**: Native Telegram WebApp bridge for in-app experiences

### Bot Integration
- **Platform**: Telegram via python-telegram-bot library (v21.x)
- **Purpose**: Provides WebApp launcher buttons to open the dashboard directly within Telegram
- **Commands**: `/start` (shows dashboard buttons), `/health` (status check)

### Directory Structure
- `apps/dashboard/` - Main dashboard Flask application
- `services/bot/` - Telegram bot service
- `tools/` - Development utilities (dev status, start/stop scripts)
- `runtime/` - Runtime outputs and logs
- `repos/8x8org/` - Core application source
- `.tools/` - Bundled tools (Node.js binary)

### Development Workflow
The project uses a custom `./tools/dev` CLI for operations:
- `./tools/dev status` - Check system status
- `./tools/dev dash:start/stop` - Manage dashboard server
- `./tools/dev bot:start/stop` - Manage Telegram bot

## External Dependencies

### Python Packages (requirements.txt)
- **flask** (3.0.3) - Web framework
- **flask-socketio** (5.3.6) - WebSocket support
- **eventlet** (0.40.3) - Async networking
- **psutil** (6.0.0) - System monitoring
- **requests** (2.32.4) - HTTP client
- **python-dotenv** (1.0.1) - Environment configuration
- **cryptography** (>=42.0.0) - Encryption
- **python-telegram-bot** (>=21,<22) - Telegram API

### CDN Dependencies (Frontend)
- Tailwind CSS
- Socket.IO client (4.7.5)
- GridStack (10.1.1)
- SortableJS (1.15.2)
- Telegram WebApp JS bridge

### Environment Variables Required
- `TELEGRAM_BOT_TOKEN` - Bot authentication token
- `DASHBOARD_URL` - Public URL for the dashboard (default: https://8x8org.youware.app)

### Bundled Tools
- Node.js v20.11.1 (Linux x64 binary in `.tools/`)