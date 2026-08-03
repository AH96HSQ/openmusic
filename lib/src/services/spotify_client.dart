import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'spotify_credentials_service.dart';

/// Token response from Spotify
class _SpotifyToken {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final DateTime obtainedAt;

  _SpotifyToken({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.obtainedAt,
  });

  bool get isValid {
    final now = DateTime.now();
    // Refresh 30 seconds early to be safe
    final expiresAt = obtainedAt.add(Duration(seconds: expiresIn - 30));
    return now.isBefore(expiresAt);
  }
}

/// Spotify track from search results
class SpotifyTrack {
  final String id;
  final String title;
  final String album;
  final String? albumId;
  final List<String> artists;
  final List<String> artistIds;
  final int durationMs;
  final String uri;
  final String? url;
  final int popularity;
  final String market;
  final List<Map<String, dynamic>> images;

  SpotifyTrack({
    required this.id,
    required this.title,
    required this.album,
    this.albumId,
    required this.artists,
    required this.artistIds,
    required this.durationMs,
    required this.uri,
    this.url,
    required this.popularity,
    required this.market,
    required this.images,
  });

  /// Convert to the format expected by the app's TrackHit model
  Map<String, dynamic> toSearchItem() {
    return {
      '_id': id,
      'id': id,
      'title': title,
      'album': album,
      'artists': artists,
      'durationMs': durationMs,
      'artwork': {'images': images},
      'ext': {
        'spotify': {
          'url': url ?? 'https://open.spotify.com/track/$id',
          'uri': uri,
          'id': id,
        },
      },
      // Include album and artist IDs for navigation
      'albumId': albumId,
      'artistIds': artistIds,
    };
  }

