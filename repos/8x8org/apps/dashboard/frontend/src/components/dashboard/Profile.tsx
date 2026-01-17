import React, { useState, useEffect } from 'react';
import { User, Key, Wallet, Save, Shield } from 'lucide-react';
import { StorageService, type Profile } from '../../lib/storage';
import { client } from '../../lib/client';

export function Profile() {
  const [profile, setProfile] = useState<Profile>({ userId: '' });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const loadProfile = async () => {
        const { data } = await client.auth.getSession();
        if (data.session?.user) {
            const p = await StorageService.getProfile(data.session.user.id);
            setProfile(p.userId ? p : { userId: data.session.user.id });
        }
        setLoading(false);
    };
    loadProfile();
  }, []);

  const handleSave = async () => {
    setSaving(true);
    await StorageService.saveProfile(profile);
    setSaving(false);
  };

  if (loading) return <div className="p-8 text-center text-gray-500">Loading profile...</div>;

  return (
    <div className="glass-panel rounded-xl p-8 border border-white/10 relative overflow-hidden max-w-2xl mx-auto">
        <div className="flex items-center gap-4 mb-8">
            <div className="p-3 rounded-xl bg-indigo-500/10 border border-indigo-500/20">
                <User className="w-8 h-8 text-indigo-400" />
            </div>
            <div>
                <h2 className="text-2xl font-bold text-white">Guest Identity</h2>
                <p className="text-gray-400 text-sm">Manage your hotel access and wallet</p>
            </div>
        </div>

        <div className="space-y-6">
            <div className="space-y-2">
                <label className="text-sm font-medium text-gray-300 flex items-center gap-2">
                    <Shield className="w-4 h-4 text-indigo-400" /> AI Identity ID
                </label>
                <input 
                    type="text" 
                    value={profile.aiId || ''}
                    onChange={e => setProfile({...profile, aiId: e.target.value})}
                    className="w-full bg-black/20 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-indigo-500/50 outline-none transition-all"
                    placeholder="Enter your AI verification ID"
                />
            </div>

            <div className="space-y-2">
                <label className="text-sm font-medium text-gray-300 flex items-center gap-2">
                    <Key className="w-4 h-4 text-emerald-400" /> Telegram ID
                </label>
                <input 
                    type="text" 
                    value={profile.telegramId || ''}
                    onChange={e => setProfile({...profile, telegramId: e.target.value})}
                    className="w-full bg-black/20 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-emerald-500/50 outline-none transition-all"
                    placeholder="@username or ID"
                />
            </div>

            <div className="space-y-2">
                <label className="text-sm font-medium text-gray-300 flex items-center gap-2">
                    <Wallet className="w-4 h-4 text-purple-400" /> Wallet Address
                </label>
                <input 
                    type="text" 
                    value={profile.walletAddress || ''}
                    onChange={e => setProfile({...profile, walletAddress: e.target.value})}
                    className="w-full bg-black/20 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-purple-500/50 outline-none transition-all font-mono"
                    placeholder="0x..."
                />
            </div>

            <button 
                onClick={handleSave}
                disabled={saving}
                className="w-full py-3 bg-indigo-600 hover:bg-indigo-500 text-white rounded-xl font-medium transition-all flex items-center justify-center gap-2 mt-8 disabled:opacity-50"
            >
                {saving ? 'Saving...' : <><Save className="w-4 h-4" /> Update Identity</>}
            </button>
        </div>
    </div>
  );
}
