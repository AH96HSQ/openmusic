"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapSpotifyTrackToSong = mapSpotifyTrackToSong;
const normalize_1 = require("../utils/normalize");
const normKey_1 = require("../utils/normKey");
// helper: keep all images; client can pick best size later
function mapImages(album) {
    const images = (album?.images ?? [])
        .filter((im) => !!im?.url)
        .map((im) => ({ url: im.url, width: im.width, height: im.height }));
    return { albumId: album?.id, images };
}
function mapSpotifyTrackToSong(t) {
    const normTitle = (0, normalize_1.normalizeString)(t.title);
    const normAlbum = (0, normalize_1.normalizeString)(t.album);
    const normArtists = (0, normalize_1.normalizeArray)(t.artists).sort();
    const key = (0, normKey_1.makeNormKey)(t.title, t.album, t.artists);
    const doc = {
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
                artistIds: t._rawArtists?.map(a => a.id).filter(Boolean) || [],
            },
        },
    };
    return doc;
}
//# sourceMappingURL=spotifyMapper.js.map