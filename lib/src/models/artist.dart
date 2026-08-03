/// Model for artist data from the Spotify API
class Artist {
  final String id;
  final String name;
  final List<String> genres;
  final int? popularity;
  final int? followers;
  final List<ArtistImage> images;
  final String? spotifyUrl;

  const Artist({
    required this.id,
    required this.name,
    required this.genres,
    this.popularity,
    this.followers,
    required this.images,
    this.spotifyUrl,
  });

  /// Parse from Spotify API response (direct format)
  factory Artist.fromSpotifyJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: json['name'] as String,
      genres: (json['genres'] as List?)?.map((g) => g as String).toList() ?? [],
      popularity: json['popularity'] as int?,
      followers: json['followers']?['total'] as int?,
      images:
          (json['images'] as List?)
              ?.map((i) => ArtistImage.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      spotifyUrl: json['external_urls']?['spotify'] as String?,
    );
  }

  /// Parse from backend response (wrapped in 'artist' key) - kept for compatibility
  factory Artist.fromJson(Map<String, dynamic> json) {
    // Check if data is wrapped in 'artist' key (backend format)
    if (json.containsKey('artist')) {
      final artistData = json['artist'] as Map<String, dynamic>;
      return Artist.fromSpotifyJson(artistData);
    }
    // Direct Spotify format
    return Artist.fromSpotifyJson(json);
  }
}

/// Model for artist top tracks response
class ArtistTopTracks {
  final String artistId;
  final List<ArtistTrack> tracks;

  const ArtistTopTracks({required this.artistId, required this.tracks});

  /// Parse from Spotify API response (direct format - list of tracks)
  factory ArtistTopTracks.fromSpotifyJson(
    String artistId,
    Map<String, dynamic> json,
  ) {
    final tracks = (json['tracks'] as List?) ?? [];
    return ArtistTopTracks(
      artistId: artistId,
      tracks: tracks
          .map((t) => ArtistTrack.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Parse from backend response - kept for compatibility
  factory ArtistTopTracks.fromJson(Map<String, dynamic> json) {
    return ArtistTopTracks(
      artistId: json['artistId'] as String,
      tracks:
          (json['topTracks']?['tracks'] as List?)
              ?.map((t) => ArtistTrack.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Model for artist images
class ArtistImage {
  final String url;
  final int? width;
  final int? height;

  const ArtistImage({required this.url, this.width, this.height});

  factory ArtistImage.fromJson(Map<String, dynamic> json) {
    return ArtistImage(
      url: json['url'] as String,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}

/// Model for tracks from artist top tracks
class ArtistTrack {
  final String id;
  final String name;
  final String? album;
  final List<String> artists;
  final int? durationMs;
  final int? popularity;
  final String? spotifyUrl;
  final List<ArtistImage> images;

  const ArtistTrack({
    required this.id,
    required this.name,
    this.album,
    required this.artists,
    this.durationMs,
    this.popularity,
    this.spotifyUrl,
    required this.images,
  });

  factory ArtistTrack.fromJson(Map<String, dynamic> json) {
    return ArtistTrack(
      id: json['id'] as String,
      name: json['name'] as String,
      album: json['album']?['name'] as String?,
      artists:
          (json['artists'] as List?)
              ?.map((a) => a['name'] as String)
              .toList() ??
          [],
      durationMs: json['duration_ms'] as int?,
      popularity: json['popularity'] as int?,
      spotifyUrl: json['external_urls']?['spotify'] as String?,
      images:
          (json['album']?['images'] as List?)
              ?.map((i) => ArtistImage.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Model for track details with navigation IDs
class TrackDetails {
  final String id;
  final String name;
  final String? album;
  final List<String> artists;
  final String? albumId;
  final List<String> artistIds;

  const TrackDetails({
    required this.id,
    required this.name,
    this.album,
    required this.artists,
    this.albumId,
    required this.artistIds,
  });

  /// Parse from Spotify API track response (direct format)
  factory TrackDetails.fromSpotifyJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?) ?? [];
    final album = json['album'] as Map<String, dynamic>?;

    return TrackDetails(
      id: json['id'] as String,
      name: json['name'] as String,
      album: album?['name'] as String?,
      artists: artists
          .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      albumId: album?['id'] as String?,
      artistIds: artists
          .map((a) => (a as Map<String, dynamic>)['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }

  /// Parse from backend response - kept for compatibility
  factory TrackDetails.fromJson(Map<String, dynamic> json) {
    // Handle the new format that matches search results
    return TrackDetails(
      id: json['_id'] as String,
      name: json['title'] as String,
      album: json['album'] as String?,
      artists:
          (json['artists'] as List?)?.map((a) => a as String).toList() ?? [],
      albumId: json['ext']?['spotify']?['albumId'] as String?,
      artistIds:
          (json['ext']?['spotify']?['artistIds'] as List?)
              ?.map((id) => id as String)
              .toList() ??
          [],
    );
  }

  @override
  String toString() {
    return 'TrackDetails(id: $id, name: $name, album: $album, artists: $artists, albumId: $albumId, artistIds: $artistIds)';
  }
}

/// Model for artist albums response
class ArtistAlbums {
  final String artistId;
  final List<ArtistAlbum> albums;

  const ArtistAlbums({required this.artistId, required this.albums});

  /// Parse from Spotify API response (direct format - items list)
  factory ArtistAlbums.fromSpotifyJson(
    String artistId,
    Map<String, dynamic> json,
  ) {
    final items = (json['items'] as List?) ?? [];
    return ArtistAlbums(
      artistId: artistId,
      albums: items
          .map((a) => ArtistAlbum.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Parse from backend response - kept for compatibility
  factory ArtistAlbums.fromJson(Map<String, dynamic> json) {
    return ArtistAlbums(
      artistId: json['artistId'] as String,
      albums:
          (json['albums']?['items'] as List?)
              ?.map((a) => ArtistAlbum.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Model for individual albums in artist albums list
class ArtistAlbum {
  final String id;
  final String name;
  final String albumType;
  final String? releaseDate;
  final int? totalTracks;
  final List<ArtistImage> images;
  final String? spotifyUrl;

  const ArtistAlbum({
    required this.id,
    required this.name,
    required this.albumType,
    this.releaseDate,
    this.totalTracks,
    required this.images,
    this.spotifyUrl,
  });

  factory ArtistAlbum.fromJson(Map<String, dynamic> json) {
    return ArtistAlbum(
      id: json['id'] as String,
      name: json['name'] as String,
      albumType: json['album_type'] as String? ?? 'album',
      releaseDate: json['release_date'] as String?,
      totalTracks: json['total_tracks'] as int?,
      images:
          (json['images'] as List?)
              ?.map((i) => ArtistImage.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      spotifyUrl: json['external_urls']?['spotify'] as String?,
    );
  }
}
