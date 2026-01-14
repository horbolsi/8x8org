# Sovereign AI Dashboard

## Overview

A futuristic, Matrix-themed dashboard for managing an AI ecosystem. This is a React + TypeScript single-page application that serves as a central control interface for AI agents, system monitoring, blockchain interactions, and cryptographic tools. The application features a glassmorphism UI design with multiple theme options (Matrix, Cyber, Dark).

**Key Capabilities:**
- AI Console with OpenAI API integration (optional)
- Real-time system resource monitoring with live charts
- Bot/agent management (Telegram, Discord, Trading bots)
- Cryptocurrency wallet generation using ethers.js
- Blockchain explorer connecting to Ethereum RPC
- File explorer and system logs viewer
- Terminal emulator with custom commands

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Frontend Architecture
- **Framework**: React 18 with TypeScript
- **Build Tool**: Vite 7.0.0 for fast HMR and optimized builds
- **Styling**: Tailwind CSS with CSS custom properties for theming
- **State Management**: Zustand with persist middleware for settings
- **Animations**: Framer Motion for smooth transitions
- **Charts**: Recharts for real-time data visualization
- **Routing**: React Router DOM (available but currently single-page)

### Component Structure
- `src/components/dashboard/` - Main feature components (AIConsole, BotManager, CryptoTools, etc.)
- `src/components/auth/` - Authentication UI components
- `src/store/` - Zustand stores for global state (config, terminal)
- `src/lib/` - Utility functions and service clients

### Backend Architecture
- **Framework**: Hono (lightweight web framework)
- **Database ORM**: Drizzle ORM with SQLite
- **Deployment Target**: Cloudflare Workers via EdgeSpark
- **API Pattern**: REST endpoints under `/api/` prefix

### Data Layer
- **Database Tables**: `bots`, `files`, `logs`, `es_system__auth_user`
- **Schema Location**: `backend/src/__generated__/db_schema.ts`
- **Local Fallback**: localStorage used when backend unavailable

### Authentication
- EdgeSpark authentication system with session management
- Auth UI rendered via `client.auth.renderAuthUI()`
- Protected API routes under `/api/*` have guaranteed user context

### Theme System
- CSS custom properties define theme colors (`--primary`, `--bg-deep`, etc.)
- Three themes: Matrix (green), Cyber (indigo/pink), Dark (blue)
- Theme persisted via Zustand + localStorage

## External Dependencies

### Third-Party Services
- **OpenAI API**: Optional integration for AI Console chat (requires user-provided API key)
- **Ethereum RPC**: Cloudflare-eth.com default for blockchain data fetching
- **EdgeSpark**: Backend-as-a-service platform (authentication, database, storage)

### Key Libraries
- `ethers.js` v6 - Ethereum wallet generation and blockchain interactions
- `recharts` - Real-time charting for system monitoring
- `framer-motion` - Animation library
- `zustand` - Lightweight state management
- `drizzle-orm` - Type-safe database queries

### API Configuration
- EdgeSpark client configured in `src/lib/client.ts`
- Base URL: `https://staging--c8yscckgjqswzrju1iaw.youbase.cloud`
- Storage service abstraction in `src/lib/storage.ts` handles API calls with localStorage fallback