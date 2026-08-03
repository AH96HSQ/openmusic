"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.LastFmService = void 0;
const axios_1 = __importDefault(require("axios"));
const LASTFM_API_BASE = "http://ws.audioscrobbler.com/2.0/";
const LASTFM_API_KEY = process.env.LASTFM_API_KEY;
class LastFmService {
    /**
     * Get similar tracks from Last.fm based on a track
     * Falls back to similar artists' top tracks if no similar tracks found
     * @param artist - Artist name
     * @param track - Track title
     * @param limit - Number of similar tracks to return (max 100)
     */
    static async getSimilarTracks(artist, track, limit = 20) {
        try {
            const response = await axios_1.default.get(LASTFM_API_BASE, {
                params: {
                    method: "track.getSimilar",
                    artist: artist,
                    track: track,
                    api_key: LASTFM_API_KEY,
                    format: "json",
                    limit: Math.min(limit, 100),
                },
                timeout: 30000,
            });
            if (response.data?.similartracks?.track) {
                const tracks = Array.isArray(response.data.similartracks.track)
                    ? response.data.similartracks.track
                    : [response.data.similartracks.track];
                if (tracks.length > 0) {
                    console.log(`[LastFM] Found ${tracks.length} similar tracks for "${track}" by ${artist}`);
                    return tracks;
                }
            }
            // Fallback: No similar tracks found, try similar artists
            console.log(`[LastFM] No similar tracks found for "${track}", trying similar artists for ${artist}`);
            return await this.getSimilarArtistsTopTracks(artist, limit);
        }
        catch (error) {
            if (axios_1.default.isAxiosError(error)) {
                console.error(`[LastFM] Error fetching similar tracks: ${error.response?.status} - ${error.message}`);
            }
            else {
                console.error(`[LastFM] Error fetching similar tracks:`, error);
            }
            // Try fallback on error too
            try {
                console.log(`[LastFM] Attempting fallback to similar artists for ${artist}`);
                return await this.getSimilarArtistsTopTracks(artist, limit);
            }
            catch (fallbackError) {
                console.error(`[LastFM] Fallback also failed:`, fallbackError);
                return [];
            }
        }
    }
    /**
     * Fallback method: Get main artist's top tracks + similar artists' top tracks
     * @param artist - Artist name
     * @param limit - Number of tracks to return
     */
    static async getSimilarArtistsTopTracks(artist, limit = 20) {
        try {
            const allTracks = [];
            // Step 1: Get main artist's top tracks (priority - 40% of limit)
            const mainArtistTracksLimit = Math.ceil(limit * 0.4);
            console.log(`[LastFM] Fetching ${mainArtistTracksLimit} top tracks from main artist: ${artist}`);
            try {
                const mainArtistResponse = await axios_1.default.get(LASTFM_API_BASE, {
                    params: {
                        method: "artist.getTopTracks",
                        artist: artist,
                        api_key: LASTFM_API_KEY,
                        format: "json",
                        limit: mainArtistTracksLimit,
                    },
                    timeout: 30000,
                });
                const mainArtistTopTracks = mainArtistResponse.data?.toptracks?.track || [];
                const convertedMainTracks = mainArtistTopTracks.map((track) => ({
                    name: track.name,
                    playcount: track.playcount,
                    listeners: track.listeners,
                    mbid: track.mbid,
                    url: track.url,
                    streamable: track.streamable,
                    artist: track.artist,
                    image: track.image,
                    match: "1.0", // Main artist gets perfect match score
                }));
                allTracks.push(...convertedMainTracks);
                console.log(`[LastFM] Got ${convertedMainTracks.length} tracks from main artist`);
            }
            catch (mainArtistError) {
                console.error(`[LastFM] Error fetching main artist top tracks:`, mainArtistError);
            }
            // Step 2: Get similar artists
            const similarArtistsResponse = await axios_1.default.get(LASTFM_API_BASE, {
                params: {
                    method: "artist.getSimilar",
                    artist: artist,
                    api_key: LASTFM_API_KEY,
                    format: "json",
                    limit: 5, // Get top 5 similar artists
                },
                timeout: 30000,
            });
            const similarArtists = similarArtistsResponse.data?.similarartists?.artist || [];
            if (similarArtists.length === 0) {
                console.log(`[LastFM] No similar artists found for ${artist}`);
                return allTracks; // Return only main artist tracks
            }
            console.log(`[LastFM] Found ${similarArtists.length} similar artists for ${artist}`);
            // Step 3: Get top tracks from each similar artist (remaining 60%)
            const remainingLimit = limit - allTracks.length;
            const tracksPerArtist = Math.ceil(remainingLimit / similarArtists.length);
            for (const similarArtist of similarArtists) {
                try {
                    const topTracksResponse = await axios_1.default.get(LASTFM_API_BASE, {
                        params: {
                            method: "artist.getTopTracks",
                            artist: similarArtist.name,
                            api_key: LASTFM_API_KEY,
                            format: "json",
                            limit: tracksPerArtist,
                        },
                        timeout: 30000,
                    });
                    const topTracks = topTracksResponse.data?.toptracks?.track || [];
                    // Convert top tracks to LastFmTrack format
                    const convertedTracks = topTracks.map((track) => ({
                        name: track.name,
                        playcount: track.playcount,
                        listeners: track.listeners,
                        mbid: track.mbid,
                        url: track.url,
                        streamable: track.streamable,
                        artist: track.artist,
                        image: track.image,
                        match: similarArtist.match, // Use artist similarity as track match
                    }));
                    allTracks.push(...convertedTracks);
                    if (allTracks.length >= limit) {
                        break;
                    }
                }
                catch (trackError) {
                    console.error(`[LastFM] Error fetching top tracks for ${similarArtist.name}:`, trackError);
                }
            }
            console.log(`[LastFM] Collected ${allTracks.length} tracks from similar artists`);
            return allTracks.slice(0, limit);
        }
        catch (error) {
            console.error(`[LastFM] Error in getSimilarArtistsTopTracks:`, error);
            return [];
        }
    }
}
exports.LastFmService = LastFmService;
//# sourceMappingURL=lastfm.service.js.map