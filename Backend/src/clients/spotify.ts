import axios, { AxiosInstance } from "axios";
import { SpotifyTrackLite } from "../types/music";

type SpotifyToken = {
  access_token: string;
  token_type: "Bearer";
  expires_in: number; // seconds
  _obtained_at: number; // ms since epoch
};

type SpotifySearchResponse = {
  tracks?: {
    items: Array<{
      id: string;
      name: string;
      duration_ms: number;
      uri: string;
      external_urls?: { spotify?: string };
      popularity?: number;
      album?: {
        id?: string;
        name?: string;
        images?: Array<{ url: string; width?: number; height?: number }>;
      };
      artists?: Array<{ name?: string }>;
    }>;
  };
};

type TrackItem = NonNullable<SpotifySearchResponse["tracks"]>["items"][number];

class SpotifyClient {
  private http: AxiosInstance;
  private token?: SpotifyToken;

  constructor(
    private clientId = process.env.SPOTIFY_CLIENT_ID!,
    private clientSecret = process.env.SPOTIFY_CLIENT_SECRET!
  ) {
    if (!this.clientId || !this.clientSecret) {
      throw new Error("Spotify creds missing in env");
    }
    
    this.http = axios.create({
      baseURL: "https://api.spotify.com/v1",
      timeout: 30_000,
    });
  }

  private tokenValid(t?: SpotifyToken): boolean {
    if (!t) return false;
    const now = Date.now();
    // refresh 30s early to be safe
    return now < t._obtained_at + (t.expires_in - 30) * 1000;
  }

