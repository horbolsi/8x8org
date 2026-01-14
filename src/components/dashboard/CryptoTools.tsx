import React, { useState } from 'react';
import { Shield, Key, Copy, RefreshCw, Wallet, Lock, Unlock, Eye, EyeOff, X, AlertCircle } from 'lucide-react';
import { ethers } from 'ethers';
import { motion, AnimatePresence } from 'framer-motion';

export function CryptoTools() {
  const [wallet, setWallet] = useState<{ address: string; privateKey: string } | null>(null);
  const [isGenerating, setIsGenerating] = useState(false);
  const [showPrivateKey, setShowPrivateKey] = useState(false);
  const [showEncryptor, setShowEncryptor] = useState(false);
  
  // Encryptor State
  const [message, setMessage] = useState('');
  const [passphrase, setPassphrase] = useState('');
  const [encryptedData, setEncryptedData] = useState('');
  const [isEncrypting, setIsEncrypting] = useState(false);

  const generateWallet = async () => {
    setIsGenerating(true);
    await new Promise(resolve => setTimeout(resolve, 800));
    
    try {
      const newWallet = ethers.Wallet.createRandom();
      setWallet({
        address: newWallet.address,
        privateKey: newWallet.privateKey
      });
    } catch (error) {
      console.error("Wallet generation failed:", error);
    } finally {
      setIsGenerating(false);
    }
  };

  const handleEncrypt = async () => {
    if (!message || !passphrase) return;
    setIsEncrypting(true);
    
    try {
      // Simple AES-GCM encryption simulation using Web Crypto API
      const enc = new TextEncoder();
      const keyMaterial = await window.crypto.subtle.importKey(
        "raw",
        enc.encode(passphrase),
        { name: "PBKDF2" },
        false,
        ["deriveBits", "deriveKey"]
      );
      
      const salt = window.crypto.getRandomValues(new Uint8Array(16));
      const key = await window.crypto.subtle.deriveKey(
        {
          name: "PBKDF2",
          salt,
          iterations: 100000,
          hash: "SHA-256"
        },
        keyMaterial,
        { name: "AES-GCM", length: 256 },
        true,
        ["encrypt", "decrypt"]
      );

      const iv = window.crypto.getRandomValues(new Uint8Array(12));
      const encrypted = await window.crypto.subtle.encrypt(
        { name: "AES-GCM", iv },
        key,
        enc.encode(message)
      );

      const encryptedArray = new Uint8Array(encrypted);
      const buf = new Uint8Array(salt.byteLength + iv.byteLength + encryptedArray.byteLength);
      buf.set(salt, 0);
      buf.set(iv, salt.byteLength);
      buf.set(encryptedArray, salt.byteLength + iv.byteLength);
      
      setEncryptedData(btoa(String.fromCharCode(...buf)));
    } catch (e) {
      console.error("Encryption failed", e);
    } finally {
      setIsEncrypting(false);
    }
  };

  return (
    <div className="glass-panel rounded-xl p-8 border border-white/10 relative overflow-hidden">
      <div className="absolute top-0 right-0 p-4 opacity-5 pointer-events-none">
        <Shield className="w-64 h-64 text-indigo-500" />
      </div>

      <div className="flex items-center justify-between mb-8 relative z-10">
        <div>
          <h3 className="font-bold text-white flex items-center gap-2 text-lg">
            <Shield className="w-5 h-5 text-indigo-400" />
            Crypto Vault
          </h3>
          <p className="text-xs text-gray-500 mt-1 font-mono">Secure key generation and encryption tools</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 relative z-10">
        {/* Tools Column */}
        <div className="space-y-6">
          <motion.div 
            whileHover={{ scale: 1.02 }}
            className="p-6 rounded-xl bg-gradient-to-br from-indigo-500/10 to-purple-500/5 border border-indigo-500/20 group cursor-pointer"
          >
            <div className="flex items-start justify-between mb-4">
              <div className="p-3 rounded-lg bg-indigo-500/20 text-indigo-400 group-hover:text-white transition-colors">
                <Wallet className="w-6 h-6" />
              </div>
              <span className="px-2 py-1 rounded text-[10px] bg-indigo-500/20 text-indigo-300 border border-indigo-500/20 uppercase tracking-wider">EVM Compatible</span>
            </div>
            <h4 className="text-lg font-bold text-white mb-2">Wallet Generator</h4>
            <p className="text-sm text-gray-400 mb-6 leading-relaxed">Generate secure, offline Ethereum-compatible wallets using standard cryptographic primitives. Keys are generated locally.</p>
            <button 
              onClick={generateWallet}
              disabled={isGenerating}
              className="w-full py-3 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition-all shadow-lg shadow-indigo-500/20 flex items-center justify-center gap-2 text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isGenerating ? (
                <RefreshCw className="w-4 h-4 animate-spin" />
              ) : (
                <RefreshCw className="w-4 h-4" />
              )}
              {isGenerating ? 'Generating Keys...' : 'Generate New Wallet'}
            </button>
          </motion.div>

          <motion.div 
            whileHover={{ scale: 1.02 }}
            className="p-6 rounded-xl bg-gradient-to-br from-purple-500/10 to-pink-500/5 border border-purple-500/20 group cursor-pointer"
          >
            <div className="flex items-start justify-between mb-4">
              <div className="p-3 rounded-lg bg-purple-500/20 text-purple-400 group-hover:text-white transition-colors">
                <Lock className="w-6 h-6" />
              </div>
              <span className="px-2 py-1 rounded text-[10px] bg-purple-500/20 text-purple-300 border border-purple-500/20 uppercase tracking-wider">AES-256</span>
            </div>
            <h4 className="text-lg font-bold text-white mb-2">Data Encryption</h4>
            <p className="text-sm text-gray-400 mb-6 leading-relaxed">Encrypt sensitive payloads using military-grade AES-256 encryption. Secure your data before transmission.</p>
            <button 
              onClick={() => setShowEncryptor(true)}
              className="w-full py-3 bg-purple-600 hover:bg-purple-500 text-white rounded-lg transition-all shadow-lg shadow-purple-500/20 flex items-center justify-center gap-2 text-sm font-medium"
            >
              <Key className="w-4 h-4" /> Open Encryptor
            </button>
          </motion.div>
        </div>

        {/* Result Column */}
        <div className="relative">
          <div className="absolute inset-0 bg-gradient-to-b from-indigo-500/5 to-transparent rounded-xl" />
          <div className="h-full bg-slate-900/50 rounded-xl border border-white/10 p-6 font-mono text-sm relative overflow-hidden backdrop-blur-sm flex flex-col">
            {!wallet ? (
              <div className="flex-1 flex flex-col items-center justify-center text-gray-500 gap-4 min-h-[300px]">
                <div className="w-16 h-16 rounded-full bg-white/5 flex items-center justify-center">
                  <Shield className="w-8 h-8 opacity-20" />
                </div>
                <p className="text-sm">Select a tool to view output</p>
              </div>
            ) : (
              <motion.div 
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className="space-y-6"
              >
                <div className="flex items-center justify-between pb-4 border-b border-white/5">
                  <h4 className="text-sm font-bold text-white uppercase tracking-wider">Generated Wallet</h4>
                  <span className="text-[10px] text-emerald-400 bg-emerald-500/10 px-2 py-1 rounded border border-emerald-500/20">SUCCESS</span>
                </div>

                <div className="space-y-2">
                  <label className="text-xs text-gray-500 uppercase tracking-wider font-semibold">Public Address</label>
                  <div className="group relative">
                    <div className="bg-black/40 p-4 rounded-lg border border-white/10 break-all text-emerald-400 hover:border-emerald-500/30 transition-colors">
                      {wallet.address}
                    </div>
                    <button 
                      onClick={() => navigator.clipboard.writeText(wallet.address)}
                      className="absolute top-2 right-2 p-2 bg-slate-800 rounded-md text-gray-400 hover:text-white opacity-0 group-hover:opacity-100 transition-all"
                    >
                      <Copy className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <label className="text-xs text-gray-500 uppercase tracking-wider font-semibold">Private Key</label>
                    <button 
                      onClick={() => setShowPrivateKey(!showPrivateKey)}
                      className="text-xs text-indigo-400 hover:text-indigo-300 flex items-center gap-1"
                    >
                      {showPrivateKey ? <EyeOff size={12} /> : <Eye size={12} />}
                      {showPrivateKey ? 'Hide' : 'Reveal'}
                    </button>
                  </div>
                  <div className="group relative">
                    <div className={`bg-black/40 p-4 rounded-lg border border-red-500/20 break-all text-red-400 transition-all duration-300 ${showPrivateKey ? '' : 'blur-sm select-none'}`}>
                      {wallet.privateKey}
                    </div>
                    <button 
                      onClick={() => navigator.clipboard.writeText(wallet.privateKey)}
                      className="absolute top-2 right-2 p-2 bg-slate-800 rounded-md text-gray-400 hover:text-white opacity-0 group-hover:opacity-100 transition-all"
                    >
                      <Copy className="w-4 h-4" />
                    </button>
                  </div>
                  <p className="text-[10px] text-red-400/60 mt-2 flex items-center gap-1">
                    <AlertCircle size={10} />
                    Never share your private key. Store it safely offline.
                  </p>
                </div>
              </motion.div>
            )}
          </div>
        </div>
      </div>

      {/* Encryptor Modal */}
      <AnimatePresence>
        {showEncryptor && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="absolute inset-0 z-50 bg-slate-900/90 backdrop-blur-md flex items-center justify-center p-8"
          >
            <motion.div 
              initial={{ scale: 0.9, y: 20 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.9, y: 20 }}
              className="w-full max-w-lg bg-slate-900 border border-purple-500/30 rounded-xl p-6 shadow-2xl relative"
            >
              <button 
                onClick={() => setShowEncryptor(false)}
                className="absolute top-4 right-4 p-2 hover:bg-white/10 rounded-lg text-gray-400 hover:text-white transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
              
              <div className="flex items-center gap-3 mb-6 text-purple-400">
                <Lock className="w-6 h-6" />
                <h3 className="text-xl font-bold">AES-256 Encryptor</h3>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="text-xs text-gray-500 uppercase tracking-wider font-semibold block mb-2">Message to Encrypt</label>
                  <textarea 
                    value={message}
                    onChange={(e) => setMessage(e.target.value)}
                    className="w-full h-32 bg-black/40 border border-white/10 rounded-lg p-4 text-white focus:border-purple-500/50 outline-none resize-none"
                    placeholder="Enter sensitive data..."
                  />
                </div>
                <div>
                  <label className="text-xs text-gray-500 uppercase tracking-wider font-semibold block mb-2">Passphrase</label>
                  <input 
                    type="password"
                    value={passphrase}
                    onChange={(e) => setPassphrase(e.target.value)}
                    className="w-full bg-black/40 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-purple-500/50 outline-none"
                    placeholder="Enter strong passphrase"
                  />
                </div>
                
                {encryptedData && (
                  <div className="bg-black/40 p-4 rounded-lg border border-purple-500/20 break-all text-xs font-mono text-purple-300">
                    {encryptedData}
                  </div>
                )}

                <button 
                  onClick={handleEncrypt}
                  disabled={isEncrypting || !message || !passphrase}
                  className="w-full py-3 bg-purple-600 hover:bg-purple-500 text-white rounded-lg transition-all shadow-lg shadow-purple-500/20 font-medium mt-4 disabled:opacity-50"
                >
                  {isEncrypting ? 'Encrypting...' : 'Encrypt Data'}
                </button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
