"use strict";
// Simple, clean logging utility
Object.defineProperty(exports, "__esModule", { value: true });
exports.log = void 0;
exports.log = {
    info: (message, ...args) => {
        console.log(`ℹ️  ${message}`, ...args);
    },
    success: (message, ...args) => {
        console.log(`✅ ${message}`, ...args);
    },
    error: (message, ...args) => {
        console.error(`❌ ${message}`, ...args);
    },
    search: (message, ...args) => {
        console.log(`🔍 ${message}`, ...args);
    },
    server: (message, ...args) => {
        console.log(`🚀 ${message}`, ...args);
    },
    db: (message, ...args) => {
        console.log(`💾 ${message}`, ...args);
    }
};
//# sourceMappingURL=logger.js.map