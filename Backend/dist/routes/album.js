"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const spotify_1 = require("../clients/spotify");
const Song_1 = require("../models/Song");
const spotifyMapper_1 = require("../mappers/spotifyMapper");
const logger_1 = require("../utils/logger");
const router = (0, express_1.Router)();
/**
 * GET /v1/album/:id
 * Get album details from Spotify by album ID
 */
router.get("/:id", async (req, res, next) => {
    try {
        const { id } = req.params;
        const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");
        if (!id) {
            res.status(400).json({ error: "Missing album ID" });
            return;
        }
        logger_1.log.search(`Album details: ${id}`);
        const albumData = await spotify_1.spotifyClient.getAlbum(id, market);
        // Save album tracks to database
        if (albumData.tracks?.items?.length) {
            const tracks = albumData.tracks.items;
            const trackDocs = tracks.map((track) => {
                const enhancedTrack = {
                    id: track.id,
                    title: track.name,
                    album: albumData.name,
                    artists: track.artists?.map((a) => a.name).filter(Boolean) || [],
                    durationMs: track.duration_ms,
                    uri: track.uri,
                    url: track.external_urls?.spotify,
                    popularity: track.popularity || 0,
                    market,
                    _rawAlbum: { id: albumData.id, images: albumData.images },
                    _rawArtists: track.artists || [],
                };
                return (0, spotifyMapper_1.mapSpotifyTrackToSong)(enhancedTrack);
            });
            // Save tracks in parallel
            const savePromises = trackDocs.map((doc) => Song_1.Song.findByIdAndUpdate(doc._id, doc, { upsert: true, new: true })
                .catch((err) => logger_1.log.error(`Failed to save track ${doc._id}:`, err.message)));
            const savedTracks = await Promise.all(savePromises);
            logger_1.log.db(`Saved ${trackDocs.length} tracks from album`);
            // Add saved tracks to response
            albumData.savedTracks = savedTracks.filter(Boolean); // Filter out any failed saves
        }
        res.json({
            source: "spotify",
            album: albumData,
        });
    }
    catch (err) {
        if (err.message?.includes("404")) {
            res.status(404).json({ error: "Album not found" });
            return;
        }
        next(err);
    }
});
exports.default = router;
//# sourceMappingURL=album.js.map