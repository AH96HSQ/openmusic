import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';

class MostPlayedService {
  /// Get most played songs from database
  static Future<List<Map<String, dynamic>>> getMostPlayedSongs({
    int limit = 10,
  }) async {
    try {
      final songs = await DatabaseHelper.instance.getMostPlayedSongs(
        limit: limit,
      );
      debugPrint(
        'MostPlayedService: Retrieved ${songs.length} most played songs',
      );
      return songs;
    } catch (e) {
      debugPrint('MostPlayedService: Error getting most played songs: $e');
      return [];
    }
  }

  /// Add play time for a song (in seconds)
  static Future<void> addPlayTime(String songId, int seconds) async {
    try {
      await DatabaseHelper.instance.addPlayTime(songId, seconds);
      debugPrint(
        'MostPlayedService: Added $seconds seconds of play time for $songId',
      );
    } catch (e) {
      debugPrint('MostPlayedService: Error adding play time for $songId: $e');
    }
  }

  /// Get play time for a specific song (in seconds)
  static Future<int> getPlayTime(String songId) async {
    try {
      final time = await DatabaseHelper.instance.getPlayTime(songId);
      return time;
    } catch (e) {
      debugPrint('MostPlayedService: Error getting play time for $songId: $e');
      return 0;
    }
  }
}
