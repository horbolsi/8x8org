import React, { useEffect, useRef } from 'react';
import { client } from '../../lib/client';
import { motion } from 'framer-motion';
import { Shield } from 'lucide-react';

export function Login() {
  const containerRef = useRef<HTMLDivElement>(null);
  const renderedRef = useRef(false);

  useEffect(() => {
    if (containerRef.current && !renderedRef.current) {
      renderedRef.current = true;
      client.auth.renderAuthUI(containerRef.current, {
        redirectTo: window.location.origin, // Redirect to same page
        labels: {
            signIn: {
                title: "Access Sovereign Core",
                loginButton: "Authenticate"
            },
            signUp: {
                title: "Initialize New Identity",
                signUpButton: "Register Identity"
            }
        }
      }).catch(err => {
        console.error("Failed to render auth UI:", err);
      });
    }
  }, []);

  return (
    <div className="min-h-screen bg-black flex items-center justify-center p-4 relative overflow-hidden">
      {/* Background Effects */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-indigo-900/20 via-black to-black" />
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-20" />
      
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="w-full max-w-md relative z-10"
      >
        <div className="glass-panel p-8 rounded-2xl border border-white/10 shadow-2xl shadow-indigo-500/10 backdrop-blur-xl bg-black/40">
          <div className="flex flex-col items-center mb-8">
            <div className="w-16 h-16 bg-indigo-500/10 rounded-full flex items-center justify-center mb-4 border border-indigo-500/20 shadow-[0_0_15px_rgba(99,102,241,0.3)]">
              <Shield className="w-8 h-8 text-indigo-400" />
            </div>
            <h1 className="text-2xl font-bold text-white tracking-tight">Sovereign AI</h1>
            <p className="text-gray-400 text-sm mt-2">Secure Access Terminal</p>
          </div>
          
          <div ref={containerRef} className="auth-container" />
        </div>
      </motion.div>
    </div>
  );
}
