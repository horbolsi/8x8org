import React, { Component, ErrorInfo, ReactNode } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('Uncaught error:', error, errorInfo);
  }

  public render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-slate-950 text-white flex items-center justify-center p-4">
          <div className="max-w-md w-full bg-slate-900 border border-red-500/20 rounded-xl p-6 shadow-2xl">
            <div className="flex items-center gap-3 mb-4 text-red-400">
              <AlertTriangle className="w-8 h-8" />
              <h1 className="text-xl font-bold">System Critical Error</h1>
            </div>
            <p className="text-gray-400 mb-6 text-sm leading-relaxed">
              The application encountered an unexpected error and had to terminate the active session.
            </p>
            <div className="bg-black/40 rounded-lg p-4 mb-6 border border-white/5 overflow-auto max-h-40">
              <code className="text-xs font-mono text-red-300 block">
                {this.state.error?.message || 'Unknown error'}
              </code>
            </div>
            <button
              onClick={() => window.location.reload()}
              className="w-full py-3 bg-red-600 hover:bg-red-500 text-white rounded-lg transition-colors flex items-center justify-center gap-2 font-medium"
            >
              <RefreshCw className="w-4 h-4" /> Reboot System
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
