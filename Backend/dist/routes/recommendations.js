"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const lastfm_service_1 = require("../services/lastfm.service");
const spotify_1 = __importDefault(require("../clients/spotify"));
const SimilarTracksCache_1 = require("../models/SimilarTracksCache");
const Song_1 = require("../models/Song");
const router = (0, express_1.Router)();
// Helper to delay between requests (rate limiting)
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const processingStates = new Map();
// Clean up old states after 10 minutes
setInterval(() => {
    const now = new Date();
    for (const [sessionId, state] of processingStates.entries()) {
        const age = now.getTime() - state.startedAt.getTime();
        if (age > 10 * 60 * 1000) { // 10 minutes
            processingStates.delete(sessionId);
            console.log(`[Recommendations] Cleaned up expired session: ${sessionId}`);
        }
    }
}, 60000); // Check every minute
/**
 * GET /v1/recommendations/status/:sessionId
 * Poll endpoint to check recommendation processing status
 */
router.get("/status/:sessionId", (req, res) => {
    const { sessionId } = req.params;
    const state = processingStates.get(sessionId);
    if (!state) {
        return res.status(404).json({
            error: "Session not found or expired",
        });
    }
    const response = {
        status: state.status,
        progress: state.progress,
    };
    if (state.status === 'complete' && state.result) {
        response.recommendations = state.result;
        response.total = state.result.length;
    }
    if (state.status === 'error' && state.error) {
        response.error = state.error;
    }
    return res.json(response);
});
// Helper to update progress
function updateProgress(sessionId, current, total, message) {
    const state = processingStates.get(sessionId);
    if (state) {
        state.progress = {
            current,
            total,
            message,
            percentage: Math.round((current / total) * 100),
        };
    }
}
/**
 * Helper function to fetch full track details from Spotify
 * Returns complete track data ready for client database insertion
 */
async function fetchFullTrackDetails(trackId) {
    try {
        const trackData = await spotify_1.default.getTrack(trackId, 'US');
        if (!trackData)
            return null;
        // Return complete track object matching client schema
        return {
            id: trackData.id,
            title: trackData.name,
            artists: trackData.artists?.map((a) => a.name).join(', ') || '',
            album: trackData.album?.name || '',
            durationMs: trackData.duration_ms || 0,
            artwork: {
                images: trackData.album?.images || [],
                largest: trackData.album?.images?.[0]?.url || ''
            },
            ext: {
                spotify: {
                    uri: trackData.uri || '',
                    url: trackData.external_urls?.spotify || '',
                    albumId: trackData.album?.id || '',
                    artistIds: trackData.artists?.map((a) => a.id).filter(Boolean) || [],
                    popularity: trackData.popularity || 0
                }
            }
        };
    }
    catch (error) {
        console.error(`[Recommendations] Error fetching details for ${trackId}:`, error);
        return null;
    }
}
/**
 * POST /v1/recommendations/similar
 * Start recommendation processing (async) and return session ID immediately
 */
router.post("/similar", async (req, res) => {
    const { likedSongs, dislikedSongIds = [], likedSongIds = [], sessionId } = req.body;
    if (!likedSongs || !Array.isArray(likedSongs) || likedSongs.length === 0) {
        return res.status(400).json({
            error: "Invalid request. Provide an array of likedSongs with playTime.",
        });
    }
    if (!sessionId) {
        return res.status(400).json({
            error: "Session ID is required",
        });
    }
    // Initialize processing state
    processingStates.set(sessionId, {
        status: 'processing',
        progress: {
            current: 0,
            total: 5, // We'll calculate top 5 songs
            message: 'Analyzing your taste...',
            percentage: 0,
        },
        startedAt: new Date(),
    });
    console.log(`[Recommendations] Started processing ${likedSongs.length} liked songs (session: ${sessionId})`);
    // Return immediately with session ID
    res.json({
        sessionId,
        status: 'processing',
        message: 'Recommendation processing started. Poll /status/:sessionId for updates.',
    });
    // Process recommendations asynchronously
    processRecommendations(sessionId, likedSongs, dislikedSongIds || [], likedSongIds || []).catch((error) => {
        console.error(`[Recommendations] Async processing error for session ${sessionId}:`, error);
    });
    return; // Explicit return to satisfy TypeScript
});
/**
 * Process recommendations asynchronously
 * Now handles ALL liked songs and calculates top 5 server-side
 */
