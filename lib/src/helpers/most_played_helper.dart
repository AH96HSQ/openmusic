import '../services/most_played_service.dart';
import 'package:flutter/foundation.dart';

class MostPlayedHelper {
  /// Add play time for a song (in seconds)
  static Future<void> addPlayTime(String songId, int seconds) async {
    try {
      // Only track for actual song IDs, not temporary ones
      if (songId.startsWith('temp_') || songId.isEmpty) {
        debugPrint('MostPlayedHelper: Skipping temp/empty song ID: $songId');
        return;
      }

      await MostPlayedService.addPlayTime(songId, seconds);
      debugPrint('MostPlayedHelper: Added $seconds seconds to song $songId');
    } catch (e) {
      debugPrint('MostPlayedHelper: Error adding play time for $songId: $e');
    }
  }

  /// Get most played songs for display in wheel
  static Future<List<Map<String, dynamic>>> getMostPlayedSongs({
    int limit = 10,
  }) async {
    try {
      return await MostPlayedService.getMostPlayedSongs(limit: limit);
    } catch (e) {
      debugPrint('MostPlayedHelper: Error getting most played songs: $e');
      return [];
    }
  }
}