  private async getToken(): Promise<string> {
    if (this.tokenValid(this.token)) return this.token!.access_token;

    const auth = Buffer.from(`${this.clientId}:${this.clientSecret}`).toString("base64");
    const res = await axios.post<Omit<SpotifyToken, "_obtained_at">>(
      "https://accounts.spotify.com/api/token",
      new URLSearchParams({ grant_type: "client_credentials" }),
      {
        headers: {
          Authorization: `Basic ${auth}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        timeout: 30_000,
      }
    );

    this.token = { ...res.data, _obtained_at: Date.now() };
    return this.token.access_token;
  }

  private async authedGet<T>(url: string, params: Record<string, any> = {}): Promise<T> {
    const token = await this.getToken();

    const r = await this.http.get<T>(url, {
      params,
      headers: { Authorization: `Bearer ${token}` },
      validateStatus: (s) => s < 500,
    });

    if (r.status === 429) {
      const raHeader = r.headers["retry-after"];
      const ra = Number(Array.isArray(raHeader) ? raHeader[0] : raHeader) || 1;
      await new Promise((ok) => setTimeout(ok, Math.min(ra, 5) * 1000));
      // single retry
      return this.authedGet<T>(url, params);
    }

    if (r.status >= 400) {
      throw new Error(`Spotify ${r.status}: ${JSON.stringify(r.data)}`);
    }

    return r.data;
  }

  /** Search tracks; supports pagination via limit/offset. */
  async searchTracks(
    q: string,
    limit = 15,
    market = process.env.SPOTIFY_MARKET || "US",
    offset = 0
  ): Promise<
    (SpotifyTrackLite & {
      _rawAlbum?: { id?: string; images?: Array<{ url: string; width?: number; height?: number }> };
    })[]
  > {
    // Spotify allows max 50 per page. We will request up to 50 per request and
    // follow the `tracks.next` URL when the caller asks for more items than a
    // single page. We also deduplicate by track id while aggregating.
    const desiredTotal = Math.max(Math.floor(limit), 1);
    const perRequest = Math.min(Math.max(desiredTotal, 1), 50);

    let url: string | undefined = "/search";
    let params: Record<string, any> | undefined = {
      q,
      type: "track",
      market,
      limit: perRequest,
      offset: Math.max(offset, 0),
    };

    const accumulated: TrackItem[] = [];
    const seen = new Set<string>();

    // Small delay between follow-up requests to be kind to rate limits. Tunable.
    const interRequestDelayMs = 200;

    while (url && accumulated.length < desiredTotal) {
      const data = await this.authedGet<SpotifySearchResponse>(url, params || {});
      const items: TrackItem[] = data.tracks && Array.isArray(data.tracks.items) ? (data.tracks.items as TrackItem[]) : [];

      for (const t of items) {
        if (!t || !t.id) continue;
        if (seen.has(t.id)) continue;
        seen.add(t.id);
        accumulated.push(t);
        if (accumulated.length >= desiredTotal) break;
      }

      // If there's no next page, break; otherwise follow the next URL.
      const nextUrl = (data.tracks as any)?.next as string | undefined;
      if (!nextUrl) break;

      // Prepare for next iteration: use the absolute nextUrl and clear params so
      // authedGet doesn't append old params. axios accepts absolute URLs.
      url = nextUrl;
      params = undefined;

      // Delay a bit between requests to reduce chance of hitting rate limits.
      if (accumulated.length < desiredTotal) {
        await new Promise((ok) => setTimeout(ok, interRequestDelayMs));
      }
    }

    return accumulated.map((t: TrackItem) => ({
      id: t.id,
      title: t.name,
      album: t.album?.name ?? "",
      artists: (t.artists ?? []).map((a) => a.name || "").filter((name) => Boolean(name)),
      durationMs: t.duration_ms,
      uri: t.uri,
      url: t.external_urls?.spotify,
      popularity: t.popularity ?? 0,
      market,
      _rawAlbum: t.album ? { id: t.album.id, images: t.album.images } : undefined,
    }));
  }

  /** Search tracks by artist name specifically */
  async searchTracksByArtist(
    artistName: string,
    limit = 15,
    market = process.env.SPOTIFY_MARKET || "US",
    offset = 0
  ) {
    const query = `artist:"${artistName}"`;
    return this.searchTracks(query, limit, market, offset);
  }

  /** Search tracks by album name specifically */
  async searchTracksByAlbum(
    albumName: string,
    limit = 15,
    market = process.env.SPOTIFY_MARKET || "US",
    offset = 0
  ) {
    const query = `album:"${albumName}"`;
    return this.searchTracks(query, limit, market, offset);
  }

  /** Search tracks by track title specifically */
  async searchTracksByTitle(
    trackTitle: string,
    limit = 15,
    market = process.env.SPOTIFY_MARKET || "US",
    offset = 0
  ) {
    const query = `track:"${trackTitle}"`;
    return this.searchTracks(query, limit, market, offset);
  }

  /** Get album details by Spotify album ID */
  async getAlbum(albumId: string, market = process.env.SPOTIFY_MARKET || "US") {
    return this.authedGet(`/albums/${albumId}`, { market });
  }

  /** Get artist details by Spotify artist ID */
  async getArtist(artistId: string) {
    return this.authedGet(`/artists/${artistId}`);
  }

  /** Get artist's top tracks */
  async getArtistTopTracks(artistId: string, market = process.env.SPOTIFY_MARKET || "US") {
    return this.authedGet(`/artists/${artistId}/top-tracks`, { market });
  }

  /** Get artist's albums */
  async getArtistAlbums(
    artistId: string,
    limit = 20,
    offset = 0,
    includeGroups = "album,single",
    market = process.env.SPOTIFY_MARKET || "US"
  ) {
    return this.authedGet(`/artists/${artistId}/albums`, {
      limit: Math.min(limit, 50),
      offset: Math.max(offset, 0),
      include_groups: includeGroups,
      market,
    });
  }

  /** Get track details by Spotify track ID */
  async getTrack(trackId: string, market = process.env.SPOTIFY_MARKET || "US") {
    return this.authedGet(`/tracks/${trackId}`, { market });
  }

  /** Search track by ISRC code */
  async searchByISRC(isrc: string, market = process.env.SPOTIFY_MARKET || "US") {
    const query = `isrc:${isrc}`;
    const results = await this.searchTracks(query, 1, market, 0);
    return results.length > 0 ? results[0] : null;
  }
}

export const spotifyClient = new SpotifyClient();
export default spotifyClient;