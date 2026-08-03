"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const lastfm_service_1 = require("../services/lastfm.service");
const spotify_1 = __importDefault(require("../clients/spotify"));
const SimilarTracksCache_1 = require("../models/SimilarTracksCache");
const router = (0, express_1.Router)();
// Helper to delay between requests (rate limiting)
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
// Store active SSE connections
const activeConnections = new Map();
/**
 * GET /v1/recommendations/progress/:sessionId
 * SSE endpoint for real-time progress updates
 */
router.get("/progress/:sessionId", (req, res) => {
    const { sessionId } = req.params;
    // Set SSE headers
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.flushHeaders();
    // Store connection
    activeConnections.set(sessionId, res);
    // Send initial connection message
    res.write(`data: ${JSON.stringify({ type: "connected", sessionId })}\n\n`);
    // Clean up on disconnect
    req.on("close", () => {
        activeConnections.delete(sessionId);
        console.log(`[Recommendations] SSE connection closed for session ${sessionId}`);
    });
});
// Helper to send progress update
function sendProgress(sessionId, current, total, message) {
    const connection = activeConnections.get(sessionId);
    if (connection) {
        const data = {
            type: "progress",
            current,
            total,
            message,
            percentage: Math.round((current / total) * 100),
        };
        connection.write(`data: ${JSON.stringify(data)}\n\n`);
    }
}
/**
 * POST /v1/recommendations/similar
 * Get recommendations based on core songs using Last.fm API with progress tracking
 * NEW APPROACH: Cache raw Last.fm data, only search Spotify for tracks we're actually sending
 */
