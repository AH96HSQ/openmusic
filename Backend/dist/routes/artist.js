"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const spotify_1 = require("../clients/spotify");
const Song_1 = require("../models/Song");
const spotifyMapper_1 = require("../mappers/spotifyMapper");
const logger_1 = require("../utils/logger");
const router = (0, express_1.Router)();
/**
 * GET /v1/artist/:id
 * Get artist details from Spotify by artist ID
 */
router.get("/:id", async (req, res, next) => {
    try {
        const { id } = req.params;
        if (!id) {
            res.status(400).json({ error: "Missing artist ID" });
            return;
        }
        logger_1.log.search(`Artist details: ${id}`);
        const artistData = await spotify_1.spotifyClient.getArtist(id);
        res.json({
            source: "spotify",
            artist: artistData,
        });
    }
    catch (err) {
        if (err.message?.includes("404")) {
            res.status(404).json({ error: "Artist not found" });
            return;
        }
        next(err);
    }
});
/**
 * GET /v1/artist/:id/top-tracks
 * Get artist's top tracks
 */
router.get("/:id/top-tracks", async (req, res, next) => {
    try {
        const { id } = req.params;
        const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");
        if (!id) {
            res.status(400).json({ error: "Missing artist ID" });
            return;
        }
        logger_1.log.search(`Artist top tracks: ${id}`);
        const topTracks = await spotify_1.spotifyClient.getArtistTopTracks(id, market);
        // Save top tracks to database
        if (topTracks.tracks?.length) {
            const trackDocs = topTracks.tracks.map((track) => {
                const enhancedTrack = {
                    id: track.id,
                    title: track.name,
                    album: track.album?.name || "",
                    artists: track.artists?.map((a) => a.name).filter(Boolean) || [],
                    durationMs: track.duration_ms,
                    uri: track.uri,
                    url: track.external_urls?.spotify,
                    popularity: track.popularity || 0,
                    market,
                    _rawAlbum: track.album,
                    _rawArtists: track.artists || [],
                };
                return (0, spotifyMapper_1.mapSpotifyTrackToSong)(enhancedTrack);
            });
            // Save tracks in parallel
            const savePromises = trackDocs.map((doc) => Song_1.Song.findByIdAndUpdate(doc._id, doc, { upsert: true, new: true })
                .catch((err) => logger_1.log.error(`Failed to save track ${doc._id}:`, err.message)));
            const savedTracks = await Promise.all(savePromises);
            logger_1.log.db(`Saved ${trackDocs.length} top tracks for artist`);
            // Add saved tracks to response
            topTracks.savedTracks = savedTracks.filter(Boolean); // Filter out any failed saves
        }
        res.json({
            source: "spotify",
            artistId: id,
            market,
            topTracks,
        });
    }
    catch (err) {
        if (err.message?.includes("404")) {
            res.status(404).json({ error: "Artist not found" });
            return;
        }
        next(err);
    }
});
/**
 * GET /v1/artist/:id/related-artists
 * Get related artists - currently returns empty array as Spotify's endpoint is deprecated
 * TODO: Implement alternative similar artist discovery method
 */
router.get("/:id/related-artists", async (req, res, next) => {
    const { id } = req.params;
    try {
        if (!id) {
            res.status(400).json({ error: "Missing artist ID" });
            return;
        }
        logger_1.log.search(`Artist related artists: ${id}`);
        console.log(`🎨 Related artists requested for: ${id}`);
        console.log(`⚠️ Returning empty array - similar artist discovery not yet implemented`);
        res.json({
            source: "none",
            artistId: id,
            similarArtists: [],
            message: "Similar artist discovery not yet implemented"
        });
    }
    catch (err) {
        console.error(`❌ Error in related artists endpoint for ${id}:`, err.message);
        next(err);
    }
});
/**
 * GET /v1/artist/:id/albums?limit=20&offset=0&include_groups=album,single
 * Get artist's albums
 */
router.get("/:id/albums", async (req, res, next) => {
    try {
        const { id } = req.params;
        const limit = Math.min(Number(req.query.limit ?? 20), 50);
        const offset = Math.max(Number(req.query.offset ?? 0), 0);
        const includeGroups = String(req.query.include_groups ?? "album,single");
        const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");
        if (!id) {
            res.status(400).json({ error: "Missing artist ID" });
            return;
        }
        logger_1.log.search(`Artist albums: ${id}`);
        const albums = await spotify_1.spotifyClient.getArtistAlbums(id, limit, offset, includeGroups, market);
        res.json({
            source: "spotify",
            artistId: id,
            market,
            includeGroups,
            page: { offset, limit },
            albums,
        });
    }
    catch (err) {
        if (err.message?.includes("404")) {
            res.status(404).json({ error: "Artist not found" });
            return;
        }
        next(err);
    }
});
exports.default = router;
//# sourceMappingURL=artist.js.map