import React from 'react';

interface DashboardLayoutProps {
  currentView: string;
  onNavigate: (view: string) => void;
  children: React.ReactNode;
}

export const DashboardLayout: React.FC<DashboardLayoutProps> = ({ 
  currentView, 
  onNavigate, 
  children 
}) => {
  const navItems = [
    { id: 'dashboard', label: 'Dashboard' },
    { id: 'monitor', label: 'Monitor' },
    { id: 'bots', label: 'Bots' },
    { id: 'crypto', label: 'Crypto' },
    { id: 'blockchain', label: 'Blockchain' },
    { id: 'terminal', label: 'Terminal' },
    { id: 'files', label: 'Files' },
    { id: 'logs', label: 'Logs' },
    { id: 'settings', label: 'Settings' },
  ];

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      {/* Sidebar */}
      <div className="fixed left-0 top-0 h-full w-64 bg-gray-800 border-r border-gray-700 p-4">
        <h1 className="text-2xl font-bold mb-8">AI Dashboard</h1>
        <nav className="space-y-2">
          {navItems.map((item) => (
            <button
              key={item.id}
              onClick={() => onNavigate(item.id)}
              className={`w-full text-left px-4 py-2 rounded-lg transition-colors ${
                currentView === item.id
                  ? 'bg-blue-600 text-white'
                  : 'hover:bg-gray-700 text-gray-300'
              }`}
            >
              {item.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Main Content */}
      <div className="ml-64 p-6">
        {children}
      </div>
    </div>
  );
};
