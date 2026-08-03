import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';

class PlaylistsService {
  // Default playlist IDs
  static const String likedSongsId = 'liked_songs';
  static const String offlineSongsId = 'offline_songs';
  static const String deviceFilesId = 'device_files';

  /// Get all playlists (default + user created)
  static Future<List<Map<String, dynamic>>> getAllPlaylists() async {
    try {
      final db = DatabaseHelper.instance;

      // Get user-created playlists from database and filter out default IDs
      final userPlaylists = (await db.getAllPlaylists())
          .where((p) => !_isDefaultPlaylist(p['id'] as String))
          .toList();

      // Get counts for default playlists
      final likedCount = await _getLikedSongsCount();
      final offlineCount = await _getOfflineSongsCount();
      final deviceCount = await _getDeviceFilesCount();

      // Default playlists
      final defaultPlaylists = [
        {
          'id': likedSongsId,
          'name': 'Liked Songs',
          'isDefault': true,
          'songCount': likedCount,
          'topSongIds': await _getPlaylistTopSongIds(likedSongsId),
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        },
        {
          'id': offlineSongsId,
          'name': 'Offline Songs',
          'isDefault': true,
          'songCount': offlineCount,
          'topSongIds': await _getPlaylistTopSongIds(offlineSongsId),
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        },
        {
          'id': deviceFilesId,
          'name': 'Device Files',
          'isDefault': true,
          'songCount': deviceCount,
          'topSongIds': await _getPlaylistTopSongIds(deviceFilesId),
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        },
      ];

      // Convert user playlists to the expected format
      final formattedUserPlaylists = <Map<String, dynamic>>[];
      for (final playlist in userPlaylists) {
        final playlistId = playlist['id'] as String;
        final songCount = await db.getPlaylistSongCount(playlistId);
        final topSongIds = await db.getPlaylistTopPlayedSongIds(playlistId);

        formattedUserPlaylists.add({
          'id': playlistId,
          'name': playlist['name'],
          'isDefault': false,
          'songCount': songCount,
          'topSongIds': topSongIds,
          'lastUpdated':
              playlist['updated_at'] * 1000, // Convert to milliseconds
        });
      }

      // Combine default and user playlists
      final allPlaylists = <Map<String, dynamic>>[];
      allPlaylists.addAll(defaultPlaylists);
      allPlaylists.addAll(formattedUserPlaylists);

      return allPlaylists;
    } catch (e) {
      debugPrint('PlaylistsService: Error getting playlists: $e');
      return [];
    }
  }

  /// Ensure default playlists exist in database (call on app startup)
  static Future<void> ensureDefaultPlaylistsExist() async {
    try {
      final db = DatabaseHelper.instance;

      // Check if default playlists exist, create if they don't
      final defaultPlaylists = [
        {'id': likedSongsId, 'name': 'Liked Songs'},
        {'id': offlineSongsId, 'name': 'Offline Songs'},
        {'id': deviceFilesId, 'name': 'Device Files'},
      ];

      for (final playlist in defaultPlaylists) {
        final existing = await db.getPlaylist(playlist['id']!);
        if (existing == null) {
          await db.createPlaylist(playlist['id']!, playlist['name']!);
          debugPrint(
            'PlaylistsService: Created default playlist "${playlist['name']}"',
          );
        }
      }
    } catch (e) {
      debugPrint('PlaylistsService: Error ensuring default playlists: $e');
    }
  }

  /// Create a new user playlist
  static Future<String> createPlaylist(String name) async {
    try {
      final playlistId = 'playlist_${DateTime.now().millisecondsSinceEpoch}';
      final db = DatabaseHelper.instance;

      await db.createPlaylist(playlistId, name);

      debugPrint(
        'PlaylistsService: Created playlist "$name" with ID: $playlistId',
      );
      return playlistId;
    } catch (e) {
      debugPrint('PlaylistsService: Error creating playlist: $e');
      throw Exception('Failed to create playlist');
    }
  }

