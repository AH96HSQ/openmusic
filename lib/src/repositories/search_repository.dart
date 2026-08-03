import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/track_hit.dart';
import '../services/spotify_client.dart';
import '../data/database_helper.dart';

/// SearchRepository - Uses on-device Spotify API when online, local database when offline
/// Checks internet connectivity before each search to determine the best source
class SearchRepository with ChangeNotifier {
  SearchRepository({required String baseUrl}) {
    // baseUrl is kept for backwards compatibility but not used for search
    // Search now happens directly on-device via Spotify API
    _init();
  }

  bool _initialized = false;

  // Cache connectivity status briefly to avoid pinging on every keystroke
  bool? _lastConnectivityStatus;
  DateTime? _lastConnectivityCheck;
  static const _connectivityCacheDuration = Duration(seconds: 10);

  Future<void> _init() async {
    if (_initialized) return;
    await SpotifyClient.instance.init();
    _initialized = true;
  }

  /// Check internet connectivity with a real HTTP request to Google
  /// Uses a short timeout (2 seconds) to quickly detect offline state
  /// Caches result for 10 seconds to avoid excessive network requests
  Future<bool> _isOnline() async {
    // Use cached result if recent enough
    if (_lastConnectivityStatus != null && _lastConnectivityCheck != null) {
      final elapsed = DateTime.now().difference(_lastConnectivityCheck!);
      if (elapsed < _connectivityCacheDuration) {
        debugPrint(
          'SearchRepository: Using cached connectivity: ${_lastConnectivityStatus! ? "ONLINE" : "OFFLINE"}',
        );
        return _lastConnectivityStatus!;
      }
    }

    try {
      debugPrint(
        'SearchRepository: Checking connectivity with HTTP request...',
      );

      // Use actual HTTP HEAD request - more reliable than DNS lookup
      // Google's generate_204 endpoint is specifically designed for connectivity checks
      final response = await http
          .head(Uri.parse('https://www.google.com/generate_204'))
          .timeout(const Duration(seconds: 2));

      final isOnline = response.statusCode == 204 || response.statusCode == 200;

      _lastConnectivityStatus = isOnline;
      _lastConnectivityCheck = DateTime.now();

      debugPrint(
        'SearchRepository: Connectivity check - ${isOnline ? "ONLINE" : "OFFLINE"} (status: ${response.statusCode})',
      );
      return isOnline;
    } on SocketException catch (e) {
      debugPrint(
        'SearchRepository: Connectivity check failed (SocketException) - OFFLINE: $e',
      );
      _lastConnectivityStatus = false;
      _lastConnectivityCheck = DateTime.now();
      return false;
    } catch (e) {
      debugPrint('SearchRepository: Connectivity check failed - OFFLINE ($e)');
      _lastConnectivityStatus = false;
      _lastConnectivityCheck = DateTime.now();
      return false;
    }
  }

  /// Convert local database song to TrackHit format
  TrackHit _dbSongToTrackHit(Map<String, dynamic> song) {
    return TrackHit.fromSearchItem({
      '_id': song['id'],
      'id': song['id'],
      'title': song['title'] ?? 'Unknown',
      'album': song['album'],
      'artists': _parseArtists(song['artists']),
      'durationMs': song['duration_ms'],
      'artwork': {'images': _parseArtwork(song['artwork'])},
      'ext': _parseExt(song['ext']),
    });
  }

