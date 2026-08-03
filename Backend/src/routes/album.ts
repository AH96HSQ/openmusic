import { Router } from "express";
import { spotifyClient } from "../clients/spotify";
import { Song } from "../models/Song";
import { mapSpotifyTrackToSong } from "../mappers/spotifyMapper";
import { log } from "../utils/logger";

const router = Router();

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

    log.search(`Album details: ${id}`);
    const albumData = await spotifyClient.getAlbum(id, market) as any;

    // Save album tracks to database
    if (albumData.tracks?.items?.length) {
      const tracks = albumData.tracks.items;
      const trackDocs = tracks.map((track: any) => {
        const enhancedTrack = {
          id: track.id,
          title: track.name,
          album: albumData.name,
          artists: track.artists?.map((a: any) => a.name).filter(Boolean) || [],
          durationMs: track.duration_ms,
          uri: track.uri,
          url: track.external_urls?.spotify,
          popularity: track.popularity || 0,
          market,
          _rawAlbum: { id: albumData.id, images: albumData.images },
          _rawArtists: track.artists || [],
        };
        return mapSpotifyTrackToSong(enhancedTrack);
      });

      // Save tracks in parallel
      const savePromises = trackDocs.map((doc: any) => 
        Song.findByIdAndUpdate(doc._id, doc, { upsert: true, new: true })
          .catch((err: any) => log.error(`Failed to save track ${doc._id}:`, err.message))
      );
      
      const savedTracks = await Promise.all(savePromises);
      log.db(`Saved ${trackDocs.length} tracks from album`);
      
      // Add saved tracks to response
      albumData.savedTracks = savedTracks.filter(Boolean); // Filter out any failed saves
    }

    res.json({
      source: "spotify",
      album: albumData,
    });
  } catch (err: any) {
    if (err.message?.includes("404")) {
      res.status(404).json({ error: "Album not found" });
      return;
    }
    next(err);
  }
});

export default router;