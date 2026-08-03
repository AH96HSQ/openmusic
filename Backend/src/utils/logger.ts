// Simple, clean logging utility

export const log = {
  info: (message: string, ...args: any[]) => {
    console.log(`ℹ️  ${message}`, ...args);
  },
  
  success: (message: string, ...args: any[]) => {
    console.log(`✅ ${message}`, ...args);
  },
  
  error: (message: string, ...args: any[]) => {
    console.error(`❌ ${message}`, ...args);
  },
  
  search: (message: string, ...args: any[]) => {
    console.log(`🔍 ${message}`, ...args);
  },
  
  server: (message: string, ...args: any[]) => {
    console.log(`🚀 ${message}`, ...args);
  },
  
  db: (message: string, ...args: any[]) => {
    console.log(`💾 ${message}`, ...args);
  }
};