import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../data/database_helper.dart';

class RecommendationProgress {
  final int current;
  final int total;
  final String message;
  final int percentage;
  final String? secondaryMessage; // Optional second line for track details

  RecommendationProgress({
    required this.current,
    required this.total,
    required this.message,
    required this.percentage,
    this.secondaryMessage,
  });

  factory RecommendationProgress.fromJson(Map<String, dynamic> json) {
    return RecommendationProgress(
      current: json['current'] as int,
      total: json['total'] as int,
      message: json['message'] as String,
      percentage: json['percentage'] as int,
      secondaryMessage: json['secondaryMessage'] as String?,
    );
  }

  RecommendationProgress copyWith({
    int? current,
    int? total,
    String? message,
    int? percentage,
    String? secondaryMessage,
  }) {
    return RecommendationProgress(
      current: current ?? this.current,
      total: total ?? this.total,
      message: message ?? this.message,
      percentage: percentage ?? this.percentage,
      secondaryMessage: secondaryMessage ?? this.secondaryMessage,
    );
  }
}

class RecommendationService {
  static const int totalRecommendations = 20;
  late final String _backendBaseUrl;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  // Progress stream controller
  final StreamController<RecommendationProgress> _progressController =
      StreamController<RecommendationProgress>.broadcast();

  Stream<RecommendationProgress> get progressStream =>
      _progressController.stream;

  RecommendationService() {
    final envBase = dotenv.env['BACKEND_BASE_URL']?.trim();
    _backendBaseUrl = envBase?.isNotEmpty == true
        ? envBase!.replaceAll(RegExp(r'/+$'), '')
        : 'http://localhost:5002';
  }

  void dispose() {
    _progressController.close();
  }

