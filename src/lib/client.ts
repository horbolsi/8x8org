// Mock client to avoid missing @edgespark/client dependency and fix blank screen
export const client = {
  baseUrl: "https://staging--c8yscckgjqswzrju1iaw.youbase.cloud",
  auth: {
    getSession: async () => ({ data: { session: { user: { id: 'admin', email: 'admin@sovereign.ai' } } }, error: null }),
    onAuthStateChange: (callback: any) => {
      // Immediately trigger callback with mock session
      setTimeout(() => {
        callback('SIGNED_IN', { user: { id: 'admin', email: 'admin@sovereign.ai' } });
      }, 0);
      return { data: { subscription: { unsubscribe: () => {} } } };
    },
    signInWithPassword: async () => ({ data: { session: { user: { id: 'admin' } } }, error: null }),
    signOut: async () => ({ error: null }),
  },
  storage: {
    from: (bucket: string) => ({
      list: async () => ({ data: [], error: null }),
      upload: async () => ({ data: {}, error: null }),
      download: async () => ({ data: new Blob(), error: null }),
    })
  },
  db: {
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          single: async () => ({ data: {}, error: null }),
          data: [],
          error: null
        }),
        data: [],
        error: null
      }),
      insert: async () => ({ data: {}, error: null }),
      update: async () => ({ data: {}, error: null }),
    })
  },
  execute: async (command: string) => {
    console.log("Executing mock command:", command);
    return { success: true, output: `Mock output for: ${command}` };
  }
};
