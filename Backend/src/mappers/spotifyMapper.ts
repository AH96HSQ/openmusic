import { ISong } from "../models/Song";
import { normalizeArray, normalizeString } from "../utils/normalize";
import { makeNormKey } from "../utils/normKey";
import { SpotifyTrackLite } from "../types/music";

// helper: keep all images; client can pick best size later
function mapImages(album?: { id?: string; images?: Array<{ url: string; width?: number; height?: number }> }) {
  const images = (album?.images ?? [])
    .filter((im) => !!im?.url)
    .map((im) => ({ url: im.url, width: im.width, height: im.height }));
  return { albumId: album?.id, images };
}

export function mapSpotifyTrackToSong(
  t: SpotifyTrackLite & {
    _rawAlbum?: { id?: string; images?: Array<{ url: string; width?: number; height?: number }> };
    _rawArtists?: Array<{ id?: string; name?: string }>;
  }
): ISong {
  const normTitle = normalizeString(t.title);
  const normAlbum = normalizeString(t.album);
  const normArtists = normalizeArray(t.artists).sort();
  const key = makeNormKey(t.title, t.album, t.artists);

  const doc: ISong = {
    _id: t.id,
    title: t.title,
    album: t.album || undefined,
    artists: t.artists,
    durationMs: t.durationMs,
    norm: {
      title: normTitle,
      album: normAlbum || undefined,
      artists: normArtists,
      key, // <-- REQUIRED now
    },
    artwork: t._rawAlbum ? { source: "spotify", ...mapImages(t._rawAlbum) } : undefined,
    ext: {
      spotify: {
        id: t.id,
        uri: t.uri,
        url: t.url,
        popularity: t.popularity,
        market: t.market,
        albumId: t._rawAlbum?.id,
        artistIds: t._rawArtists?.map(a => a.id).filter(Boolean) as string[] || [],
      },
    },
  };

  return doc;
}