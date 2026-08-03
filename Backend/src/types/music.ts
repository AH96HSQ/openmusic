// Shared lightweight types across providers

export type SpotifyTrackLite = {
  id: string;
  title: string;
  album: string;
  artists: string[];
  durationMs: number;
  uri?: string;
  url?: string;
  popularity: number;
  market: string;
};