/// Model for album data from the Spotify API
class Album {
  final String id;
  final String name;
  final List<String> artists;
  final String? releaseDate;
  final int? totalTracks;
  final List<AlbumImage> images;
  final String? spotifyUrl;
  final List<AlbumTrack> tracks;

  const Album({
    required this.id,
    required this.name,
    required this.artists,
    this.releaseDate,
    this.totalTracks,
    required this.images,
    this.spotifyUrl,
    required this.tracks,
  });

  /// Parse from Spotify API response (direct format)
  factory Album.fromSpotifyJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      name: json['name'] as String,
      artists:
          (json['artists'] as List?)
              ?.map((a) => a['name'] as String)
              .toList() ??
          [],
      releaseDate: json['release_date'] as String?,
      totalTracks: json['total_tracks'] as int?,
      images:
          (json['images'] as List?)
              ?.map((i) => AlbumImage.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      spotifyUrl: json['external_urls']?['spotify'] as String?,
      tracks:
          (json['tracks']?['items'] as List?)
              ?.map((t) => AlbumTrack.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Parse from backend response (wrapped in 'album' key) - kept for compatibility
  factory Album.fromJson(Map<String, dynamic> json) {
    // Check if data is wrapped in 'album' key (backend format)
    if (json.containsKey('album')) {
      final albumData = json['album'] as Map<String, dynamic>;
      return Album.fromSpotifyJson(albumData);
    }
    // Direct Spotify format
    return Album.fromSpotifyJson(json);
  }
}

/// Model for album artwork images
class AlbumImage {
  final String url;
  final int? width;
  final int? height;

  const AlbumImage({required this.url, this.width, this.height});

  factory AlbumImage.fromJson(Map<String, dynamic> json) {
    return AlbumImage(
      url: json['url'] as String,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}

/// Model for tracks within an album
class AlbumTrack {
  final String id;
  final String name;
  final List<String> artists;
  final int? durationMs;
  final int trackNumber;
  final String? spotifyUrl;

  const AlbumTrack({
    required this.id,
    required this.name,
    required this.artists,
    this.durationMs,
    required this.trackNumber,
    this.spotifyUrl,
  });

  factory AlbumTrack.fromJson(Map<String, dynamic> json) {
    return AlbumTrack(
      id: json['id'] as String,
      name: json['name'] as String,
      artists:
          (json['artists'] as List?)
              ?.map((a) => a['name'] as String)
              .toList() ??
          [],
      durationMs: json['duration_ms'] as int?,
      trackNumber: json['track_number'] as int? ?? 1,
      spotifyUrl: json['external_urls']?['spotify'] as String?,
    );
  }
}
