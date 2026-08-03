import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database_helper.dart';
import 'album_art_helper.dart';
import 'auth_service.dart';

/// Key for storing local sync timestamp in SharedPreferences
const String _localSyncTimestampKey = 'local_sync_timestamp';

/// Service for syncing user data with backend
/// Uses smart bidirectional sync based on timestamps
class SyncService {
  static final SyncService _instance = SyncService._internal();
  static SyncService get instance => _instance;
  SyncService._internal();

  late final String _baseUrl;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  /// Stream controller for sync status changes
  final _syncStatusController = StreamController<bool>.broadcast();
  Stream<bool> get syncStatusStream => _syncStatusController.stream;

  /// Get current sync status
  bool get isSyncing => _isSyncing;

  /// Get last sync time
  DateTime? get lastSyncTime => _lastSyncTime;

  Future<void> init() async {
    final envBase = dotenv.env['BACKEND_BASE_URL']?.trim();
    _baseUrl = envBase?.isNotEmpty == true
        ? envBase!.replaceAll(RegExp(r'/+$'), '')
        : 'http://localhost:5002';
  }

  /// Get the local sync timestamp (last time local data was modified)
  Future<int> getLocalTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_localSyncTimestampKey) ?? 0;
  }

  /// Update the local sync timestamp
  Future<void> updateLocalTimestamp([int? timestamp]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _localSyncTimestampKey,
      timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Smart sync - compares timestamps and syncs in the right direction
  /// Returns: 'uploaded', 'downloaded', 'none', or throws on error
  Future<String> smartSync() async {
    if (!AuthService.instance.isLoggedIn) {
      debugPrint('SyncService: Cannot sync - user not logged in');
      return 'none';
    }

    if (_isSyncing) {
      debugPrint('SyncService: Sync already in progress');
      return 'none';
    }

    _isSyncing = true;
    _syncStatusController.add(true);

    try {
      debugPrint('SyncService: Starting smart sync...');

      final userId = AuthService.instance.currentUser!['id'];
      final localTimestamp = await getLocalTimestamp();

      debugPrint('SyncService: Local timestamp: $localTimestamp');

      // First, check server status to determine sync direction
      final statusResponse = await http
          .get(
            Uri.parse('$_baseUrl/v1/sync/status/$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (statusResponse.statusCode != 200) {
        throw Exception('Failed to get sync status');
      }

      final status = jsonDecode(statusResponse.body);
      final serverTimestamp = status['serverTimestamp'] as int? ?? 0;
      final hasSyncData = status['hasSyncData'] as bool? ?? false;

      debugPrint(
        'SyncService: Server timestamp: $serverTimestamp, has data: $hasSyncData',
      );

      // Determine sync direction
      if (!hasSyncData || localTimestamp > serverTimestamp) {
        // Local is newer or no server data - upload
        debugPrint('SyncService: Local is newer - uploading...');
        await _uploadData(userId, localTimestamp);
        return 'uploaded';
      } else if (serverTimestamp > localTimestamp) {
        // Server is newer - download
        debugPrint('SyncService: Server is newer - downloading...');
        await _downloadData(userId, serverTimestamp);
        return 'downloaded';
      } else {
        // Timestamps are equal - no sync needed
        debugPrint('SyncService: Data is in sync');
        return 'none';
      }
    } catch (e) {
      debugPrint('SyncService: ❌ Smart sync failed: $e');
      return 'none';
    } finally {
      _isSyncing = false;
      _syncStatusController.add(false);
    }
  }

  /// Upload local data to server
  Future<void> _uploadData(String userId, int localTimestamp) async {
    final songs = await _getSongsForSync();
    final playlists = await _getPlaylistsForSync();
    final recommendations = await _getRecommendationsForSync();

    final syncData = {
      'userId': userId,
      'songs': songs,
      'playlists': playlists,
      'recommendations': recommendations['data'],
      'recommendationsTimestamp': recommendations['timestamp'],
      'syncedAt': DateTime.now().toIso8601String(),
      'clientTimestamp': localTimestamp,
    };

    debugPrint(
      'SyncService: Uploading ${songs.length} songs, ${playlists.length} playlists',
    );

    final response = await http
        .post(
          Uri.parse('$_baseUrl/v1/sync/upload'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(syncData),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      final serverTimestamp = result['serverTimestamp'] as int?;
      if (serverTimestamp != null) {
        await updateLocalTimestamp(serverTimestamp);
      }
      _lastSyncTime = DateTime.now();
      debugPrint('SyncService: ✓ Upload completed successfully');
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Upload failed');
    }
  }

  /// Download data from server
  Future<void> _downloadData(String userId, int serverTimestamp) async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl/v1/sync/restore/$userId'),
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['songs'] == null || data['playlists'] == null) {
        throw Exception('No backup data found');
      }

      await _restoreToDatabase(data);
      await _restoreRecommendations(data);

      // Update local timestamp to match server
      await updateLocalTimestamp(serverTimestamp);

      _lastSyncTime = DateTime.now();
      debugPrint('SyncService: ✓ Download completed successfully');

      // Download missing artwork in background
      Future.delayed(Duration.zero, () {
        AlbumArtHelper.instance.downloadAllMissingArtwork();
      });
    } else if (response.statusCode == 404) {
      throw Exception('No backup found for this account');
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Download failed');
    }
  }

  /// Legacy sync method - always uploads (for backward compatibility)
  /// Called when app goes to background or on significant events
  Future<void> syncData() async {
    // Use smart sync instead of always uploading
    await smartSync();
  }

  /// Restore data from backend (user-initiated)
  Future<void> restoreData() async {
    if (!AuthService.instance.isLoggedIn) {
      throw Exception('User not logged in');
    }

    try {
      debugPrint('SyncService: Starting manual restore...');

      final userId = AuthService.instance.currentUser!['id'];
      await _downloadData(userId, DateTime.now().millisecondsSinceEpoch);

      debugPrint('SyncService: ✓ Manual restore completed successfully');
    } catch (e) {
      debugPrint('SyncService: ❌ Restore failed: $e');
      rethrow;
    }
  }

  /// Force upload local data (user-initiated)
  Future<void> forceUpload() async {
    if (!AuthService.instance.isLoggedIn) {
      throw Exception('User not logged in');
    }

    if (_isSyncing) {
      throw Exception('Sync already in progress');
    }

    _isSyncing = true;
    _syncStatusController.add(true);

    try {
      debugPrint('SyncService: Starting force upload...');

      final userId = AuthService.instance.currentUser!['id'];
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await updateLocalTimestamp(timestamp);
      await _uploadData(userId, timestamp);

      debugPrint('SyncService: ✓ Force upload completed successfully');
    } catch (e) {
      debugPrint('SyncService: ❌ Force upload failed: $e');
      rethrow;
    } finally {
      _isSyncing = false;
      _syncStatusController.add(false);
    }
  }

  /// Get recommendations for sync from SharedPreferences
  Future<Map<String, dynamic>> _getRecommendationsForSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('latest_recommendations');
      final timestamp = prefs.getString('latest_recommendations_timestamp');

      if (cachedJson != null) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        final recommendations = decoded
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        return {'data': recommendations, 'timestamp': timestamp};
      }

      return {'data': null, 'timestamp': null};
    } catch (e) {
      debugPrint('SyncService: Error getting recommendations for sync: $e');
      return {'data': null, 'timestamp': null};
    }
  }

  /// Get songs for sync (excluding device-specific fields and device files)
  Future<List<Map<String, dynamic>>> _getSongsForSync() async {
    final db = await DatabaseHelper.instance.database;
    final allSongs = await db.query('songs');

    // Filter out device files and exclude device-specific fields
    final syncableSongs = allSongs
        .where((song) {
          // Exclude songs that are device files (from local storage)
          final isDeviceFile =
              song['is_device_file'] == 'true' ||
              song['is_device_file'] == true ||
              song['is_device_file'] == 1;

          if (isDeviceFile) {
            debugPrint(
              'SyncService: Skipping device file: ${song['title'] ?? song['id']}',
            );
            return false;
          }

          return true;
        })
        .map((song) {
          final syncSong = Map<String, dynamic>.from(song);
          // Remove the 4 device-specific fields
          syncSong.remove('on_device_status');
          syncSong.remove('on_device_filename');
          syncSong.remove('album_art_on_device_status');
          syncSong.remove('album_art_on_device_filename');
          return syncSong;
        })
        .toList();

    debugPrint(
      'SyncService: Total songs: ${allSongs.length}, Syncable songs: ${syncableSongs.length}',
    );

    return syncableSongs;
  }

  /// Get playlists for sync (with song IDs only)
  /// Excludes default playlists: offline_songs, device_files
  /// Only syncs liked_songs and custom playlists that have songs
  Future<List<Map<String, dynamic>>> _getPlaylistsForSync() async {
    final db = await DatabaseHelper.instance.database;

    // Get all playlists
    final playlists = await db.query('playlists');

    final playlistsWithSongs = <Map<String, dynamic>>[];

    for (final playlist in playlists) {
      final playlistId = playlist['id'] as String;

      // Skip offline_songs and device_files playlists (use correct IDs)
      if (playlistId == 'offline_songs' || playlistId == 'device_files') {
        debugPrint('SyncService: Skipping playlist: $playlistId');
        continue;
      }

      // Get song IDs in order
      final songs = await db.query(
        'playlist_songs',
        columns: ['song_id', 'position'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );

      // Skip playlists with no songs (including liked_songs which is virtual)
      if (songs.isEmpty) {
        debugPrint('SyncService: Skipping empty playlist: $playlistId');
        continue;
      }

      debugPrint(
        'SyncService: Syncing playlist $playlistId with ${songs.length} songs',
      );

      playlistsWithSongs.add({
        'id': playlist['id'],
        'name': playlist['name'],
        'created_at': playlist['created_at'],
        'updated_at': playlist['updated_at'],
        'songs': songs.map((s) => s['song_id']).toList(),
      });
    }

    return playlistsWithSongs;
  }

  /// Restore data to database
  /// Preserves device-specific fields for songs that already exist locally
  Future<void> _restoreToDatabase(Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      // 1. Get existing songs with their device-specific fields before clearing
      final existingSongs = await txn.query(
        'songs',
        columns: [
          'id',
          'on_device_status',
          'on_device_filename',
          'album_art_on_device_status',
          'album_art_on_device_filename',
        ],
      );

      // Create a map of song_id -> device fields
      final deviceFieldsMap = <String, Map<String, dynamic>>{};
      for (final song in existingSongs) {
        deviceFieldsMap[song['id'] as String] = {
          'on_device_status': song['on_device_status'],
          'on_device_filename': song['on_device_filename'],
          'album_art_on_device_status': song['album_art_on_device_status'],
          'album_art_on_device_filename': song['album_art_on_device_filename'],
        };
      }

      debugPrint(
        'SyncService: Preserved device fields for ${deviceFieldsMap.length} existing songs',
      );

      // 2. Clear existing data
      await txn.delete('playlist_songs');
      await txn.delete('playlists');
      await txn.delete('songs');

      debugPrint('SyncService: Cleared existing database');

      // 3. Restore songs (preserving device-specific fields if song existed)
      final songs = data['songs'] as List<dynamic>;
      for (final song in songs) {
        final songMap = Map<String, dynamic>.from(song);
        final songId = songMap['id'] as String;

        // Check if this song existed locally
        if (deviceFieldsMap.containsKey(songId)) {
          // Preserve existing device-specific fields
          final deviceFields = deviceFieldsMap[songId]!;
          songMap['on_device_status'] = deviceFields['on_device_status'];
          songMap['on_device_filename'] = deviceFields['on_device_filename'];
          songMap['album_art_on_device_status'] =
              deviceFields['album_art_on_device_status'];
          songMap['album_art_on_device_filename'] =
              deviceFields['album_art_on_device_filename'];
        } else {
          // New song - set empty device-specific fields
          songMap['on_device_status'] = 'false';
          songMap['on_device_filename'] = '';
          songMap['album_art_on_device_status'] = 'false';
          songMap['album_art_on_device_filename'] = '';
        }

        await txn.insert('songs', songMap);
      }

      debugPrint('SyncService: Restored ${songs.length} songs');

      // 4. Restore playlists
      final playlists = data['playlists'] as List<dynamic>;
      for (final playlist in playlists) {
        // Insert playlist
        await txn.insert('playlists', {
          'id': playlist['id'],
          'name': playlist['name'],
          'created_at': playlist['created_at'],
          'updated_at': playlist['updated_at'],
        });

        // Insert playlist songs
        final songIds = playlist['songs'] as List<dynamic>;
        for (int i = 0; i < songIds.length; i++) {
          await txn.insert('playlist_songs', {
            'playlist_id': playlist['id'],
            'song_id': songIds[i],
            'position': i,
            'added_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          });
        }
      }

      debugPrint('SyncService: Restored ${playlists.length} playlists');
    });
  }

  /// Restore recommendations to SharedPreferences
  Future<void> _restoreRecommendations(Map<String, dynamic> data) async {
    try {
      final recommendations = data['recommendations'];
      final timestamp = data['recommendationsTimestamp'];

      if (recommendations != null) {
        final prefs = await SharedPreferences.getInstance();

        // Save recommendations as JSON string
        final json = jsonEncode(recommendations);
        await prefs.setString('latest_recommendations', json);

        // Save timestamp if available
        if (timestamp != null) {
          await prefs.setString('latest_recommendations_timestamp', timestamp);
        }

        debugPrint(
          'SyncService: Restored ${(recommendations as List).length} recommendations',
        );
      } else {
        debugPrint('SyncService: No recommendations found in backup');
      }
    } catch (e) {
      debugPrint('SyncService: Error restoring recommendations: $e');
      // Don't throw - recommendations restore failure shouldn't block the whole restore
    }
  }

  void dispose() {
    _syncStatusController.close();
  }
}