  List<String> _parseArtists(dynamic artists) {
    if (artists == null) return [];
    if (artists is List) return artists.cast<String>();
    if (artists is String) {
      // Could be comma-separated or JSON array
      if (artists.startsWith('[')) {
        try {
          final parsed = artists
              .replaceAll('[', '')
              .replaceAll(']', '')
              .replaceAll('"', '');
          return parsed
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        } catch (_) {}
      }
      return artists
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _parseArtwork(dynamic artwork) {
    if (artwork == null) return [];
    if (artwork is String && artwork.isNotEmpty) {
      try {
        // If it's a JSON string, try to parse it
        if (artwork.startsWith('{') || artwork.startsWith('[')) {
          return [];
        }
        // Otherwise treat as single URL
        return [
          {'url': artwork, 'width': 300, 'height': 300},
        ];
      } catch (_) {}
    }
    return [];
  }

  Map<String, dynamic>? _parseExt(dynamic ext) {
    if (ext == null) return null;
    if (ext is Map) return Map<String, dynamic>.from(ext);
    if (ext is String && ext.isNotEmpty) {
      try {
        // Parse JSON string if needed
        return null; // Let TrackHit handle parsing
      } catch (_) {}
    }
    return null;
  }

  /// Search local database for songs
  Future<List<TrackHit>> _searchLocal(
    String query, {
    String? filterType,
    int limit = 50,
  }) async {
    debugPrint(
      'SearchRepository: Searching locally for "$query" (filter: $filterType)',
    );

    try {
      final results = await DatabaseHelper.instance.searchLibrarySongs(
        query: query,
        filterType: filterType,
      );

      debugPrint('SearchRepository: Found ${results.length} local results');

      return results
          .take(limit)
          .map((song) => _dbSongToTrackHit(song))
          .toList();
    } catch (e) {
      debugPrint('SearchRepository: Local search error: $e');
      return [];
    }
  }

  Future<List<TrackHit>> searchTracks(
    String query, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    await _init();

    // Check connectivity first
    final isOnline = await _isOnline();

    if (!isOnline) {
      debugPrint('SearchRepository: Offline - searching locally for "$query"');
      return _searchLocal(query, limit: limit);
    }

    debugPrint('SearchRepository: Online - searching "$query" via Spotify API');

    try {
      final tracks = await SpotifyClient.instance.searchTracks(
        query,
        limit: limit,
        offset: offset,
        market: market,
      );

      // Convert SpotifyTrack to TrackHit format
      return tracks
          .map((t) => TrackHit.fromSearchItem(t.toSearchItem()))
          .toList();
    } catch (e) {
      debugPrint(
        'SearchRepository: Spotify search error: $e - falling back to local',
      );
      // Fall back to local search on error
      return _searchLocal(query, limit: limit);
    }
  }

  Future<List<TrackHit>> searchByArtist(
    String query, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    await _init();

    // Check connectivity first
    final isOnline = await _isOnline();

    if (!isOnline) {
      debugPrint(
        'SearchRepository: Offline - searching locally by artist "$query"',
      );
      return _searchLocal(query, filterType: 'artist', limit: limit);
    }

    debugPrint(
      'SearchRepository: Online - searching by artist "$query" via Spotify API',
    );

    try {
      final tracks = await SpotifyClient.instance.searchTracksByArtist(
        query,
        limit: limit,
        offset: offset,
        market: market,
      );

      return tracks
          .map((t) => TrackHit.fromSearchItem(t.toSearchItem()))
          .toList();
    } catch (e) {
      debugPrint(
        'SearchRepository: Artist search error: $e - falling back to local',
      );
      return _searchLocal(query, filterType: 'artist', limit: limit);
    }
  }

  Future<List<TrackHit>> searchByAlbum(
    String query, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    await _init();

    // Check connectivity first
    final isOnline = await _isOnline();

    if (!isOnline) {
      debugPrint(
        'SearchRepository: Offline - searching locally by album "$query"',
      );
      return _searchLocal(query, filterType: 'album', limit: limit);
    }

    debugPrint(
      'SearchRepository: Online - searching by album "$query" via Spotify API',
    );

    try {
      final tracks = await SpotifyClient.instance.searchTracksByAlbum(
        query,
        limit: limit,
        offset: offset,
        market: market,
      );

      return tracks
          .map((t) => TrackHit.fromSearchItem(t.toSearchItem()))
          .toList();
    } catch (e) {
      debugPrint(
        'SearchRepository: Album search error: $e - falling back to local',
      );
      return _searchLocal(query, filterType: 'album', limit: limit);
    }
  }

  Future<List<TrackHit>> searchByTrack(
    String query, {
    int limit = 20,
    int offset = 0,
    String market = 'US',
  }) async {
    await _init();

    // Check connectivity first
    final isOnline = await _isOnline();

    if (!isOnline) {
      debugPrint(
        'SearchRepository: Offline - searching locally by track "$query"',
      );
      return _searchLocal(query, filterType: 'track', limit: limit);
    }

    debugPrint(
      'SearchRepository: Online - searching by track "$query" via Spotify API',
    );

    try {
      final tracks = await SpotifyClient.instance.searchTracksByTitle(
        query,
        limit: limit,
        offset: offset,
        market: market,
      );

      return tracks
          .map((t) => TrackHit.fromSearchItem(t.toSearchItem()))
          .toList();
    } catch (e) {
      debugPrint(
        'SearchRepository: Track search error: $e - falling back to local',
      );
      return _searchLocal(query, filterType: 'track', limit: limit);
    }
  }

  /// Force clear connectivity cache (useful when network state changes)
  void clearConnectivityCache() {
    _lastConnectivityStatus = null;
    _lastConnectivityCheck = null;
  }

  /// Public method to check if device is online
  /// Uses cached result if available
  Future<bool> checkConnectivity() async {
    return _isOnline();
  }

  /// Get last known connectivity status (synchronous, may be stale)
  bool? get lastKnownConnectivityStatus => _lastConnectivityStatus;
}
