"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.getSystemMetrics = getSystemMetrics;
exports.formatBytes = formatBytes;
exports.formatUptime = formatUptime;
const si = __importStar(require("systeminformation"));
/**
 * Get memory information using systeminformation
 */
async function getMemoryInfo() {
    try {
        const mem = await si.mem();
        return {
            total: mem.total,
            used: mem.used,
            free: mem.free,
            usagePercent: Math.round((mem.used / mem.total) * 100)
        };
    }
    catch {
        return {
            total: 0,
            used: 0,
            free: 0,
            usagePercent: 0
        };
    }
}
/**
 * Get CPU information using systeminformation
 */
async function getCpuInfo() {
    try {
        const [cpu, cpuLoad] = await Promise.all([
            si.cpu(),
            si.currentLoad()
        ]);
        return {
            model: cpu.model || 'Unknown',
            cores: cpu.cores || 0,
            speed: cpu.speed || 0,
            currentUsage: Math.round(cpuLoad.currentLoad || 0)
        };
    }
    catch {
        return {
            model: 'Unknown',
            cores: 0,
            speed: 0,
            currentUsage: 0
        };
    }
}
/**
 * Get storage information using systeminformation
 */
async function getStorageInfo() {
    try {
        const disks = await si.fsSize();
        const drives = disks.map(disk => ({
            drive: disk.fs,
            total: disk.size,
            used: disk.used,
            free: disk.available,
            usagePercent: Math.round((disk.used / disk.size) * 100)
        }));
        const totalStorage = disks.reduce((acc, disk) => acc + disk.size, 0);
        const totalUsed = disks.reduce((acc, disk) => acc + disk.used, 0);
        const totalFree = disks.reduce((acc, disk) => acc + disk.available, 0);
        const totalUsagePercent = totalStorage > 0 ? Math.round((totalUsed / totalStorage) * 100) : 0;
        return {
            drives,
            totalStorage,
            totalUsed,
            totalFree,
            totalUsagePercent
        };
    }
    catch {
        return {
            drives: [],
            totalStorage: 0,
            totalUsed: 0,
            totalFree: 0,
            totalUsagePercent: 0
        };
    }
}
/**
 * Get system information using systeminformation
 */
async function getSystemInfo() {
    try {
        const [osInfo, _system] = await Promise.all([
            si.osInfo(),
            si.system()
        ]);
        return {
            platform: osInfo.platform || 'Unknown',
            hostname: osInfo.hostname || 'Unknown',
            uptime: Math.floor(si.time().uptime || 0),
            loadAverage: [] // Load average not available on Windows
        };
    }
    catch {
        return {
            platform: 'Unknown',
            hostname: 'Unknown',
            uptime: 0,
            loadAverage: []
        };
    }
}
/**
 * Get database statistics
 */
async function getDatabaseStats() {
    try {
        // Import models dynamically to avoid circular dependencies
        const { Song } = await Promise.resolve().then(() => __importStar(require('../models/Song')));
        const totalSongs = await Song.countDocuments();
        return {
            totalSongs,
        };
    }
    catch {
        // Return zeros if database is not available
        return {
            totalSongs: 0,
        };
    }
}
/**
 * Get complete system information
 */
async function getSystemMetrics() {
    const [memory, cpu, storage, system, database] = await Promise.all([
        getMemoryInfo(),
        getCpuInfo(),
        getStorageInfo(),
        getSystemInfo(),
        getDatabaseStats()
    ]);
    return {
        timestamp: new Date().toISOString(),
        memory,
        cpu,
        storage,
        system,
        database
    };
}
/**
 * Format bytes to human readable format
 */
function formatBytes(bytes) {
    if (bytes === 0)
        return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}
/**
 * Format uptime to human readable format
 */
function formatUptime(seconds) {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    if (days > 0) {
        return `${days}d ${hours}h ${minutes}m`;
    }
    else if (hours > 0) {
        return `${hours}h ${minutes}m`;
    }
    else {
        return `${minutes}m`;
    }
}
//# sourceMappingURL=systemMonitor.js.map