  /// Add song to playlist
  static Future<void> addSongToPlaylist(
    String playlistId,
    String songId,
  ) async {
    try {
      final db = DatabaseHelper.instance;

      if (_isDefaultPlaylist(playlistId)) {
        await _addToDefaultPlaylist(playlistId, songId);
      } else {
        await db.addSongToPlaylist(playlistId, songId);
      }
      debugPrint(
        'PlaylistsService: Added song $songId to playlist $playlistId',
      );
    } catch (e) {
      debugPrint('PlaylistsService: Error adding song to playlist: $e');
      throw Exception('Failed to add song to playlist');
    }
  }

  /// Remove song from playlist
  static Future<void> removeSongFromPlaylist(
    String playlistId,
    String songId,
  ) async {
    try {
      final db = DatabaseHelper.instance;

      if (_isDefaultPlaylist(playlistId)) {
        await _removeFromDefaultPlaylist(playlistId, songId);
      } else {
        await db.removeSongFromPlaylist(playlistId, songId);
      }
      debugPrint(
        'PlaylistsService: Removed song $songId from playlist $playlistId',
      );
    } catch (e) {
      debugPrint('PlaylistsService: Error removing song from playlist: $e');
      throw Exception('Failed to remove song from playlist');
    }
  }

  /// Get songs in a playlist
  static Future<List<String>> getPlaylistSongs(String playlistId) async {
    try {
      final db = DatabaseHelper.instance;

      if (_isDefaultPlaylist(playlistId)) {
        return await _getDefaultPlaylistSongs(playlistId);
      } else {
        return await db.getPlaylistSongs(playlistId);
      }
    } catch (e) {
      debugPrint('PlaylistsService: Error getting playlist songs: $e');
      return [];
    }
  }

  /// Delete a user playlist
  static Future<void> deletePlaylist(String playlistId) async {
    try {
      if (_isDefaultPlaylist(playlistId)) {
        throw Exception('Cannot delete default playlist');
      }

      final db = DatabaseHelper.instance;
      await db.deletePlaylist(playlistId);
      debugPrint('PlaylistsService: Deleted playlist $playlistId');
    } catch (e) {
      debugPrint('PlaylistsService: Error deleting playlist: $e');
      throw Exception('Failed to delete playlist');
    }
  }

  /// Rename a user playlist
  static Future<void> renamePlaylist(String playlistId, String newName) async {
    try {
      if (_isDefaultPlaylist(playlistId)) {
        throw Exception('Cannot rename default playlist');
      }

      final db = DatabaseHelper.instance;
      await db.updatePlaylist(playlistId, newName);
      debugPrint(
        'PlaylistsService: Renamed playlist $playlistId to "$newName"',
      );
    } catch (e) {
      debugPrint('PlaylistsService: Error renaming playlist: $e');
      throw Exception('Failed to rename playlist');
    }
  }

  /// Reorder songs in a playlist
  static Future<void> reorderPlaylistSongs(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    try {
      // Block reordering for all default playlists (they are auto-generated)
      // liked_songs: Generated from liked_status field in songs table
      // offline_songs: Generated from on_device_status field
      // device_files: Generated from source='device' field
      if (_isDefaultPlaylist(playlistId)) {
        throw Exception('Cannot reorder auto-generated playlist songs');
      }

      final db = DatabaseHelper.instance;
      await db.reorderPlaylistSongs(playlistId, oldIndex, newIndex);
      debugPrint('PlaylistsService: Reordered songs in playlist $playlistId');
    } catch (e) {
      debugPrint('PlaylistsService: Error reordering playlist songs: $e');
      throw Exception('Failed to reorder playlist songs');
    }
  }

  // Private helper methods

  static bool _isDefaultPlaylist(String playlistId) {
    return [likedSongsId, offlineSongsId, deviceFilesId].contains(playlistId);
  }

  static Future<int> _getLikedSongsCount() async {
    try {
      final db = DatabaseHelper.instance;
      final songs = await db.getAllSongs();
      return songs.where((song) => song['liked_status'] == 'true').length;
    } catch (e) {
      debugPrint('PlaylistsService: Error getting liked songs count: $e');
      return 0;
    }
  }

