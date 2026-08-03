import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import '../services/playlists_service.dart';

/// Helper service for managing liked songs and the liked songs playlist
class LikedSongsHelper {
  /// Toggle the liked status of a song and update the liked songs playlist
  static Future<bool> toggleLikedStatus(String songId) async {
    try {
      debugPrint('LikedSongsHelper.toggleLikedStatus: songId = $songId');
      final db = DatabaseHelper.instance;
      var song = await db.getSong(songId);
      debugPrint(
        'LikedSongsHelper.toggleLikedStatus: song found = ${song != null}',
      );
      if (song != null) {
        debugPrint(
          'LikedSongsHelper.toggleLikedStatus: current liked_status = ${song['liked_status']}',
        );
      }

      // If song doesn't exist (e.g. liking directly from search), insert a
      // minimal row. Database schema requires 'title' NOT NULL, so use
      // songId as a placeholder title.
      if (song == null) {
        await db.insertSong({
          'id': songId,
          'title': songId,
          'artists': '',
          'album': '',
          'artwork_largest': '',
          'liked_status': 'false',
        });
        song = await db.getSong(songId);
      }

      final currentLikedStatus = (song!['liked_status'] == 'true');
      final newLikedStatus = !currentLikedStatus;
      debugPrint(
        'LikedSongsHelper.toggleLikedStatus: toggling from $currentLikedStatus to $newLikedStatus',
      );

      // Update the song's liked status in database
      // Also clear disliked status when liking a song
      await db.updateSong(songId, {
        'liked_status': newLikedStatus ? 'true' : 'false',
        'disliked_status': 0, // Clear disliked status when liking
      });
      debugPrint(
        'LikedSongsHelper.toggleLikedStatus: database update completed (also cleared disliked status)',
      );

      if (newLikedStatus) {
        // Add to liked songs playlist (at the top)
        await PlaylistsService.addSongToPlaylist(
          PlaylistsService.likedSongsId,
          songId,
        );
        debugPrint('LikedSongsHelper: Added $songId to liked songs');
      } else {
        // Remove from liked songs playlist
        await PlaylistsService.removeSongFromPlaylist(
          PlaylistsService.likedSongsId,
          songId,
        );
        debugPrint('LikedSongsHelper: Removed $songId from liked songs');
      }

      // Re-read the song to confirm the persisted liked status and return
      final updated = await db.getSong(songId);
      final persistedLiked =
          updated != null && updated['liked_status'] == 'true';
      return persistedLiked;
    } catch (e) {
      debugPrint('LikedSongsHelper: Error toggling liked status: $e');
      return false;
    }
  }

  /// Set the liked status of a song (without toggling)
  static Future<void> setLikedStatus(String songId, bool liked) async {
    try {
      final db = DatabaseHelper.instance;

      // Ensure song exists in DB first
      var song = await db.getSong(songId);
      if (song == null) {
        await db.insertSong({
          'id': songId,
          'title': songId,
          'artists': '',
          'album': '',
          'artwork_largest': '',
          'liked_status': liked ? 'true' : 'false',
        });
      } else {
        // Update the song's liked status in database
        await db.updateSong(songId, {'liked_status': liked ? 'true' : 'false'});
      }

      if (liked) {
        // Add to liked songs playlist (at the top)
        await PlaylistsService.addSongToPlaylist(
          PlaylistsService.likedSongsId,
          songId,
        );
        debugPrint('LikedSongsHelper: Set $songId as liked');
      } else {
        // Remove from liked songs playlist
        await PlaylistsService.removeSongFromPlaylist(
          PlaylistsService.likedSongsId,
          songId,
        );
        debugPrint('LikedSongsHelper: Set $songId as not liked');
      }
    } catch (e) {
      debugPrint('LikedSongsHelper: Error setting liked status: $e');
    }
  }

  /// Get the liked status of a song
  static Future<bool> isLiked(String songId) async {
    try {
      final db = DatabaseHelper.instance;
      final song = await db.getSong(songId);
      return song != null && song['liked_status'] == 'true';
    } catch (e) {
      debugPrint('LikedSongsHelper: Error checking liked status: $e');
      return false;
    }
  }

  /// Get all liked songs (in order)
  static Future<List<String>> getLikedSongs() async {
    try {
      return await PlaylistsService.getPlaylistSongs(
        PlaylistsService.likedSongsId,
      );
    } catch (e) {
      debugPrint('LikedSongsHelper: Error getting liked songs: $e');
      return [];
    }
  }
}
