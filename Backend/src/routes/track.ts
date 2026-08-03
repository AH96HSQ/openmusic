import { Router } from "express";
import { spotifyClient } from "../clients/spotify";
import { Song } from "../models/Song";
import { mapSpotifyTrackToSong } from "../mappers/spotifyMapper";
import { log } from "../utils/logger";

const router = Router();

/**
 * GET /v1/track/:id/details
 * Get track details with album and artist IDs, enriching database if needed
 */
router.get("/:id/details", async (req, res, next) => {
  try {
    const { id } = req.params;
    const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");

    console.log(`[Track Details] Endpoint called for id: ${id}, market: ${market}`);

    if (!id) {
      console.log(`albums and artists playback: ERROR - Missing track ID`);
      res.status(400).json({ error: "Missing track ID" });
      return;
    }

    // First, check if we have this track in our database with IDs
    console.log(`albums and artists playback: Checking database for existing track: ${id}`);
    let song = await Song.findById(id).lean();
    console.log(`albums and artists playback: Database lookup result: ${song ? 'found' : 'not found'}`);
    
    if (song) {
      console.log(`albums and artists playback: Existing song has albumId: ${song.ext?.spotify?.albumId}, artistIds: ${JSON.stringify(song.ext?.spotify?.artistIds)}`);
    }
    
    if (song && song.ext?.spotify?.albumId && song.ext?.spotify?.artistIds?.length) {
      // We have the track with IDs already
      console.log(`albums and artists playback: Track found in database with IDs, returning cached version`);
      log.search(`Track details (cached): ${id}`);
      
      // Format to match search results structure
      const fileInfo = { exists: false }; // TODO: Add file check if needed
      res.json({
        source: "database",
        title: song.title,
        album: song.album,
        artists: song.artists,
        durationMs: song.durationMs,
        artwork: song.artwork,
        ext: song.ext,
        _id: song._id,
        file: fileInfo,
      });
      return;
    }

    // Need to fetch from Spotify and enrich our database
    console.log(`albums and artists playback: Track not in database or missing IDs, fetching from Spotify`);
    log.search(`Track details (fetching): ${id}`);
    const trackData = await spotifyClient.getTrack(id, market) as any;
    console.log(`albums and artists playback: Spotify API returned track data: ${JSON.stringify({ id: trackData.id, name: trackData.name, album: trackData.album?.name })}`);

    // Extract album and artist IDs
    const albumId = trackData.album?.id;
    const artistIds = trackData.artists?.map((artist: any) => artist.id).filter(Boolean) || [];
    console.log(`albums and artists playback: Extracted albumId: ${albumId}, artistIds: ${JSON.stringify(artistIds)}`);

    // Create enhanced track data for mapping
    const enhancedTrackData = {
      id: trackData.id,
      title: trackData.name,
      album: trackData.album?.name || "",
      artists: trackData.artists?.map((a: any) => a.name || "").filter(Boolean) || [],
      durationMs: trackData.duration_ms,
      uri: trackData.uri,
      url: trackData.external_urls?.spotify,
      popularity: trackData.popularity || 0,
      market,
      _rawAlbum: trackData.album,
    };

    // Map to our Song format
    console.log(`albums and artists playback: Mapping track data to Song format`);
    const mappedSong = mapSpotifyTrackToSong(enhancedTrackData);
    console.log(`albums and artists playback: Mapped song _id: ${mappedSong._id}, title: ${mappedSong.title}`);
    
    // Add the IDs to the mapped song
    if (mappedSong.ext?.spotify) {
      mappedSong.ext.spotify.albumId = albumId;
      mappedSong.ext.spotify.artistIds = artistIds;
      console.log(`albums and artists playback: Added IDs to mapped song - albumId: ${albumId}, artistIds: ${JSON.stringify(artistIds)}`);
    } else {
      console.log(`albums and artists playback: WARNING - mappedSong.ext.spotify is null/undefined`);
    }

    // Upsert to database (use mappedSong._id, not the requested id, as Spotify may return a different ID)
    console.log(`albums and artists playback: Upserting song to database with id: ${mappedSong._id} (requested: ${id})`);
    const savedSong = await Song.findByIdAndUpdate(
      mappedSong._id,
      mappedSong,
      { upsert: true, new: true }
    );
    console.log(`albums and artists playback: Successfully saved song to database: ${savedSong._id}`);

    log.search(`Track enriched and saved: ${id}`);
    
    // Format to match search results structure
    const fileInfo = { exists: false }; // TODO: Add file check if needed
    const response = {
      source: "spotify",
      title: mappedSong.title,
      album: mappedSong.album,
      artists: mappedSong.artists,
      durationMs: mappedSong.durationMs,
      artwork: mappedSong.artwork,
      ext: mappedSong.ext,
      _id: mappedSong._id,
      file: fileInfo,
    };
    console.log(`albums and artists playback: Sending response with consistent format for track: ${mappedSong._id}`);
    res.json(response);

  } catch (err: any) {
    console.log(`albums and artists playback: ERROR in track details endpoint: ${err.message}`);
    console.log(`albums and artists playback: Error stack: ${err.stack}`);
    
    if (err.message?.includes("404")) {
      console.log(`albums and artists playback: Track not found (404) for id: ${req.params.id}`);
      res.status(404).json({ error: "Track not found" });
      return;
    }
    next(err);
  }
});

export default router;