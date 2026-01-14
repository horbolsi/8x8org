# Sovereign AI Dashboard

A futuristic, Matrix-themed dashboard for managing the Sovereign AI Ecosystem. This application serves as the central control interface for AI agents, system monitoring, and cryptographic tools.

## Project Status

- **Project Type**: React + TypeScript Modern Web Application
- **Entry Point**: `src/main.tsx`
- **Build System**: Vite 7.0.0
- **Styling System**: Tailwind CSS 3.4.17

## Key Features

### 1. AI Console
- **Functional**: Connects to OpenAI API (requires API Key in Settings).
- **Simulation**: Fallback to simulated neural processing responses if no key provided.
- Real-time typing indicators and message history.

### 2. System Monitor
- Real-time visualization of system resources (CPU, Memory, Network).
- Live area charts using Recharts.
- Matrix-themed data cards.

### 3. Bot Manager
- Status tracking for autonomous agents (Telegram, Discord, Trading bots).
- Visual status indicators (Running, Stopped, Error).
- Deployment and management controls.

### 4. Crypto Tools
- **Functional**: Secure wallet generation using `ethers.js`.
- Generates real EVM-compatible addresses and private keys locally.
- Encryption tool interface.

### 5. File Explorer
- System file management interface.
- Categorized file icons and metadata display.

### 6. System Logs
- Real-time scrolling log viewer.
- Color-coded log levels (INFO, WARN, ERROR).

### 7. Blockchain Explorer
- **Functional**: Connects to Ethereum RPC (default: Cloudflare) to fetch real block data.
- Live block feed visualization with transaction counts and hashes.

### 8. Terminal
- Command-line interface simulation.
- Supports basic commands (help, status, date, clear).

### 9. Settings
- Configuration for OpenAI API Key.
- Configuration for Ethereum RPC URL.
- User profile settings.
- Data persistence using local storage.

## Design System

- **Theme**: Cyberpunk / Matrix
- **Colors**:
  - Primary: Indigo (#6366f1)
  - Secondary: Purple (#8b5cf6)
  - Accent: Emerald (#10b981)
  - Background: Darker (#020617)
- **Effects**:
  - Glassmorphism panels
  - Neon text glows
  - Matrix background animation
  - CRT-style terminal text

## Directory Structure

```
src/
├── components/
│   └── dashboard/
│       ├── DashboardLayout.tsx  # Main layout with sidebar
│       ├── AIConsole.tsx        # Chat interface (Real/Simulated)
│       ├── SystemMonitor.tsx    # Resource charts
│       ├── BotManager.tsx       # Bot table
│       ├── CryptoTools.tsx      # Wallet tools (Real)
│       ├── FileExplorer.tsx     # File list
│       ├── LogViewer.tsx        # System logs
│       ├── BlockchainExplorer.tsx # Block feed (Real)
│       ├── Terminal.tsx         # CLI interface
│       └── Settings.tsx         # Configuration
├── lib/
│   └── utils.ts                 # Helper functions
├── store/
│   └── config.ts                # Zustand store for settings
├── App.tsx                      # Main application grid
└── index.css                    # Global styles & animations
```

## Development

To run the development server:
```bash
npm run dev
```

To build for production:
```bash
npm run build
```
