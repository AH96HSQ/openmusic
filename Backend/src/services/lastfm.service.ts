import axios from "axios";

const LASTFM_API_BASE = "http://ws.audioscrobbler.com/2.0/";
const LASTFM_API_KEY = process.env.LASTFM_API_KEY;

interface LastFmTrack {
  name: string;
  playcount: string;
  listeners: string;
  mbid: string;
  url: string;
  streamable: string;
  artist: {
    name: string;
    mbid: string;
    url: string;
  };
  image: Array<{
    "#text": string;
    size: string;
  }>;
  match?: string;
}

interface SimilarTracksResponse {
  similartracks: {
    track: LastFmTrack[];
    "@attr": {
      artist: string;
    };
  };
}

interface SimilarArtistsResponse {
  similarartists: {
    artist: Array<{
      name: string;
      mbid: string;
      match: string;
      url: string;
      image: Array<{
        "#text": string;
        size: string;
      }>;
    }>;
  };
}

interface TopTracksResponse {
  toptracks: {
    track: Array<{
      name: string;
      playcount: string;
      listeners: string;
      mbid: string;
      url: string;
      streamable: string;
      artist: {
        name: string;
        mbid: string;
        url: string;
      };
      image: Array<{
        "#text": string;
        size: string;
      }>;
    }>;
  };
}

export class LastFmService {
  /**
   * Get similar tracks from Last.fm based on a track
   * Falls back to similar artists' top tracks if no similar tracks found
   * @param artist - Artist name
   * @param track - Track title
   * @param limit - Number of similar tracks to return (max 100)
   */
  static async getSimilarTracks(
    artist: string,
    track: string,
    limit: number = 20
  ): Promise<LastFmTrack[]> {
    try {
      const response = await axios.get<SimilarTracksResponse>(LASTFM_API_BASE, {
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
      
    } catch (error) {
      if (axios.isAxiosError(error)) {
        console.error(
          `[LastFM] Error fetching similar tracks: ${error.response?.status} - ${error.message}`
        );
      } else {
        console.error(`[LastFM] Error fetching similar tracks:`, error);
      }
      
      // Try fallback on error too
      try {
        console.log(`[LastFM] Attempting fallback to similar artists for ${artist}`);
        return await this.getSimilarArtistsTopTracks(artist, limit);
      } catch (fallbackError) {
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
  static async getSimilarArtistsTopTracks(
    artist: string,
    limit: number = 20
  ): Promise<LastFmTrack[]> {
    try {
      const allTracks: LastFmTrack[] = [];
      
      // Step 1: Get main artist's top tracks (priority - 40% of limit)
      const mainArtistTracksLimit = Math.ceil(limit * 0.4);
      console.log(`[LastFM] Fetching ${mainArtistTracksLimit} top tracks from main artist: ${artist}`);
      
      try {
        const mainArtistResponse = await axios.get<TopTracksResponse>(
          LASTFM_API_BASE,
          {
            params: {
              method: "artist.getTopTracks",
              artist: artist,
              api_key: LASTFM_API_KEY,
              format: "json",
              limit: mainArtistTracksLimit,
            },
            timeout: 30000,
          }
        );

        const mainArtistTopTracks = mainArtistResponse.data?.toptracks?.track || [];
        const convertedMainTracks: LastFmTrack[] = mainArtistTopTracks.map((track) => ({
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
      } catch (mainArtistError) {
        console.error(`[LastFM] Error fetching main artist top tracks:`, mainArtistError);
      }
      
      // Step 2: Get similar artists
      const similarArtistsResponse = await axios.get<SimilarArtistsResponse>(
        LASTFM_API_BASE,
        {
          params: {
            method: "artist.getSimilar",
            artist: artist,
            api_key: LASTFM_API_KEY,
            format: "json",
            limit: 5, // Get top 5 similar artists
          },
          timeout: 30000,
        }
      );

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
          const topTracksResponse = await axios.get<TopTracksResponse>(
            LASTFM_API_BASE,
            {
              params: {
                method: "artist.getTopTracks",
                artist: similarArtist.name,
                api_key: LASTFM_API_KEY,
                format: "json",
                limit: tracksPerArtist,
              },
              timeout: 30000,
            }
          );

          const topTracks = topTracksResponse.data?.toptracks?.track || [];
          
          // Convert top tracks to LastFmTrack format
          const convertedTracks: LastFmTrack[] = topTracks.map((track) => ({
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
        } catch (trackError) {
          console.error(
            `[LastFM] Error fetching top tracks for ${similarArtist.name}:`,
            trackError
          );
        }
      }

      console.log(`[LastFM] Collected ${allTracks.length} tracks from similar artists`);
      return allTracks.slice(0, limit);
      
    } catch (error) {
      console.error(`[LastFM] Error in getSimilarArtistsTopTracks:`, error);
      return [];
    }
  }

}
