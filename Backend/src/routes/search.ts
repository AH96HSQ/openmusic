import { Router } from "express";
import { spotifyClient } from "../clients/spotify";
import { mapSpotifyTrackToSong } from "../mappers/spotifyMapper";
import { Song } from "../models/Song";
import { log } from "../utils/logger";

const router = Router();

// Helper function to handle common search logic
async function handleSearchResults(
  searchFunction: () => Promise<any[]>,
  req: any,
  res: any,
  next: any,
  searchType: string
): Promise<any> {
  try {
    const limit = Math.min(Number(req.query.limit ?? 20), 50);
    const offset = Math.max(Number(req.query.offset ?? 0), 0);
    const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");

    const remote = await searchFunction();

    // Map Spotify results to docs
    let docs: any[] = [];
    try {
      docs = remote.map((t: any) => mapSpotifyTrackToSong(t));

      // Save tracks to database (upsert to avoid duplicates)
      if (docs.length > 0) {
        const savePromises = docs.map(doc =>
          Song.findByIdAndUpdate(
            doc._id,
            doc,
            { upsert: true, new: true }
          ).catch(err => {
            log.error(`Failed to save track ${doc._id}:`, err.message);
          })
        );

        // Execute all saves in parallel
        await Promise.all(savePromises);
        log.db(`Saved ${docs.length} tracks to database`);
      }
    } catch (mapErr) {
      log.error("Search mapping failed:", mapErr);
    }

    const page = docs.slice(0, limit).map((doc: any) => {
      return {
        source: 'spotify' as const,
        title: doc.title,
        album: doc.album,
        artists: doc.artists,
        durationMs: doc.durationMs,
        artwork: doc.artwork,
        ext: doc.ext,
        _id: doc._id,
      };
    });

    log.search(`${searchType} search: ${page.length} results`);
    return {
      searchType,
      market,
      page: { offset, limit, returned: page.length, totalFetched: docs.length },
      counts: {
        localFetched: 0,
        spotifyFetched: docs.length,
      },
      results: page,
    };
  } catch (err: any) {
    next(err);
    return null;
  }
}

/**
 * GET /v1/search?q=&limit=&offset=&market=
 * - default limit: 7
 * - default offset: 0
 * - local-first + spotify
 * - upserts remote hits (upsert safety handled by songRepo using norm.key or spotify id)
 * - returns a page slice after de-dup
 */
router.get("/", async (req, res, next) => {
  try {
    const q = String(req.query.q ?? "").trim();
    const limit = Math.min(Number(req.query.limit ?? 20), 50);
    const offset = Math.max(Number(req.query.offset ?? 0), 0);
    const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");

    if (!q) {
      res.status(400).json({ error: "Missing query 'q'." });
      return;
    }

    const result = await handleSearchResults(
      () => spotifyClient.searchTracks(q, limit, market, offset),
      req,
      res,
      next,
      "general"
    );

    if (result) {
      res.json({
        query: q,
        ...result,
      });
    }
  } catch (err) {
    next(err);
  }
});

/**
 * GET /v1/search/artist?q=&limit=&offset=&market=
 * Search tracks by artist name specifically
 */
router.get("/artist", async (req, res, next) => {
  try {
    const q = String(req.query.q ?? "").trim();
    const limit = Math.min(Number(req.query.limit ?? 20), 50);
    const offset = Math.max(Number(req.query.offset ?? 0), 0);
    const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");

    if (!q) {
      res.status(400).json({ error: "Missing artist query 'q'." });
      return;
    }

    const result = await handleSearchResults(
      () => spotifyClient.searchTracksByArtist(q, limit, market, offset),
      req,
      res,
      next,
      "artist"
    );

    if (result) {
      res.json({
        query: q,
        searchField: "artist",
        ...result,
      });
    }
  } catch (err) {
    next(err);
  }
});

/**
 * GET /v1/search/album?q=&limit=&offset=&market=
 * Search tracks by album name specifically
 */
router.get("/album", async (req, res, next) => {
  try {
    const q = String(req.query.q ?? "").trim();
    const limit = Math.min(Number(req.query.limit ?? 20), 50);
    const offset = Math.max(Number(req.query.offset ?? 0), 0);
    const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");

    if (!q) {
      res.status(400).json({ error: "Missing album query 'q'." });
      return;
    }

    const result = await handleSearchResults(
      () => spotifyClient.searchTracksByAlbum(q, limit, market, offset),
      req,
      res,
      next,
      "album"
    );

    if (result) {
      res.json({
        query: q,
        searchField: "album",
        ...result,
      });
    }
  } catch (err) {
    next(err);
  }
});

/**
 * GET /v1/search/title?q=&limit=&offset=&market=
 * Search tracks by title specifically
 */
router.get("/title", async (req, res, next) => {
  try {
    const q = String(req.query.q ?? "").trim();
    const limit = Math.min(Number(req.query.limit ?? 20), 50);
    const offset = Math.max(Number(req.query.offset ?? 0), 0);
    const market = String(req.query.market ?? process.env.SPOTIFY_MARKET ?? "US");

    if (!q) {
      res.status(400).json({ error: "Missing title query 'q'." });
      return;
    }

    const result = await handleSearchResults(
      () => spotifyClient.searchTracksByTitle(q, limit, market, offset),
      req,
      res,
      next,
      "title"
    );

    if (result) {
      res.json({
        query: q,
        searchField: "title",
        ...result,
      });
    }
  } catch (err) {
    next(err);
  }
});

export default router;
