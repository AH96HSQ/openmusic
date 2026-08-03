"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.SimilarTracksCache = void 0;
const mongoose_1 = __importStar(require("mongoose"));
const SimilarTrackSchema = new mongoose_1.Schema({
    title: { type: String, required: true },
    artists: { type: String, required: true },
    score: { type: Number, default: 1.0 },
    sourceArtist: { type: String, required: true }, // Which artist this track came from
    spotifyId: { type: String, required: false }, // Optional Spotify ID
});
const SimilarTracksCacheSchema = new mongoose_1.Schema({
    trackId: { type: String, required: true, unique: true, index: true },
    artist: { type: String, required: true },
    track: { type: String, required: true },
    similarTracks: [SimilarTrackSchema],
    source: {
        type: String,
        enum: ["track.getSimilar", "artist.getSimilar"],
        required: true,
    },
    cachedAt: { type: Date, default: Date.now },
    expiresAt: { type: Date, required: true },
});
// Index for automatic cleanup of expired caches
SimilarTracksCacheSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
exports.SimilarTracksCache = mongoose_1.default.model("SimilarTracksCache", SimilarTracksCacheSchema);
//# sourceMappingURL=SimilarTracksCache.js.map