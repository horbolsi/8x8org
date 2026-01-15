// Mock client to avoid missing @edgespark/client dependency
export const client = {
  baseUrl: "https://staging--c8yscckgjqswzrju1iaw.youbase.cloud",
  execute: async (command: string) => {
    console.log("Executing mock command:", command);
    return { success: true, output: `Mock output for: ${command}` };
  }
};