async function processRecommendations(sessionId, likedSongs, dislikedSongIds, likedSongIds) {
    try {
        console.log(`[Recommendations] Processing ${likedSongs.length} liked songs for recommendations (session: ${sessionId})`);
        const totalRecommendations = 20;
        // Filter out songs with Unknown Artist before processing
        const filteredSongs = likedSongs.filter(song => {
            const artistLower = song.artists.toLowerCase();
            const hasUnknownArtist = artistLower.includes('unknown artist') || artistLower === 'unknown';
            if (hasUnknownArtist) {
                console.log(`  ⊘ Skipping "${song.title}" - Unknown Artist`);
            }
            return !hasUnknownArtist;
        });
        console.log(`[Recommendations] Filtered to ${filteredSongs.length} songs (removed ${likedSongs.length - filteredSongs.length} with Unknown Artist)`);
        if (filteredSongs.length === 0) {
            updateProgress(sessionId, 5, 5, 'Error: All liked songs have Unknown Artist');
            throw new Error('All liked songs have Unknown Artist - cannot generate recommendations');
        }
        // 1️⃣ VALIDATE AVAILABILITY - Check which songs exist in Last.fm
        updateProgress(sessionId, 1, 5, "You've been listening to some cool songs!");
        console.log('[Recommendations] Step 1: Validating song availability in Last.fm database...');
        const availableSongs = [];
        const unavailableSongs = [];
        // Sort all songs by playTime descending to check best candidates first
        const sortedAllSongs = [...filteredSongs].sort((a, b) => b.playTime - a.playTime);
        for (let i = 0; i < sortedAllSongs.length; i++) {
            const song = sortedAllSongs[i];
            // Check cache first
            const cached = await SimilarTracksCache_1.SimilarTracksCache.findOne({ trackId: song.id });
            const now = new Date();
            let isAvailable = false;
            if (cached && cached.expiresAt > now && cached.similarTracks && cached.similarTracks.length > 0) {
                // Song is cached and has tracks - it's available!
                console.log(`  ✓ "${song.title}" - Available (cached, ${cached.similarTracks.length} tracks)`);
                isAvailable = true;
            }
            else {
                // Try fetching from Last.fm to validate
                try {
                    // Add delay to avoid rate limiting
                    if (i > 0) {
                        await delay(500);
                    }
                    const lastfmTracks = await lastfm_service_1.LastFmService.getSimilarTracks(song.artists, song.title, 10 // Just check if it exists, don't need all 50
                    );
                    if (lastfmTracks && lastfmTracks.length > 0) {
                        console.log(`  ✓ "${song.title}" - Available (found ${lastfmTracks.length} similar tracks)`);
                        isAvailable = true;
                    }
                    else {
                        console.log(`  ✗ "${song.title}" - Not available (no similar tracks found, likely device file)`);
                    }
                }
                catch (error) {
                    console.log(`  ✗ "${song.title}" - Not available (Last.fm error: ${error})`);
                }
            }
            if (isAvailable) {
                availableSongs.push(song);
                if (availableSongs.length >= 10) {
                    console.log(`[Recommendations] Found 10 available songs, stopping validation check`);
                    break; // We have enough, stop checking
                }
            }
            else {
                unavailableSongs.push(song);
            }
        }
        console.log(`[Recommendations] Availability check complete: ${availableSongs.length} available, ${unavailableSongs.length} unavailable`);
        if (availableSongs.length === 0) {
            throw new Error('No songs available in Last.fm database. Try adding more online songs to your library.');
        }
        // 2️⃣ CALCULATE WEIGHTS - Only for available songs
        updateProgress(sessionId, 2, 5, "I'm smarter than chatgpt by the way!");
        console.log('[Recommendations] Step 2: Calculating weights based on available songs...');
        const totalDuration = availableSongs.reduce((sum, song) => sum + song.playTime, 0);
        // Take top 10 available songs
        const top10Songs = availableSongs.slice(0, Math.min(10, availableSongs.length));
        console.log(`[Recommendations] Top ${top10Songs.length} available songs:`);
        top10Songs.forEach((song, i) => {
            const weight = ((song.playTime / totalDuration) * 100).toFixed(1);
            console.log(`  ${i + 1}. "${song.title}" by ${song.artists} (${weight}%)`);
        });
        // 3️⃣ DISTRIBUTE QUOTA - Proportional to play time
        updateProgress(sessionId, 3, 5, 'Listening to every music on the planet...');
        const coreSongs = top10Songs.map(song => {
            const weight = song.playTime / totalDuration;
            let quota = Math.round(weight * totalRecommendations);
            quota = Math.max(1, Math.min(quota, totalRecommendations)); // Clamp between 1 and 20
            return {
                id: song.id,
                title: song.title,
                artists: song.artists,
                quota,
            };
        });
        // Adjust quotas to always try for 20 recommendations (regardless of song count)
        let totalQuota = coreSongs.reduce((sum, s) => sum + s.quota, 0);
        // Add more to reach 20 (proportionally to top songs)
        while (totalQuota < totalRecommendations && coreSongs.length > 0) {
            coreSongs[0].quota++; // Give extra to top song
            totalQuota++;
        }
        // Remove if over 20 (shouldn't happen with proper rounding)
        while (totalQuota > totalRecommendations && coreSongs.length > 0) {
            const lastWithMoreThan1 = coreSongs.reverse().find(s => s.quota > 1);
            if (lastWithMoreThan1)
                lastWithMoreThan1.quota--;
            coreSongs.reverse();
            totalQuota--;
        }
        console.log(`[Recommendations] Quota distribution: ${coreSongs.map(s => `${s.quota}`).join(', ')} = ${totalQuota} total`);
        if (dislikedSongIds.length > 0) {
            console.log(`[Recommendations] Filtering out ${dislikedSongIds.length} disliked songs`);
        }
        if (likedSongIds.length > 0) {
            console.log(`[Recommendations] Filtering out ${likedSongIds.length} liked songs`);
        }
        const dislikedSet = new Set(dislikedSongIds);
        const likedSet = new Set(likedSongIds);
        const addedIds = new Set();
        const allRecommendations = [];
        // 4️⃣ FETCH RECOMMENDATIONS - All songs are pre-validated, no fallback needed
        updateProgress(sessionId, 4, 5, 'Almost there...');
        console.log('[Recommendations] Step 4: Fetching recommendations (all songs pre-validated)...');
        for (let i = 0; i < coreSongs.length; i++) {
            const song = coreSongs[i];
            const { id, title, artists, quota } = song;
            // Don't update progress per song - keep the "Almost there..." message
            // updateProgress() is not called here anymore
            console.log(`[Recommendations] [${i + 1}/${coreSongs.length}] Fetching ${quota} similar tracks for "${title}" by ${artists}`);
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
                        sourceArtist: t.artist.name, // Save which artist this track came from
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
                // Search Spotify and add tracks immediately (with artist distribution)
                let added = 0;
                // Group tracks by source artist for equal distribution
                const tracksByArtist = new Map();
                for (const track of similarTracks) {
                    const artistName = track.sourceArtist || track.artists;
                    if (!tracksByArtist.has(artistName)) {
                        tracksByArtist.set(artistName, []);
                    }
                    tracksByArtist.get(artistName).push(track);
                }
                // Sort artists: main artist (exact match with 'artists' param) first, then by score
                const sortedArtists = Array.from(tracksByArtist.entries()).sort((a, b) => {
                    const aIsMainArtist = a[0].toLowerCase() === artists.toLowerCase();
                    const bIsMainArtist = b[0].toLowerCase() === artists.toLowerCase();
                    if (aIsMainArtist && !bIsMainArtist)
                        return -1;
                    if (!aIsMainArtist && bIsMainArtist)
                        return 1;
                    // Sort by highest score if neither is main artist
                    const aMaxScore = Math.max(...a[1].map(t => t.score));
                    const bMaxScore = Math.max(...b[1].map(t => t.score));
                    return bMaxScore - aMaxScore;
                });
                console.log(`[Recommendations] Distributing ${quota} tracks across ${sortedArtists.length} artists`);
                // Round-robin distribution: take one track from each artist until quota is met
                const artistIndexes = new Map();
                sortedArtists.forEach(([artist]) => artistIndexes.set(artist, 0));
                let currentArtistIdx = 0;
                let attempts = 0;
                const maxAttempts = similarTracks.length;
                while (added < quota && attempts < maxAttempts) {
                    attempts++;
                    // Get next artist in round-robin
                    const [currentArtist, tracks] = sortedArtists[currentArtistIdx];
                    const trackIdx = artistIndexes.get(currentArtist);
                    // Move to next artist for next iteration
                    currentArtistIdx = (currentArtistIdx + 1) % sortedArtists.length;
                    // Check if this artist has more tracks
                    if (trackIdx >= tracks.length) {
                        continue;
                    }
                    const track = tracks[trackIdx];
                    artistIndexes.set(currentArtist, trackIdx + 1);
                    try {
                        // OPTIMIZATION: Check if track exists in our database BEFORE Spotify search
                        const existingInDb = await Song_1.Song.findOne({
                            $or: [
                                { 'norm.title': track.title.toLowerCase(), 'norm.artists': { $in: [track.artists.toLowerCase()] } },
                                { title: track.title, artists: { $in: [track.artists] } }
                            ]
                        }).select('_id').lean();
                        if (existingInDb) {
                            const dbTrackId = existingInDb._id;
                            // Check if it's in disliked/liked/already added
                            if (addedIds.has(dbTrackId) || dislikedSet.has(dbTrackId) || likedSet.has(dbTrackId)) {
                                // Skip silently - we already have it
                                continue;
                            }
                        }
                        // Search Spotify for this track
                        const query = `track:${track.title} artist:${track.artists}`;
                        const results = await spotify_1.default.searchTracks(query, 1);
                        if (!results || results.length === 0) {
                            continue; // Try next track
                        }
                        const spotifyId = results[0].id;
                        // Skip if liked, disliked, or already added (duplicate check)
                        if (addedIds.has(spotifyId) || dislikedSet.has(spotifyId) || likedSet.has(spotifyId)) {
                            console.log(`[Recommendations] ⏭️  Skipping duplicate/disliked/liked: "${track.title}"`);
                            continue; // Try next track from cache
                        }
                        // Add to recommendations
                        allRecommendations.push({
                            id: spotifyId,
                            title: track.title,
                            artists: track.artists,
                            score: track.score,
                        });
                        addedIds.add(spotifyId);
                        added++;
                        // Small delay between Spotify searches
                        if (added % 10 === 0) {
                            await delay(100);
                        }
                    }
                    catch (error) {
                        console.error(`[Recommendations] Error searching Spotify for "${track.title}":`, error);
                        // Continue to next track
                    }
                }
                console.log(`[Recommendations] Added ${added}/${quota} tracks for "${title}" (${sortedArtists.length} artists, ${attempts} attempts)`);
            }
            catch (error) {
                console.error(`[Recommendations] ❌ Error fetching recommendations for "${title}":`, error);
                // Continue with next song - all songs are pre-validated so this shouldn't happen
            }
        }
        console.log(`[Recommendations] ✅ Complete! Found ${allRecommendations.length} total recommendations`);
        // Fetch full details for all recommendations before sending to client
        console.log(`[Recommendations] 📥 Fetching full details for ${allRecommendations.length} tracks...`);
        updateProgress(sessionId, 5, 5, 'Preparing song details...');
        const enrichedRecommendations = [];
        // Fetch in batches of 5 to avoid overwhelming Spotify API
        for (let i = 0; i < allRecommendations.length; i += 5) {
            const batch = allRecommendations.slice(i, i + 5);
            const batchPromises = batch.map(async (rec) => {
                const fullDetails = await fetchFullTrackDetails(rec.id);
                if (fullDetails) {
                    // Merge recommendation score with full track details
                    return {
                        ...fullDetails,
                        score: rec.score
                    };
                }
                // Fallback to basic data if fetch fails
                return rec;
            });
            const batchResults = await Promise.all(batchPromises);
            enrichedRecommendations.push(...batchResults);
            // Small delay between batches
            if (i + 5 < allRecommendations.length) {
                await delay(200);
            }
        }
        console.log(`[Recommendations] ✅ Enriched ${enrichedRecommendations.length}/${allRecommendations.length} tracks with full details`);
        // Mark as complete with enriched data
        const state = processingStates.get(sessionId);
        if (state) {
            state.status = 'complete';
            state.result = enrichedRecommendations;
            state.progress = {
                current: coreSongs.length,
                total: coreSongs.length,
                message: `Done! Found ${enrichedRecommendations.length} songs you'll love`,
                percentage: 100,
            };
        }
    }
    catch (error) {
        console.error(`[Recommendations] Error processing session ${sessionId}:`, error);
        const state = processingStates.get(sessionId);
        if (state) {
            state.status = 'error';
            state.error = error instanceof Error ? error.message : 'Unknown error';
        }
    }
}
exports.default = router;
//# sourceMappingURL=recommendations.js.map