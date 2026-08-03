"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncController = void 0;
const mongoose_1 = __importDefault(require("mongoose"));
// Define Mongoose schema for sync data
const userSyncDataSchema = new mongoose_1.default.Schema({
    userId: { type: String, required: true, unique: true, index: true },
    songs: { type: Array, required: true, default: [] },
    playlists: { type: Array, required: true, default: [] },
    recommendations: { type: Array, default: [] },
    recommendationsTimestamp: { type: String, default: null },
    syncedAt: { type: String, required: true },
    // Server timestamp for smart sync (milliseconds since epoch)
    serverTimestamp: { type: Number, required: true, default: () => Date.now() },
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
});
const UserSyncData = mongoose_1.default.model('UserSyncData', userSyncDataSchema);
class SyncController {
    /**
     * Upload sync data for a user
     */
    async uploadSyncData(userId, data, clientTimestamp) {
        const { songs, playlists, recommendations, recommendationsTimestamp, syncedAt } = data;
        const serverTimestamp = clientTimestamp || Date.now();
        // Upsert sync data in MongoDB
        await UserSyncData.findOneAndUpdate({ userId }, {
            userId,
            songs,
            playlists,
            recommendations: recommendations || [],
            recommendationsTimestamp: recommendationsTimestamp || null,
            syncedAt,
            serverTimestamp,
            updatedAt: new Date(),
        }, { upsert: true, new: true });
        console.log(`Sync data uploaded for user ${userId}: ${songs.length} songs, ${playlists.length} playlists, ${recommendations?.length || 0} recommendations, timestamp: ${serverTimestamp}`);
        return serverTimestamp;
    }
    /**
     * Get sync data for a user
     */
    async getSyncData(userId) {
        const syncData = await UserSyncData.findOne({ userId });
        if (!syncData) {
            return null;
        }
        return {
            songs: syncData.songs || [],
            playlists: syncData.playlists || [],
            recommendations: syncData.recommendations || [],
            recommendationsTimestamp: syncData.recommendationsTimestamp || undefined,
            syncedAt: syncData.syncedAt,
        };
    }
    /**
     * Get sync status for a user (includes serverTimestamp)
     */
    async getSyncStatus(userId) {
        const syncData = await UserSyncData.findOne({ userId }, { updatedAt: 1, serverTimestamp: 1 });
        if (!syncData) {
            return {
                hasSyncData: false,
                lastSyncTime: null,
                serverTimestamp: null,
            };
        }
        return {
            hasSyncData: true,
            lastSyncTime: syncData.updatedAt,
            serverTimestamp: syncData.serverTimestamp || syncData.updatedAt?.getTime() || null,
        };
    }
    /**
     * Smart sync - Compare timestamps and determine sync direction
     * Returns: { action, serverTimestamp, data? }
     * action: 'upload' (client should upload), 'download' (client should download), 'none' (already in sync)
     */
    async smartSync(userId, clientTimestamp, clientData) {
        const syncData = await UserSyncData.findOne({ userId });
        // No server data exists
        if (!syncData) {
            if (clientData) {
                // Client has data, upload it
                const newTimestamp = await this.uploadSyncData(userId, clientData, clientTimestamp);
                return {
                    action: 'none',
                    serverTimestamp: newTimestamp,
                    message: 'Initial sync - data uploaded successfully',
                };
            }
            return {
                action: 'none',
                serverTimestamp: null,
                message: 'No data on server or client',
            };
        }
        const serverTimestamp = syncData.serverTimestamp || syncData.updatedAt?.getTime() || 0;
        console.log(`Smart sync for ${userId}: clientTimestamp=${clientTimestamp}, serverTimestamp=${serverTimestamp}`);
        // Server is newer - client should download
        if (serverTimestamp > clientTimestamp) {
            return {
                action: 'download',
                serverTimestamp,
                data: {
                    songs: syncData.songs || [],
                    playlists: syncData.playlists || [],
                    recommendations: syncData.recommendations || [],
                    recommendationsTimestamp: syncData.recommendationsTimestamp || undefined,
                    syncedAt: syncData.syncedAt,
                },
                message: 'Server has newer data - downloading to client',
            };
        }
        // Client is newer - upload client data
        if (clientTimestamp > serverTimestamp && clientData) {
            const newTimestamp = await this.uploadSyncData(userId, clientData, clientTimestamp);
            return {
                action: 'upload',
                serverTimestamp: newTimestamp,
                message: 'Client has newer data - uploaded to server',
            };
        }
        // Timestamps are equal or client is newer but no data provided
        return {
            action: 'none',
            serverTimestamp,
            message: 'Data is already in sync',
        };
    }
    /**
     * Delete sync data for a user
     */
    async deleteSyncData(userId) {
        await UserSyncData.deleteOne({ userId });
        console.log(`Sync data deleted for user ${userId}`);
    }
}
exports.syncController = new SyncController();
//# sourceMappingURL=sync.js.map