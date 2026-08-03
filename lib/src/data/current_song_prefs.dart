import 'package:shared_preferences/shared_preferences.dart';

/// Helper to persist the current playing song id across app restarts.
class CurrentSongPrefs {
  static const _key = 'current_song_id';

  /// Save the currently playing song id.
  static Future<void> setCurrentSongId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }

  /// Return persisted song id or null if none.
  static Future<String?> getCurrentSongId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Clear the persisted id.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