  static Future<int> _getOfflineSongsCount() async {
    try {
      final db = DatabaseHelper.instance;
      final songs = await db.getAllSongs();
      return songs.where((song) => song['on_device_status'] == 'true').length;
    } catch (e) {
      debugPrint('PlaylistsService: Error getting offline songs count: $e');
      return 0;
    }
  }

  static Future<int> _getDeviceFilesCount() async {
    try {
      final db = DatabaseHelper.instance;
      final songs = await db.getAllSongs();
      return songs.where((song) => song['source'] == 'device').length;
    } catch (e) {
      debugPrint('PlaylistsService: Error getting device files count: $e');
      return 0;
    }
  }

  /// Get top played song IDs for a playlist (up to 4 for collage thumbnail)
  static Future<List<String>> _getPlaylistTopSongIds(String playlistId) async {
    try {
      final db = DatabaseHelper.instance;
      final songs = await db.getAllSongs();
      List<Map<String, dynamic>> playlistSongs;

      switch (playlistId) {
        case likedSongsId:
          playlistSongs = songs
              .where((song) => song['liked_status'] == 'true')
              .toList();
          break;
        case offlineSongsId:
          playlistSongs = songs
              .where((song) => song['on_device_status'] == 'true')
              .toList();
          break;
        case deviceFilesId:
          playlistSongs = songs
              .where((song) => song['source'] == 'device')
              .toList();
          break;
        default:
          return [];
      }

      if (playlistSongs.isEmpty) {
        return [];
      }

      // Sort by play_time descending, then by updated_at descending
      playlistSongs.sort((a, b) {
        final playTimeA = a['play_time'] as int? ?? 0;
        final playTimeB = b['play_time'] as int? ?? 0;
        if (playTimeA != playTimeB) {
          return playTimeB.compareTo(playTimeA);
        }
        final updatedA = a['updated_at'] as int? ?? 0;
        final updatedB = b['updated_at'] as int? ?? 0;
        return updatedB.compareTo(updatedA);
      });

      // Return up to 4 song IDs
      return playlistSongs.take(4).map((song) => song['id'] as String).toList();
    } catch (e) {
      debugPrint('PlaylistsService: Error getting playlist top song IDs: $e');
      return [];
    }
  }

  static Future<void> _addToDefaultPlaylist(
    String playlistId,
    String songId,
  ) async {
    final db = DatabaseHelper.instance;

    switch (playlistId) {
      case likedSongsId:
        // Update the song's liked status in the database
        await db.updateSong(songId, {'liked_status': 'true'});
        break;
      case offlineSongsId:
        // Update the song's offline status in the database
        await db.updateSong(songId, {'on_device_status': 'true'});
        break;
      case deviceFilesId:
        // Device files don't need explicit addition - they're detected by scan
        break;
    }
  }

  static Future<void> _removeFromDefaultPlaylist(
    String playlistId,
    String songId,
  ) async {
    final db = DatabaseHelper.instance;

    switch (playlistId) {
      case likedSongsId:
        // Update the song's liked status in the database
        await db.updateSong(songId, {'liked_status': 'false'});
        break;
      case offlineSongsId:
        // Update the song's offline status in the database
        await db.updateSong(songId, {'on_device_status': 'false'});
        break;
      case deviceFilesId:
        // Remove device file from database
        await db.deleteSong(songId);
        break;
    }
  }

  static Future<List<String>> _getDefaultPlaylistSongs(
    String playlistId,
  ) async {
    final db = DatabaseHelper.instance;
    final songs = await db.getAllSongs();

    switch (playlistId) {
      case likedSongsId:
        return songs
            .where((song) => song['liked_status'] == 'true')
            .map((song) => song['id'] as String)
            .toList();
      case offlineSongsId:
        return songs
            .where((song) => song['on_device_status'] == 'true')
            .map((song) => song['id'] as String)
            .toList();
      case deviceFilesId:
        return songs
            .where((song) => song['source'] == 'device')
            .map((song) => song['id'] as String)
            .toList();
      default:
        return [];
    }
  }
}
