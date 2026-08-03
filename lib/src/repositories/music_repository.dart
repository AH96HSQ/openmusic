import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/artist.dart';

/// Repository for music metadata operations (albums, artists, track details)
class MusicRepository with ChangeNotifier {
  MusicRepository({required String baseUrl})
    : _base = baseUrl.replaceAll(RegExp(r'/$'), ''),
      _dio = Dio(BaseOptions(headers: {'Accept': 'application/json'}));

  final String _base;
  final Dio _dio;

  /// Get track details with album and artist IDs
  Future<TrackDetails> getTrackDetails(
    String trackId, {
    String market = 'US',
  }) async {
    debugPrint(
      'albums and artists playback: MusicRepository.getTrackDetails called for trackId: $trackId, market: $market',
    );

    final uri = Uri.parse(
      '$_base/v1/track/$trackId/details',
    ).replace(queryParameters: {'market': market});

    debugPrint('albums and artists playback: Making API request to: $uri');

    final resp = await _dio.getUri(uri);
    debugPrint(
      'albums and artists playback: API response status: ${resp.statusCode}',
    );
    debugPrint(
      'albums and artists playback: API response data type: ${resp.data.runtimeType}',
    );

    if (resp.statusCode != 200) {
      debugPrint(
        'albums and artists playback: API request failed with status ${resp.statusCode}: ${resp.data}',
      );
      throw Exception('HTTP ${resp.statusCode}: ${resp.data}');
    }

    final data = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : jsonDecode(resp.data as String) as Map<String, dynamic>;

    debugPrint(
      'albums and artists playback: Parsed API response data keys: ${data.keys.toList()}',
    );

    final trackDetails = TrackDetails.fromJson(data);
    debugPrint(
      'albums and artists playback: Successfully created TrackDetails object for trackId: $trackId',
    );

    return trackDetails;
  }

  /// Get complete track details response (for saving to database)
  Future<Map<String, dynamic>> getTrackDetailsRaw(
    String trackId, {
    String market = 'US',
  }) async {
    debugPrint(
      'albums and artists playback: MusicRepository.getTrackDetailsRaw called for trackId: $trackId, market: $market',
    );

    final uri = Uri.parse(
      '$_base/v1/track/$trackId/details',
    ).replace(queryParameters: {'market': market});

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.data}');
    }

    final data = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : jsonDecode(resp.data as String) as Map<String, dynamic>;

    return data;
  }

  /// Get album details with all tracks
  Future<Album> getAlbum(String albumId, {String market = 'US'}) async {
    final uri = Uri.parse(
      '$_base/v1/album/$albumId',
    ).replace(queryParameters: {'market': market});

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.data}');
    }

    final data = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : jsonDecode(resp.data as String) as Map<String, dynamic>;

    return Album.fromJson(data);
  }

  /// Get artist details
  Future<Artist> getArtist(String artistId) async {
    final uri = Uri.parse('$_base/v1/artist/$artistId');

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.data}');
    }

    final data = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : jsonDecode(resp.data as String) as Map<String, dynamic>;

    return Artist.fromJson(data);
  }

  /// Get artist's top tracks
  Future<ArtistTopTracks> getArtistTopTracks(
    String artistId, {
    String market = 'US',
  }) async {
    final uri = Uri.parse(
      '$_base/v1/artist/$artistId/top-tracks',
    ).replace(queryParameters: {'market': market});

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.data}');
    }

    final data = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : jsonDecode(resp.data as String) as Map<String, dynamic>;

    return ArtistTopTracks.fromJson(data);
  }

  /// Get artist's related artists (using TasteDive + Spotify)
  Future<List<String>> getRelatedArtists(String artistId) async {
    final uri = Uri.parse('$_base/v1/artist/$artistId/related-artists');

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.data}');
    }

    final data = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : jsonDecode(resp.data as String) as Map<String, dynamic>;

    final artists = (data['similarArtists'] as List?) ?? [];
    return artists.map((a) => a as String).toList();
  }

  /// Get artist's albums
  Future<ArtistAlbums> getArtistAlbums(
    String artistId, {
    int limit = 20,
    int offset = 0,
    String includeGroups = 'album,single',
    String market = 'US',
  }) async {
    final uri = Uri.parse('$_base/v1/artist/$artistId/albums').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'include_groups': includeGroups,
        'market': market,
      },
    );

    final resp = await _dio.getUri(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.data}');
    }

    final data = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : jsonDecode(resp.data as String) as Map<String, dynamic>;

    return ArtistAlbums.fromJson(data);
  }
}
