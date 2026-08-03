"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const sync_js_1 = require("../services/sync.js");
const router = (0, express_1.Router)();
/**
 * Smart sync - Compare timestamps and sync in the right direction
 * POST /v1/sync/smart
 *
 * Body: {
 *   userId: string,
 *   clientTimestamp: number (milliseconds since epoch),
 *   data?: { songs, playlists, recommendations, ... } // Only needed if uploading
 * }
 *
 * Response: {
 *   action: 'upload' | 'download' | 'none',
 *   serverTimestamp: number | null,
 *   data?: { songs, playlists, ... }, // Only present if action is 'download'
 *   message: string
 * }
 */
router.post('/smart', async (req, res) => {
    try {
        const { userId, clientTimestamp, data } = req.body;
        if (!userId) {
            return res.status(400).json({ error: 'User ID is required' });
        }
        if (typeof clientTimestamp !== 'number') {
            return res.status(400).json({ error: 'Client timestamp (number) is required' });
        }
        const result = await sync_js_1.syncController.smartSync(userId, clientTimestamp, data);
        return res.json(result);
    }
    catch (error) {
        console.error('Smart sync error:', error);
        return res.status(500).json({ error: 'Smart sync failed' });
    }
});
/**
 * Upload sync data (songs + playlists)
 * POST /v1/sync/upload
 */
router.post('/upload', async (req, res) => {
    try {
        const { userId, songs, playlists, recommendations, recommendationsTimestamp, syncedAt, clientTimestamp } = req.body;
        if (!userId || !songs || !playlists) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        const serverTimestamp = await sync_js_1.syncController.uploadSyncData(userId, {
            songs,
            playlists,
            recommendations,
            recommendationsTimestamp,
            syncedAt,
        }, clientTimestamp);
        return res.json({
            success: true,
            message: 'Data synced successfully',
            syncedAt,
            serverTimestamp,
        });
    }
    catch (error) {
        console.error('Sync upload error:', error);
        return res.status(500).json({ error: 'Failed to sync data' });
    }
});
/**
 * Restore sync data
 * GET /v1/sync/restore/:userId
 */
router.get('/restore/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        if (!userId) {
            return res.status(400).json({ error: 'User ID is required' });
        }
        const data = await sync_js_1.syncController.getSyncData(userId);
        if (!data) {
            return res.status(404).json({ error: 'No backup found for this account' });
        }
        return res.json(data);
    }
    catch (error) {
        console.error('Sync restore error:', error);
        return res.status(500).json({ error: 'Failed to restore data' });
    }
});
/**
 * Get sync status (last sync time)
 * GET /v1/sync/status/:userId
 */
router.get('/status/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        if (!userId) {
            return res.status(400).json({ error: 'User ID is required' });
        }
        const status = await sync_js_1.syncController.getSyncStatus(userId);
        return res.json(status);
    }
    catch (error) {
        console.error('Sync status error:', error);
        return res.status(500).json({ error: 'Failed to get sync status' });
    }
});
/**
 * Delete sync data
 * DELETE /v1/sync/:userId
 */
router.delete('/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        if (!userId) {
            return res.status(400).json({ error: 'User ID is required' });
        }
        await sync_js_1.syncController.deleteSyncData(userId);
        return res.json({
            success: true,
            message: 'Sync data deleted successfully',
        });
    }
    catch (error) {
        console.error('Sync delete error:', error);
        return res.status(500).json({ error: 'Failed to delete sync data' });
    }
});
exports.default = router;
//# sourceMappingURL=sync.js.map