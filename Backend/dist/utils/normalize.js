"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeString = normalizeString;
exports.normalizeArray = normalizeArray;
exports.normalizeSortedArray = normalizeSortedArray;
exports.makeNormKey = makeNormKey;
function normalizeString(s) {
    if (!s)
        return "";
    return s
        .trim()
        .toLowerCase()
        .replace(/[^\w\s-]/g, "")
        .replace(/\s+/g, " ");
}
function normalizeArray(a) {
    return (a ?? []).map(normalizeString).filter(Boolean);
}
function normalizeSortedArray(a) {
    return normalizeArray(a).sort();
}
function makeNormKey(title, album, artists) {
    const normTitle = normalizeString(title);
    const normAlbum = normalizeString(album);
    const normArtists = normalizeSortedArray(artists);
    return `${normTitle}@@${normAlbum}@@${normArtists.join("|")}`;
}
//# sourceMappingURL=normalize.js.map