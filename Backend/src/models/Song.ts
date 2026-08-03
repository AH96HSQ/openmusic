import mongoose, { Schema } from "mongoose";

/**
 * Represents a song in the database. The _id is the Spotify track ID.
 */
export interface ISong {
  _id: string;

  // core identity
  title: string;
  album?: string;
  artists: string[];
  durationMs?: number;

  // normalized fields for search
  norm: {
    title: string;
    album?: string;
    artists: string[];
    key: string; // stable identity key (title@@album@@artist1|artist2)
  };

  ext?: {
    spotify?: {
      id: string;
      uri?: string;
      url?: string;
      popularity?: number;
      market?: string;
      albumId?: string; // Spotify album ID for easy navigation
      artistIds?: string[]; // Spotify artist IDs for easy navigation
    };
  };

  artwork?: {
    source: "spotify";
    images: Array<{ url: string; width?: number; height?: number }>;
    albumId?: string;
  };

  createdAt?: Date;
  updatedAt?: Date;
}

const SongSchema = new Schema<ISong>(
  {
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
  },
  { timestamps: true, versionKey: false, _id: false }
);

// text search
SongSchema.index(
  { title: "text", album: "text", artists: "text" },
  { name: "song_text", weights: { title: 10, artists: 5, album: 3 } }
);

// exact identity by normalized key
SongSchema.index({ "norm.key": 1 }, { name: "song_norm_key" });

export const Song = mongoose.model<ISong>("Song", SongSchema);