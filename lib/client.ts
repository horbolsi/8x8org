// Mock Supabase client for now
export const client = {
  auth: {
    getSession: async () => ({ 
      data: { 
        session: { 
          user: { id: '1', email: 'user@example.com' },
          access_token: 'mock-token'
        } 
      } 
    }),
    onAuthStateChange: (callback: (event: string, session: any) => void) => {
      // Mock subscription
      setTimeout(() => {
        callback('SIGNED_IN', { 
          user: { id: '1', email: 'user@example.com' },
          access_token: 'mock-token'
        });
      }, 100);
      
      return {
        data: {
          subscription: {
            unsubscribe: () => {}
          }
        }
      };
    }
  }
};