  factory SpotifyTrack.fromJson(Map<String, dynamic> json, String market) {
    final album = json['album'] as Map<String, dynamic>?;
    final artists = (json['artists'] as List?) ?? [];
    final images = (album?['images'] as List?) ?? [];

    return SpotifyTrack(
      id: json['id'] as String,
      title: json['name'] as String,
      album: album?['name'] as String? ?? '',
      albumId: album?['id'] as String?,
      artists: artists
          .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      artistIds: artists
          .map((a) => (a as Map<String, dynamic>)['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
      durationMs: json['duration_ms'] as int? ?? 0,
      uri: json['uri'] as String? ?? '',
      url: json['external_urls']?['spotify'] as String?,
      popularity: json['popularity'] as int? ?? 0,
      market: market,
      images: images
          .map(
            (img) => <String, dynamic>{
              'url': img['url'] as String? ?? '',
              'width': img['width'] as int? ?? 0,
              'height': img['height'] as int? ?? 0,
            },
          )
          .where((img) => (img['url'] as String).isNotEmpty)
          .toList(),
    );
  }
}

/// On-device Spotify API client
/// Handles authentication and search requests directly from the device
class SpotifyClient {
  static final SpotifyClient instance = SpotifyClient._internal();
  SpotifyClient._internal();

  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const String _apiBaseUrl = 'https://api.spotify.com/v1';

  _SpotifyToken? _token;
  final http.Client _httpClient = http.Client();

  /// Initialize the client
  Future<void> init() async {
    await SpotifyCredentialsService.instance.init();
    debugPrint('SpotifyClient: Initialized');
  }

  /// Get a valid access token, refreshing if necessary
  Future<String> _getToken() async {
    if (_token != null && _token!.isValid) {
      return _token!.accessToken;
    }

    final clientId = SpotifyCredentialsService.instance.clientId;
    final clientSecret = SpotifyCredentialsService.instance.clientSecret;

    debugPrint('SpotifyClient: Fetching new access token');

    try {
      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));

      final response = await _httpClient
          .post(
            Uri.parse(_tokenUrl),
            headers: {
              'Authorization': 'Basic $credentials',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'grant_type=client_credentials',
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception(
          'Token request failed: ${response.statusCode} - ${response.body}',
        );
      }

      final data = jsonDecode(response.body);
      _token = _SpotifyToken(
        accessToken: data['access_token'] as String,
        tokenType: data['token_type'] as String,
        expiresIn: data['expires_in'] as int,
        obtainedAt: DateTime.now(),
      );

      debugPrint(
        'SpotifyClient: Got new access token, expires in ${_token!.expiresIn}s',
      );
      return _token!.accessToken;
    } catch (e) {
      debugPrint('SpotifyClient: Error getting token: $e');
      rethrow;
    }
  }

  /// Make an authenticated GET request to the Spotify API
  Future<Map<String, dynamic>> _authedGet(
    String endpoint, {
    Map<String, String>? params,
  }) async {
    final token = await _getToken();

    var url = '$_apiBaseUrl$endpoint';
    if (params != null && params.isNotEmpty) {
      final queryString = params.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');
      url = '$url?$queryString';
    }

    debugPrint('SpotifyClient: GET $url');

    try {
      final response = await _httpClient
          .get(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));

      // Handle rate limiting
      if (response.statusCode == 429) {
        final retryAfter =
            int.tryParse(response.headers['retry-after'] ?? '1') ?? 1;
        debugPrint('SpotifyClient: Rate limited, waiting ${retryAfter}s');
        await Future.delayed(Duration(seconds: retryAfter.clamp(1, 5)));
        return _authedGet(endpoint, params: params);
      }

      if (response.statusCode >= 400) {
        throw Exception(
          'Spotify API error: ${response.statusCode} - ${response.body}',
        );
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('SpotifyClient: API request failed: $e');
      rethrow;
    }
  }

  /// Search for tracks
  Future<List<SpotifyTrack>> searchTracks(
    String query, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    if (query.trim().isEmpty) return [];

    debugPrint(
      'SpotifyClient: Searching for "$query" (limit: $limit, offset: $offset)',
    );

    final response = await _authedGet(
      '/search',
      params: {
        'q': query,
        'type': 'track',
        'market': market,
        'limit': limit.clamp(1, 50).toString(),
        'offset': offset.clamp(0, 1000).toString(),
      },
    );

    final tracks = response['tracks'] as Map<String, dynamic>?;
    final items = (tracks?['items'] as List?) ?? [];

    final results = items
        .map(
          (item) => SpotifyTrack.fromJson(item as Map<String, dynamic>, market),
        )
        .toList();

    debugPrint('SpotifyClient: Found ${results.length} tracks');
    return results;
  }

  /// Search tracks by artist name
  Future<List<SpotifyTrack>> searchTracksByArtist(
    String artistName, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    final query = 'artist:"$artistName"';
    return searchTracks(query, limit: limit, offset: offset, market: market);
  }

  /// Search tracks by album name
  Future<List<SpotifyTrack>> searchTracksByAlbum(
    String albumName, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    final query = 'album:"$albumName"';
    return searchTracks(query, limit: limit, offset: offset, market: market);
  }

  /// Search tracks by track title
  Future<List<SpotifyTrack>> searchTracksByTitle(
    String trackTitle, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    final query = 'track:"$trackTitle"';
    return searchTracks(query, limit: limit, offset: offset, market: market);
  }

  /// Get track details by ID
  Future<SpotifyTrack?> getTrack(String trackId, {String market = 'US'}) async {
    try {
      final response = await _authedGet(
        '/tracks/$trackId',
        params: {'market': market},
      );
      return SpotifyTrack.fromJson(response, market);
    } catch (e) {
      debugPrint('SpotifyClient: Error getting track $trackId: $e');
      return null;
    }
  }

  /// Get album details by ID
  Future<Map<String, dynamic>?> getAlbum(
    String albumId, {
    String market = 'US',
  }) async {
    try {
      return await _authedGet('/albums/$albumId', params: {'market': market});
    } catch (e) {
      debugPrint('SpotifyClient: Error getting album $albumId: $e');
      return null;
    }
  }

  /// Get artist details by ID
  Future<Map<String, dynamic>?> getArtist(String artistId) async {
    try {
      return await _authedGet('/artists/$artistId');
    } catch (e) {
      debugPrint('SpotifyClient: Error getting artist $artistId: $e');
      return null;
    }
  }

  /// Get artist's top tracks
  Future<List<SpotifyTrack>> getArtistTopTracks(
    String artistId, {
    String market = 'US',
  }) async {
    try {
      final response = await _authedGet(
        '/artists/$artistId/top-tracks',
        params: {'market': market},
      );
      final tracks = (response['tracks'] as List?) ?? [];
      return tracks
          .map(
            (item) =>
                SpotifyTrack.fromJson(item as Map<String, dynamic>, market),
          )
          .toList();
    } catch (e) {
      debugPrint('SpotifyClient: Error getting artist top tracks: $e');
      return [];
    }
  }

  /// Get artist's albums
  Future<Map<String, dynamic>?> getArtistAlbums(
    String artistId, {
    int limit = 20,
    int offset = 0,
    String includeGroups = 'album,single',
    String market = 'US',
  }) async {
    try {
      return await _authedGet(
        '/artists/$artistId/albums',
        params: {
          'limit': limit.clamp(1, 50).toString(),
          'offset': offset.clamp(0, 1000).toString(),
          'include_groups': includeGroups,
          'market': market,
        },
      );
    } catch (e) {
      debugPrint('SpotifyClient: Error getting artist albums: $e');
      return null;
    }
  }

  /// Dispose the HTTP client
  void dispose() {
    _httpClient.close();
  }
}
