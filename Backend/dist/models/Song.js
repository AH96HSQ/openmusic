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
exports.Song = void 0;
const mongoose_1 = __importStar(require("mongoose"));
const SongSchema = new mongoose_1.Schema({
    _id: { type: String, required: true },
    title: { type: String, required: true },
    album: { type: String },
    artists: { type: [String], default: [] },
    durationMs: { type: Number },
    norm: {
        title: { type: String, index: true, required: true },
        album: { type: String, index: true },
        artists: { type: [String], index: true, default: [] },
        key: { type: String, index: true, required: true },
    },
    ext: {
        spotify: {
            id: { type: String, index: true, sparse: true, unique: false },
            uri: String,
            url: String,
            popularity: Number,
            market: String,
            albumId: String,
            artistIds: [String],
        },
    },
    artwork: {
        source: { type: String },
        images: [
            {
                url: { type: String, required: true },
                width: Number,
                height: Number,
                _id: false,
            },
        ],
        albumId: String,
    },
}, { timestamps: true, versionKey: false, _id: false });
// text search
SongSchema.index({ title: "text", album: "text", artists: "text" }, { name: "song_text", weights: { title: 10, artists: 5, album: 3 } });
// exact identity by normalized key
SongSchema.index({ "norm.key": 1 }, { name: "song_norm_key" });
exports.Song = mongoose_1.default.model("Song", SongSchema);
//# sourceMappingURL=Song.js.map