  /// Calculate recommendations using Last.fm API (via Backend)
  ///
  /// 🎧 DAILY RECOMMENDATION ALGORITHM (Server-Side Version)
  /// 1. Send all liked songs with play times to backend
  /// 2. Backend calculates top 10 and weights
  /// 3. Backend fetches similar tracks from Last.fm
  /// 4. Backend handles missing tracks (device files) automatically
  /// 5. Receive final 20 recommendations from backend
  Future<List<Map<String, dynamic>>> calculateRecommendations() async {
    debugPrint(
      '[rec-system] 🎧 Starting Last.fm recommendation calculation...',
    );

    // 1️⃣ Get ONLY liked songs with play time (optimized query)
    List<Map<String, dynamic>> likedSongs = [];
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        // Use optimized query instead of getAllSongs() + filter
        likedSongs = await DatabaseHelper.instance.getLikedSongsWithPlayTime();
        break; // Success, exit retry loop
      } catch (e) {
        if (e.toString().contains('database is locked') &&
            retries < maxRetries - 1) {
          retries++;
          debugPrint(
            '[rec-system] ⚠️ Database locked while reading liked songs, retrying ($retries/$maxRetries)...',
          );
          await Future.delayed(
            Duration(milliseconds: 200 * retries),
          ); // Exponential backoff
        } else {
          rethrow;
        }
      }
    }

    if (likedSongs.isEmpty) {
      throw Exception('No liked songs found. Like some songs first!');
    }

    debugPrint('[rec-system] 📊 Found ${likedSongs.length} liked songs');

    // 2️⃣ All songs already have play time > 0 from the query
    final qualifiedSongs = likedSongs;

    debugPrint('[rec-system] ✓ ${qualifiedSongs.length} qualified songs');

    // 3️⃣ Prepare all liked songs with play times for backend
    final List<Map<String, dynamic>> allLikedSongsData = [];
    for (final song in qualifiedSongs) {
      allLikedSongsData.add({
        'id': song['id'] as String,
        'title': song['title'] ?? 'Unknown',
        'artists': song['artists'] ?? 'Unknown Artist',
        'playTime': (song['play_time'] as int?) ?? 0,
      });
    }

    debugPrint(
      '[rec-system] 🔍 Sending ${allLikedSongsData.length} liked songs to backend',
    );

    // 4️⃣ Get disliked song IDs (with retry for database locks)
    List<String> dislikedSongIds = [];
    retries = 0;

    while (retries < maxRetries) {
      try {
        dislikedSongIds = await DatabaseHelper.instance.getDislikedSongIds();
        break;
      } catch (e) {
        if (e.toString().contains('database is locked') &&
            retries < maxRetries - 1) {
          retries++;
          debugPrint(
            '[rec-system] ⚠️ Database locked while reading disliked songs, retrying ($retries/$maxRetries)...',
          );
          await Future.delayed(Duration(milliseconds: 200 * retries));
        } else {
          rethrow;
        }
      }
    }

    debugPrint(
      '[rec-system] 🚫 Found ${dislikedSongIds.length} disliked songs to filter',
    );

    // Get liked song IDs (filter them out too)
    final likedSongIds = likedSongs
        .map((song) => song['id'] as String)
        .toList();
    debugPrint(
      '[rec-system] ❤️  Found ${likedSongIds.length} liked songs to filter',
    );

    // Generate unique session ID for progress tracking
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      // Start SSE connection for progress updates
      _listenToProgress(sessionId);

      // 5️⃣ Backend does everything: calculates top 10, fetches similar tracks,
      // searches Spotify, handles failures, and returns final 20 recommendations
      final recommendations = await _fetchLastFmSimilar(
        allLikedSongsData,
        dislikedSongIds,
        likedSongIds,
        sessionId,
      );

      debugPrint(
        '[rec-system] 📥 Received ${recommendations.length} recommendations from backend',
      );

      // 6️⃣ Backend sent FULL track details! Just check existence and insert
      debugPrint(
        '[rec-system] 💾 Saving ${recommendations.length} tracks to database...',
      );

      _progressController.add(
        RecommendationProgress(
          current: 0,
          total: recommendations.length,
          message: 'Saving your new songs! (0/${recommendations.length})',
          percentage: 90,
        ),
      );

      int savedCount = 0;
      int skippedCount = 0;

      // Process each recommendation - backend already sent full details!
      for (int i = 0; i < recommendations.length; i++) {
        final track = recommendations[i];
        final trackId = track['id'] as String?;

        if (trackId == null || trackId.isEmpty) {
          debugPrint('[rec-system] Skipping track with no ID');
          continue;
        }

        try {
          // Check if song already exists in database
          final existingSong = await DatabaseHelper.instance.getSong(trackId);

          if (existingSong != null) {
            debugPrint('[rec-system] Track already exists: $trackId');
            skippedCount++;
          } else {
            // Insert new track (backend sent full details!)
            await DatabaseHelper.instance.insertSong(track);
            debugPrint('[rec-system] Saved new track: $trackId');
            savedCount++;
          }
        } catch (e) {
          debugPrint('[rec-system] ⚠️ Error processing $trackId: $e');
        }

        _progressController.add(
          RecommendationProgress(
            current: i + 1,
            total: recommendations.length,
            message: 'Saving songs (${i + 1}/${recommendations.length})',
            percentage: 90 + ((i + 1) / recommendations.length * 10).round(),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 30));
      }

      debugPrint(
        '[rec-system] ✅ Done! Saved $savedCount new, skipped $skippedCount existing',
      );

      // Build final list from recommendations
      final List<Map<String, dynamic>> finalList = recommendations
          .where(
            (track) =>
                track['id'] != null && (track['id'] as String).isNotEmpty,
          )
          .map(
            (track) => {
              'id': track['id'] as String,
              'title': track['title'] ?? 'Unknown',
              'artists': track['artists'] ?? 'Unknown Artist',
              'score': track['score'] ?? 0.0,
            },
          )
          .toList();

      debugPrint(
        '[rec-system] ✅ Final recommendations: ${finalList.length} tracks',
      );
      for (int i = 0; i < finalList.length; i++) {
        final track = finalList[i];
        debugPrint(
          '[rec-system]   ${i + 1}. "${track['title']}" by ${track['artists']}',
        );
      }

      return finalList;
    } catch (e) {
      debugPrint('[rec-system] ❌ Error fetching recommendations: $e');
      rethrow;
    }
  }

  /// Listen to SSE progress updates from backend (DEPRECATED - now using polling)
  void _listenToProgress(String sessionId) {
    // This is kept for backward compatibility but no longer used
    // We now use polling via /status/:sessionId endpoint
    final url = '$_backendBaseUrl/v1/recommendations/status/$sessionId';
    debugPrint('[rec-system] 📡 Connecting to progress stream: $url');

    http.Client()
        .send(http.Request('GET', Uri.parse(url)))
        .then((response) {
          response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                (line) {
                  if (line.startsWith('data: ')) {
                    try {
                      final jsonData = line.substring(
                        6,
                      ); // Remove "data: " prefix
                      final data = jsonDecode(jsonData);

                      if (data['type'] == 'progress') {
                        final progress = RecommendationProgress.fromJson(data);
                        _progressController.add(progress);
                        debugPrint(
                          '[rec-system] 📊 Progress: ${progress.percentage}% - ${progress.message}',
                        );
                      } else if (data['type'] == 'complete') {
                        debugPrint('[rec-system] ✅ Progress stream complete');
                      } else if (data['type'] == 'error') {
                        debugPrint(
                          '[rec-system] ❌ Progress stream error: ${data['message']}',
                        );
                      }
                    } catch (e) {
                      debugPrint('[rec-system] Error parsing SSE data: $e');
                    }
                  }
                },
                onError: (error) {
                  debugPrint('[rec-system] SSE connection error: $error');
                },
                onDone: () {
                  debugPrint('[rec-system] SSE connection closed');
                },
              );
        })
        .catchError((error) {
          debugPrint('[rec-system] Failed to connect to SSE: $error');
        });
  }

  /// Fetch similar tracks from Last.fm API via backend (with polling)
  Future<List<Map<String, dynamic>>> _fetchLastFmSimilar(
    List<Map<String, dynamic>> likedSongsData,
    List<String> dislikedSongIds,
    List<String> likedSongIds,
    String sessionId,
  ) async {
    try {
      // Step 1: Start the processing
      debugPrint('[rec-system] 🚀 Starting async recommendation processing...');
      final startResponse = await _dio.post(
        '$_backendBaseUrl/v1/recommendations/similar',
        data: {
          'likedSongs': likedSongsData,
          'dislikedSongIds': dislikedSongIds,
          'likedSongIds': likedSongIds,
          'sessionId': sessionId,
        },
      );

      if (startResponse.statusCode != 200) {
        throw Exception(
          'Failed to start processing: ${startResponse.statusCode}',
        );
      }

      debugPrint('[rec-system] ✓ Processing started, polling for status...');

      // Step 2: Poll for status every 5 seconds
      while (true) {
        await Future.delayed(const Duration(seconds: 5));

        try {
          final statusResponse = await _dio.get(
            '$_backendBaseUrl/v1/recommendations/status/$sessionId',
          );

          if (statusResponse.statusCode == 200 && statusResponse.data != null) {
            final data = statusResponse.data as Map<String, dynamic>;
            final status = data['status'] as String;
            final progress = data['progress'] as Map<String, dynamic>?;

            // Update progress
            if (progress != null) {
              _progressController.add(
                RecommendationProgress.fromJson(progress),
              );
              debugPrint(
                '[rec-system] 📊 Progress: ${progress['percentage']}% - ${progress['message']}',
              );
            }

            // Check if complete
            if (status == 'complete') {
              final recommendations =
                  data['recommendations'] as List<dynamic>? ?? [];
              debugPrint(
                '[rec-system] ✅ Processing complete! Got ${recommendations.length} recommendations',
              );

              // Map backend response to our format
              return recommendations.map((track) {
                final t = track as Map<String, dynamic>;
                return {
                  'id': t['id'] ?? '',
                  'title': t['title'] ?? 'Unknown',
                  'artists': t['artists'] ?? 'Unknown Artist',
                  'score': (t['score'] as num?)?.toDouble() ?? 1.0,
                };
              }).toList();
            } else if (status == 'error') {
              final error = data['error'] as String? ?? 'Unknown error';
              throw Exception('Backend processing error: $error');
            }
          }
        } catch (e) {
          if (e is DioException && e.response?.statusCode == 404) {
            debugPrint('[rec-system] ⚠️  Session not found, may have expired');
            throw Exception('Session not found or expired');
          }
          // For other errors, continue polling
          debugPrint('[rec-system] ⚠️  Polling error: $e');
        }
      }
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          debugPrint(
            '[rec-system] ⚠️  Backend recommendation endpoint not found',
          );
        } else if (e.response?.statusCode == 400) {
          debugPrint('[rec-system] ⚠️  Invalid request to backend');
        } else {
          debugPrint(
            '[rec-system] ❌ Backend API error: ${e.response?.statusCode} - ${e.message}',
          );
        }
      } else {
        debugPrint('[rec-system] ❌ Backend API error: $e');
      }
      return [];
    }
  }
}