router.post("/similar", async (req, res) => {
    try {
        const { coreSongs, dislikedSongIds = [], sessionId } = req.body;
        if (!coreSongs || !Array.isArray(coreSongs) || coreSongs.length === 0) {
            return res.status(400).json({
                error: "Invalid request. Provide an array of coreSongs.",
            });
        }
        console.log(`[Recommendations] Processing ${coreSongs.length} core songs for recommendations (session: ${sessionId || "none"})`);
        if (dislikedSongIds.length > 0) {
            console.log(`[Recommendations] Filtering out ${dislikedSongIds.length} disliked songs`);
        }
        const dislikedSet = new Set(dislikedSongIds);
        // STEP 1: Collect all raw recommendations from Last.fm (with caching, NO Spotify searches)
        const rawRecommendations = [];
        for (let i = 0; i < coreSongs.length; i++) {
            const song = coreSongs[i];
            const { id, title, artists, quota } = song;
            // Send progress update
            if (sessionId) {
                sendProgress(sessionId, i + 1, coreSongs.length, `Fetching recommendations for "${title}"...`);
            }
            console.log(`[Recommendations] Fetching ${quota} similar tracks for "${title}" by ${artists}`);
            try {
                // Check cache first
                const cached = await SimilarTracksCache_1.SimilarTracksCache.findOne({ trackId: id });
                const now = new Date();
                let similarTracks;
                if (cached && cached.expiresAt > now) {
                    console.log(`[Recommendations] ✓ Using cached data for "${title}" (${cached.similarTracks.length} tracks)`);
                    similarTracks = cached.similarTracks;
                }
                else {
                    // Fetch from Last.fm and cache the RAW data (no Spotify searches!)
                    console.log(`[Recommendations] 🔍 Fetching fresh data from Last.fm for "${title}"`);
                    // Add delay to avoid rate limiting (500ms between Last.fm requests)
                    if (i > 0) {
                        await delay(500);
                    }
                    const lastfmTracks = await lastfm_service_1.LastFmService.getSimilarTracks(artists, title, 50 // Get 50 tracks to build a good cache
                    );
                    console.log(`[Recommendations] 📦 Got ${lastfmTracks.length} tracks from Last.fm, saving raw data...`);
                    // Save RAW Last.fm data to cache (no Spotify IDs yet)
                    similarTracks = lastfmTracks.map((t) => ({
                        title: t.name,
                        artists: t.artist.name,
                        score: t.match ? parseFloat(t.match) : 1.0,
                    }));
                    // Save to cache
                    const expiresAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000); // 1 week
                    await SimilarTracksCache_1.SimilarTracksCache.findOneAndUpdate({ trackId: id }, {
                        trackId: id,
                        artist: artists,
                        track: title,
                        similarTracks: similarTracks,
                        source: "track.getSimilar",
                        cachedAt: now,
                        expiresAt: expiresAt,
                    }, { upsert: true, new: true });
                    console.log(`[Recommendations] 💾 Cached ${similarTracks.length} raw tracks for "${title}"`);
                }
                // Add tracks to raw recommendations pool (up to quota)
                let added = 0;
                for (const track of similarTracks) {
                    if (added >= quota)
                        break;
                    rawRecommendations.push({
                        title: track.title,
                        artists: track.artists,
                        score: track.score,
                        sourceSong: title,
                    });
                    added++;
                }
                console.log(`[Recommendations] Added ${added}/${quota} raw tracks for "${title}"`);
            }
            catch (error) {
                console.error(`[Recommendations] Error fetching recommendations for "${title}":`, error);
            }
        }
        console.log(`[Recommendations] 📊 Total raw recommendations collected: ${rawRecommendations.length}`);
        // STEP 2: Deduplicate by track name + artist (before searching Spotify)
        const uniqueTracks = new Map();
        for (const track of rawRecommendations) {
            const key = `${track.title.toLowerCase()}|||${track.artists.toLowerCase()}`;
            if (!uniqueTracks.has(key)) {
                uniqueTracks.set(key, track);
            }
        }
        console.log(`[Recommendations] 🔍 After deduplication: ${uniqueTracks.size} unique tracks`);
        // STEP 3: Search Spotify ONLY for the unique tracks we're sending
        console.log(`[Recommendations] 🎵 Now searching Spotify for ${uniqueTracks.size} unique tracks...`);
        const allRecommendations = [];
        const addedIds = new Set();
        let searchCount = 0;
        for (const [_key, track] of uniqueTracks) {
            try {
                searchCount++;
                if (searchCount % 5 === 0) {
                    console.log(`[Recommendations] Searching Spotify ${searchCount}/${uniqueTracks.size}...`);
                    // Send progress update
                    if (sessionId) {
                        sendProgress(sessionId, coreSongs.length, coreSongs.length, `Searching Spotify: ${searchCount}/${uniqueTracks.size} tracks...`);
                    }
                }
                // Add small delay between Spotify searches (100ms per 10 searches)
                if (searchCount > 1 && searchCount % 10 === 0) {
                    await delay(100);
                }
                const query = `track:${track.title} artist:${track.artists}`;
                const results = await spotify_1.default.searchTracks(query, 1);
                if (!results || results.length === 0) {
                    continue;
                }
                const spotifyId = results[0].id;
                // Skip if disliked or already added
                if (addedIds.has(spotifyId) || dislikedSet.has(spotifyId)) {
                    continue;
                }
                allRecommendations.push({
                    id: spotifyId,
                    title: track.title,
                    artists: track.artists,
                    score: track.score,
                });
                addedIds.add(spotifyId);
            }
            catch (error) {
                console.error(`[Recommendations] Error searching Spotify for "${track.title}":`, error);
            }
        }
        console.log(`[Recommendations] ✅ Found ${allRecommendations.length} tracks on Spotify (from ${uniqueTracks.size} unique tracks)`);
        console.log(`[Recommendations] Returning ${allRecommendations.length} total recommendations`);
        // Send final progress update
        if (sessionId) {
            console.log(`[Recommendations] Sending completion event to session ${sessionId}`);
            sendProgress(sessionId, coreSongs.length, coreSongs.length, `Complete! Found ${allRecommendations.length} recommendations`);
            // Send completion event
            const connection = activeConnections.get(sessionId);
            if (connection) {
                connection.write(`data: ${JSON.stringify({ type: "complete", recommendations: allRecommendations.length })}\n\n`);
                console.log(`[Recommendations] Completion event sent`);
            }
        }
        console.log(`[Recommendations] Sending JSON response with ${allRecommendations.length} recommendations`);
        return res.json({
            recommendations: allRecommendations,
            total: allRecommendations.length,
        });
    }
    catch (error) {
        console.error("[Recommendations] Error:", error);
        // Send error to SSE client
        if (req.body.sessionId) {
            const connection = activeConnections.get(req.body.sessionId);
            if (connection) {
                connection.write(`data: ${JSON.stringify({ type: "error", message: error instanceof Error ? error.message : "Unknown error" })}\n\n`);
            }
        }
        return res.status(500).json({
            error: "Failed to generate recommendations",
            message: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
exports.default = router;
//# sourceMappingURL=recommendations_old.js.map