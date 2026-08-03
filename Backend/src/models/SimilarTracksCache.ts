import mongoose, { Schema, Document } from "mongoose";

interface ISimilarTrack {
  title: string;
  artists: string;
  score: number;
  sourceArtist: string; // Which artist this track came from (for distribution)
  spotifyId?: string; // Optional: only set when we actually search for it
}

export interface ISimilarTracksCache extends Document {
  trackId: string; // Spotify track ID of the source song
  artist: string;
  track: string;
  similarTracks: ISimilarTrack[];
  source: "track.getSimilar" | "artist.getSimilar";
  cachedAt: Date;
  expiresAt: Date;
}

const SimilarTrackSchema = new Schema({
  title: { type: String, required: true },
  artists: { type: String, required: true },
  score: { type: Number, default: 1.0 },
  sourceArtist: { type: String, required: true }, // Which artist this track came from
  spotifyId: { type: String, required: false }, // Optional Spotify ID
});

const SimilarTracksCacheSchema = new Schema<ISimilarTracksCache>({
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

export const SimilarTracksCache = mongoose.model<ISimilarTracksCache>(
  "SimilarTracksCache",
  SimilarTracksCacheSchema
);
