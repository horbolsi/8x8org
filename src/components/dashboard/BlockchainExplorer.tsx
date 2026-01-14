import React, { useEffect, useState } from 'react';
import { Blocks, Link, Box, ArrowRight, Clock, Hash, Layers, RefreshCw } from 'lucide-react';
import { ethers } from 'ethers';
import { useConfig } from '../../store/config';
import { motion, AnimatePresence } from 'framer-motion';

interface Block {
  height: number;
  hash: string;
  txs: number;
  time: string;
}

export function BlockchainExplorer() {
  const { rpcUrl } = useConfig();
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [isSyncing, setIsSyncing] = useState(true);

  useEffect(() => {
    let provider: ethers.JsonRpcProvider;
    let mounted = true;

    const fetchBlock = async () => {
      try {
        if (!provider) provider = new ethers.JsonRpcProvider(rpcUrl);
        const blockNumber = await provider.getBlockNumber();
        const block = await provider.getBlock(blockNumber);
        
        if (block && mounted) {
          setBlocks(prev => {
            // Avoid duplicates
            if (prev.length > 0 && prev[0].height === block.number) return prev;
            
            const newBlock: Block = {
              height: block.number,
              hash: block.hash || '',
              txs: block.transactions.length,
              time: 'Just now'
            };
            return [newBlock, ...prev].slice(0, 5);
          });
          setIsSyncing(false);
        }
      } catch (error) {
        console.error("Blockchain fetch error:", error);
        setIsSyncing(false);
      }
    };

    // Initial fetch
    fetchBlock();

    // Poll every 12 seconds (avg block time)
    const interval = setInterval(fetchBlock, 12000);

    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, [rpcUrl]);

  return (
    <div className="glass-panel rounded-xl p-6 border border-white/10 relative overflow-hidden">
      <div className="absolute top-0 right-0 p-4 opacity-5 pointer-events-none">
        <Blocks className="w-64 h-64 text-indigo-500" />
      </div>

      <div className="flex items-center justify-between mb-8 relative z-10">
        <div>
          <h3 className="font-bold text-white flex items-center gap-2 text-lg">
            <Blocks className="w-5 h-5 text-indigo-400" />
            Blockchain Explorer
          </h3>
          <p className="text-xs text-gray-500 mt-1 font-mono">Live block feed from connected node</p>
        </div>
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-900/50 border border-white/10">
          <div className="relative">
            <span className={`w-2 h-2 rounded-full bg-emerald-500 ${isSyncing ? 'animate-pulse' : ''}`} />
            {isSyncing && <span className="absolute inset-0 rounded-full bg-emerald-500 animate-ping opacity-75" />}
          </div>
          <span className="text-xs font-mono text-emerald-400 font-bold tracking-wider">{isSyncing ? 'SYNCING' : 'LIVE FEED'}</span>
        </div>
      </div>

      <div className="space-y-4 relative z-10">
        <div className="flex items-center justify-between text-xs text-gray-500 font-mono uppercase tracking-wider px-4">
          <span>Block Height</span>
          <span>Hash / Transactions</span>
        </div>
        
        <div className="relative">
          {/* Connecting Line */}
          <div className="absolute left-8 top-4 bottom-4 w-px bg-gradient-to-b from-indigo-500/50 to-transparent border-l border-dashed border-indigo-500/30" />

          <AnimatePresence initial={false}>
            {blocks.length === 0 ? (
              <motion.div 
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="text-center text-gray-500 py-12 bg-slate-900/30 rounded-xl border border-white/5 border-dashed"
              >
                <RefreshCw className="w-6 h-6 mx-auto mb-2 animate-spin opacity-50" />
                <p className="text-sm">Waiting for blocks...</p>
              </motion.div>
            ) : (
              blocks.map((block, index) => (
                <motion.div
                  key={block.height}
                  initial={{ opacity: 0, x: -20, height: 0 }}
                  animate={{ opacity: 1, x: 0, height: 'auto' }}
                  exit={{ opacity: 0, x: 20, height: 0 }}
                  transition={{ duration: 0.3, delay: index * 0.1 }}
                  className="mb-3 last:mb-0"
                >
                  <div className="bg-slate-900/40 border border-white/5 rounded-xl p-4 flex items-center justify-between group hover:border-indigo-500/30 hover:bg-slate-900/60 transition-all relative overflow-hidden">
                    <div className="absolute left-0 top-0 bottom-0 w-1 bg-indigo-500 opacity-0 group-hover:opacity-100 transition-opacity" />
                    
                    <div className="flex items-center gap-4">
                      <div className="w-10 h-10 rounded-lg bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400 shrink-0 z-10 relative bg-slate-900">
                        <Box size={18} />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-white font-mono text-lg">#{block.height}</span>
                          {index === 0 && (
                            <span className="px-1.5 py-0.5 rounded text-[10px] bg-indigo-500 text-white font-bold">LATEST</span>
                          )}
                        </div>
                        <div className="flex items-center gap-2 text-xs text-gray-500">
                          <Clock size={12} />
                          <span>{block.time}</span>
                        </div>
                      </div>
                    </div>

                    <div className="text-right">
                      <div className="flex items-center justify-end gap-2 text-xs font-mono text-gray-400 mb-1">
                        <Hash size={12} />
                        <span className="truncate max-w-[100px] sm:max-w-[200px]">{block.hash}</span>
                      </div>
                      <div className="flex items-center justify-end gap-1 text-xs text-indigo-400 bg-indigo-500/10 px-2 py-0.5 rounded-full inline-flex ml-auto">
                        <Layers size={12} />
                        <span>{block.txs} txs</span>
                      </div>
                    </div>
                    
                    <div className="absolute right-4 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 transition-opacity">
                      <ArrowRight className="w-5 h-5 text-indigo-500" />
                    </div>
                  </div>
                </motion.div>
              ))
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
