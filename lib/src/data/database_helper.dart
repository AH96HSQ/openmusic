import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/album_art_helper.dart';
import '../services/sync_service.dart';

/// Key for storing local sync timestamp in SharedPreferences
const String _localSyncTimestampKey = 'local_sync_timestamp';

/// Update the local sync timestamp to indicate data has changed
/// and trigger a sync to push changes to the server
Future<void> _markLocalDataChanged() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _localSyncTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    // Trigger sync to push changes to server
    // Using unawaited to not block the calling code
    unawaited(SyncService.instance.syncData());
  } catch (e) {
    debugPrint('DatabaseHelper: Failed to update local sync timestamp: $e');
  }
}

/// Initialize the database factory for the current platform
void initDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux) {
    // Use FFI for Windows/Linux desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // On Android/iOS/macOS, the default sqflite factory is used
}

/// Database helper for OpenMusic - songs schema only (single unified id)
class DatabaseHelper {
  static const _databaseName = 'openmusic.db';
  static const _databaseVersion = 10;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    try {
      await db.rawQuery('PRAGMA journal_mode=WAL;');
      await db.rawQuery('PRAGMA synchronous=NORMAL;');
    } catch (_) {}
    return db;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migration from version 1 -> 2: change flag columns from INTEGER to TEXT
    // storing 'true'/'false'. We'll create a new table, copy rows with
    // conversion, drop the old table and rename the new one.
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE songs_new (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          album TEXT,
          artists TEXT,
          duration_ms INTEGER,
          source TEXT,
          ext TEXT,
          artwork_images TEXT,
          artwork_largest TEXT,
          file_exists TEXT DEFAULT 'false',
          file_id TEXT,
          spotify_uri TEXT,
          spotify_url TEXT,
          liked_status TEXT DEFAULT 'false',
          on_device_status TEXT DEFAULT 'false',
          on_device_filename TEXT DEFAULT '',
          album_art_on_device_status TEXT DEFAULT 'false',
          album_art_on_device_filename TEXT DEFAULT '',
          created_at INTEGER DEFAULT (strftime('%s','now')),
          updated_at INTEGER DEFAULT (strftime('%s','now'))
        );
      ''');

      await db.execute('''
        INSERT INTO songs_new (
          id, title, album, artists, duration_ms, source, ext,
          artwork_images, artwork_largest, file_exists, file_id,
          spotify_uri, spotify_url, liked_status, on_device_status,
          on_device_filename, album_art_on_device_status,
          album_art_on_device_filename, created_at, updated_at
        )
        SELECT
          id, title, album, artists, duration_ms, source, ext,
          artwork_images, artwork_largest,
          CASE WHEN file_exists IN (1, '1', 'true') THEN 'true' ELSE 'false' END,
          COALESCE(file_id, ''),
          COALESCE(spotify_uri, ''),
          COALESCE(spotify_url, ''),
          CASE WHEN liked_status IN (1, '1', 'true') THEN 'true' ELSE 'false' END,
          CASE WHEN on_device_status IN (1, '1', 'true') THEN 'true' ELSE 'false' END,
          COALESCE(on_device_filename, ''),
          CASE WHEN album_art_on_device_status IN (1, '1', 'true') THEN 'true' ELSE 'false' END,
          COALESCE(album_art_on_device_filename, ''),
          COALESCE(created_at, strftime('%s','now')),
          COALESCE(updated_at, strftime('%s','now'))
        FROM songs;
      ''');

      await db.execute('DROP TABLE songs;');
      await db.execute('ALTER TABLE songs_new RENAME TO songs;');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_songs_liked_status ON songs (liked_status)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_songs_on_device_status ON songs (on_device_status)',
      );
    }

    // Migration from version 2 -> 3: Add playlist tables
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE playlists (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at INTEGER DEFAULT (strftime('%s','now')),
          updated_at INTEGER DEFAULT (strftime('%s','now'))
        )
      ''');

      await db.execute('''
        CREATE TABLE playlist_songs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          playlist_id TEXT NOT NULL,
          song_id TEXT NOT NULL,
          position INTEGER NOT NULL,
          added_at INTEGER DEFAULT (strftime('%s','now')),
          FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
          FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE,
          UNIQUE (playlist_id, song_id)
        )
      ''');

      await db.execute(
        'CREATE INDEX idx_playlist_songs_playlist_id ON playlist_songs (playlist_id)',
      );
      await db.execute(
        'CREATE INDEX idx_playlist_songs_position ON playlist_songs (playlist_id, position)',
      );
    }

    // Migration from version 3 -> 4: Add is_device_file field
    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE songs ADD COLUMN is_device_file TEXT DEFAULT 'false'
      ''');

      // Update existing device files to mark them as device files
      // This assumes that songs with 'device_' prefix in their ID are device files
      await db.execute('''
        UPDATE songs SET is_device_file = 'true' WHERE id LIKE 'device_%'
      ''');
    }

    // Migration from version 4 -> 5: Add play_count field
    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE songs ADD COLUMN play_count INTEGER DEFAULT 0
      ''');

      // Create index for play_count to optimize most played queries
      await db.execute(
        'CREATE INDEX idx_songs_play_count ON songs (play_count DESC)',
      );
    }

    // Migration from version 5 -> 6: Add play_time field (in seconds)
    if (oldVersion < 6) {
      await db.execute('''
        ALTER TABLE songs ADD COLUMN play_time INTEGER DEFAULT 0
      ''');

      // Create index for play_time to optimize most played queries
      await db.execute(
        'CREATE INDEX idx_songs_play_time ON songs (play_time DESC)',
      );
    }

    // Migration from version 6 -> 7: Add recent_sources table
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE recent_sources (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_type INTEGER NOT NULL,
          source_id TEXT NOT NULL,
          source_name TEXT NOT NULL,
          artwork_url TEXT,
          played_at INTEGER DEFAULT (strftime('%s','now')),
          UNIQUE (source_type, source_id)
        )
      ''');

      await db.execute(
        'CREATE INDEX idx_recent_sources_played_at ON recent_sources (played_at DESC)',
      );
    }

    // Migration from version 7 -> 8: Replace recent_sources with recent_songs
    if (oldVersion < 8) {
      // Drop the old recent_sources table
      await db.execute('DROP TABLE IF EXISTS recent_sources');

      // Create new recent_songs table with simpler schema
      await db.execute('''
        CREATE TABLE recent_songs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          song_id TEXT NOT NULL UNIQUE,
          played_at INTEGER DEFAULT (strftime('%s','now'))
        )
      ''');

      await db.execute(
        'CREATE INDEX idx_recent_songs_played_at ON recent_songs (played_at DESC)',
      );
    }

    // Migration from version 8 -> 9: Add disliked_status column
    if (oldVersion < 9) {
      // Check if column already exists
      final columns = await db.rawQuery('PRAGMA table_info(songs)');
      final hasDisliked = columns.any(
        (col) => col['name'] == 'disliked_status',
      );

      if (!hasDisliked) {
        await db.execute('''
          ALTER TABLE songs ADD COLUMN disliked_status INTEGER DEFAULT 0
        ''');

        await db.execute(
          'CREATE INDEX idx_songs_disliked_status ON songs (disliked_status)',
        );
      }
    }

    // Migration from version 9 -> 10: Ensure disliked_status exists
    if (oldVersion < 10) {
      final columns = await db.rawQuery('PRAGMA table_info(songs)');
      final hasDisliked = columns.any(
        (col) => col['name'] == 'disliked_status',
      );

      if (!hasDisliked) {
        await db.execute('''
          ALTER TABLE songs ADD COLUMN disliked_status INTEGER DEFAULT 0
        ''');

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_songs_disliked_status ON songs (disliked_status)',
        );
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE songs (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        album TEXT,
        artists TEXT,
        duration_ms INTEGER,
        source TEXT,
        ext TEXT, -- json blob for provider-specific fields (spotify ext etc.)
        artwork_images TEXT, -- json array of artwork images
        artwork_largest TEXT,
        file_exists INTEGER DEFAULT 0,
        file_id TEXT,
        spotify_uri TEXT,
        spotify_url TEXT,
        liked_status INTEGER DEFAULT 0,
        disliked_status INTEGER DEFAULT 0,
        on_device_status INTEGER DEFAULT 0,
        on_device_filename TEXT DEFAULT '',
        album_art_on_device_status INTEGER DEFAULT 0,
        album_art_on_device_filename TEXT DEFAULT '',
        is_device_file TEXT DEFAULT 'false',
        play_count INTEGER DEFAULT 0,
        play_time INTEGER DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s','now')),
        updated_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_songs_liked_status ON songs (liked_status)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_disliked_status ON songs (disliked_status)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_on_device_status ON songs (on_device_status)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_play_count ON songs (play_count DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_play_time ON songs (play_time DESC)',
    );

    // Playlists table
    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s','now')),
        updated_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    // Playlist songs junction table (maintains order)
    await db.execute('''
      CREATE TABLE playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        added_at INTEGER DEFAULT (strftime('%s','now')),
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE,
        UNIQUE (playlist_id, song_id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_playlist_songs_playlist_id ON playlist_songs (playlist_id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlist_songs_position ON playlist_songs (playlist_id, position)',
    );

    // Recent songs table - tracks individual songs that were recently played
    await db.execute('''
      CREATE TABLE recent_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id TEXT NOT NULL UNIQUE,
        played_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_recent_songs_played_at ON recent_songs (played_at DESC)',
    );
  }

  Future<int> insertSong(Map<String, dynamic> song) async {
    // Defensive insert: sanitize incoming map to the known columns so that
    // unexpected keys from provider payloads don't cause SQLite errors.
    debugPrint(
      'DatabaseHelper.insertSong: ${song['title'] ?? song['name'] ?? '<no-title>'}',
    );
    final db = await database;

    // Ensure id exists
    final id =
        (song['id'] ?? song['_id'] ?? song['songId'] ?? song['trackId'])
            ?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // Normalize title
    final title = (song['title'] ?? song['name'] ?? song['trackName'] ?? '')
        ?.toString();

    // Normalize artists: if array, join; if map/object, try to extract name
    String? artists;
    try {
      final a = song['artists'];
      if (a is String) {
        artists = a;
      } else if (a is List) {
        artists = a.map((e) => e.toString()).join(', ');
      } else if (a is Map && a['name'] != null) {
        artists = a['name'].toString();
      }
    } catch (_) {
      // ignore
    }

    // artwork_images may be provided in a few shapes. Support:
    // - song['artwork_images'] as List or JSON string
    // - song['artwork'] as Map with an 'images' list
    String? artworkImages;
    String? artworkLargest;
    try {
      final imgsField = song['artwork_images'];
      if (imgsField is String) {
        artworkImages = imgsField;
      } else if (imgsField is List || imgsField is Map) {
        artworkImages = jsonEncode(imgsField);
      } else {
        // Fallback: check nested artwork.images
        final art = song['artwork'];
        if (art is Map) {
          final images = art['images'] as List<dynamic>?;
          if (images != null && images.isNotEmpty) {
            artworkImages = jsonEncode(images);
            // pick largest
            String? best;
            int bestW = 0;
            for (final im in images) {
              try {
                final w = (im['width'] as int?) ?? (im['w'] as int?) ?? 0;
                final url =
                    (im['url'] as String?) ?? (im['u'] as String?) ?? '';
                if (url.isNotEmpty && w > bestW) {
                  bestW = w;
                  best = url;
                }
              } catch (_) {}
            }
            artworkLargest = best;
          }
        }
      }
    } catch (_) {
      // ignore
    }

    // Prefer backend's durationMs (camelCase) if present.
    final durationVal =
        song['durationMs'] ?? song['duration_ms'] ?? song['duration'];

    // file information (nested object from backend)
    bool fileExistsFlag = false;
    String? fileIdVal;
    try {
      final f = song['file'];
      if (f is Map) {
        fileExistsFlag = (f['exists'] == true) || (f['exists'] == 1);
        fileIdVal = (f['id'] ?? f['fileId'] ?? f['filename'])?.toString();
      } else {
        fileExistsFlag =
            (song['file_exists'] == true) || (song['file_exists'] == 1);
        fileIdVal = song['file_id']?.toString();
      }
    } catch (_) {
      // ignore
    }

    // Spotify fields from ext.spotify
    String? spotifyUriVal;
    String? spotifyUrlVal;
    try {
      final sp = song['ext']?['spotify'];
      if (sp is Map) {
        spotifyUriVal = sp['uri']?.toString() ?? sp['uri']?.toString();
        spotifyUrlVal = sp['url']?.toString();
      }
    } catch (_) {}

    final row = <String, dynamic>{
      'id': id,
      'title': title,
      'album':
          song['album']?.toString() ?? song['collectionName']?.toString() ?? '',
      'artists':
          artists ??
          song['artist']?.toString() ??
          song['artistName']?.toString() ??
          '',
      'duration_ms': durationVal,
      'source': song['source']?.toString() ?? '',
      'ext': song['ext'] != null ? jsonEncode(song['ext']) : null,
      'artwork_images': artworkImages,
      'artwork_largest':
          artworkLargest ??
          song['artwork_largest']?.toString() ??
          song['artworkUrl']?.toString() ??
          '',
      // store flags as 'true'/'false' strings in the DB for consistency
      'file_exists': fileExistsFlag ? 'true' : 'false',
      'file_id': fileIdVal ?? '',
      'spotify_uri':
          spotifyUriVal ??
          song['spotify_uri']?.toString() ??
          song['spotifyUri']?.toString() ??
          '',
      'spotify_url':
          spotifyUrlVal ??
          song['spotify_url']?.toString() ??
          song['spotifyUrl']?.toString() ??
          '',
      'liked_status':
          (song['liked_status'] == 1 || song['liked_status'] == true)
          ? 'true'
          : 'false',
      'on_device_status':
          (song['on_device_status'] == 1 || song['on_device_status'] == true)
          ? 'true'
          : 'false',
      'on_device_filename': song['on_device_filename']?.toString() ?? '',
      'album_art_on_device_status':
          (song['album_art_on_device_status'] == 1 ||
              song['album_art_on_device_status'] == true)
          ? 'true'
          : 'false',
      'album_art_on_device_filename':
          song['album_art_on_device_filename']?.toString() ?? '',
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      // is_device_file: normalize from incoming data, or infer from source/id
      'is_device_file':
          ((song['is_device_file'] == 1 ||
              song['is_device_file'] == true ||
              song['is_device_file'] == 'true')
          ? 'true'
          : (song['source']?.toString() == 'device' ||
                id.toString().startsWith('device_'))
          ? 'true'
          : 'false'),
    };

    try {
      // Check if the song already exists and has download info to preserve
      final existing = await db.query(
        'songs',
        columns: [
          'on_device_status',
          'on_device_filename',
          'album_art_on_device_status',
          'album_art_on_device_filename',
        ],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      // If song exists and has download info, preserve it
      if (existing.isNotEmpty) {
        final existingRow = existing.first;
        final existingOnDeviceStatus =
            existingRow['on_device_status'] as String?;
        final existingOnDeviceFilename =
            existingRow['on_device_filename'] as String?;
        final existingArtOnDeviceStatus =
            existingRow['album_art_on_device_status'] as String?;
        final existingArtOnDeviceFilename =
            existingRow['album_art_on_device_filename'] as String?;

        // Preserve on_device fields if they were set and new data doesn't have them
        if (existingOnDeviceStatus == 'true' &&
            row['on_device_status'] != 'true') {
          row['on_device_status'] = existingOnDeviceStatus;
          row['on_device_filename'] = existingOnDeviceFilename ?? '';
          debugPrint(
            'DatabaseHelper.insertSong: Preserving existing on_device_status=true for $id',
          );
        }
        if (existingArtOnDeviceStatus == 'true' &&
            row['album_art_on_device_status'] != 'true') {
          row['album_art_on_device_status'] = existingArtOnDeviceStatus;
          row['album_art_on_device_filename'] =
              existingArtOnDeviceFilename ?? '';
          debugPrint(
            'DatabaseHelper.insertSong: Preserving existing album_art_on_device_status=true for $id',
          );
        }
      }

      final result = await db.insert(
        'songs',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Mark local data as changed for sync
      await _markLocalDataChanged();

      // Trigger background artwork download if song has artwork URL
      if (result > 0 && (artworkLargest != null || artworkImages != null)) {
        debugPrint(
          'DatabaseHelper: Triggering artwork download for $id - artworkLargest: $artworkLargest, artworkImages: ${artworkImages != null ? 'has_images' : 'null'}',
        );
        AlbumArtHelper.instance.downloadArtworkForSong(id).catchError((error) {
          debugPrint(
            'DatabaseHelper: Background artwork download failed for $id: $error',
          );
          return null;
        });
      } else {
        debugPrint(
          'DatabaseHelper: NOT triggering artwork download for $id - result: $result, artworkLargest: $artworkLargest, artworkImages: ${artworkImages != null ? 'has_images' : 'null'}',
        );
      }

      return result;
    } catch (e, st) {
      debugPrint('DatabaseHelper.insertSong failed: $e');
      debugPrint('Song payload: ${jsonEncode(song)}');
      debugPrint('Stack: $st');
      return 0;
    }
  }

  Future<Map<String, dynamic>?> getSong(String id) async {
    final db = await database;
    final rows = await db.query(
      'songs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllSongs() async {
    final db = await database;
    return await db.query('songs', orderBy: 'created_at DESC');
  }

  /// Get only liked songs with play time > 0 (for recommendations)
  Future<List<Map<String, dynamic>>> getLikedSongsWithPlayTime() async {
    final db = await database;
    return await db.query(
      'songs',
      where: '(liked_status = ? OR liked_status = ?) AND play_time > ?',
      whereArgs: ['true', '1', 0],
      orderBy: 'play_time DESC',
    );
  }

  Future<int> updateSong(String id, Map<String, dynamic> song) async {
    final db = await database;
    // Coerce known flag fields to stored string form ('true'/'false') and
    // ensure file_id is string to avoid sqlite type errors when callers pass
    // booleans or ints.
    try {
      final coerced = Map<String, dynamic>.from(song);
      void setBoolField(String key) {
        if (coerced.containsKey(key)) {
          final v = coerced[key];
          if (v == true || v == 1 || v == '1' || v == 'true') {
            coerced[key] = 'true';
          } else if (v == false || v == 0 || v == '0' || v == 'false') {
            coerced[key] = 'false';
          } else if (v is String) {
            // keep as-is if it's already a string
          } else {
            coerced[key] = v != null ? v.toString() : 'false';
          }
        }
      }

      setBoolField('file_exists');
      setBoolField('liked_status');
      setBoolField('on_device_status');
      setBoolField('album_art_on_device_status');
      setBoolField('is_device_file');

      if (coerced.containsKey('file_id')) {
        final v = coerced['file_id'];
        coerced['file_id'] = v == null ? '' : v.toString();
      }

      coerced['updated_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final rows = await db.update(
        'songs',
        coerced,
        where: 'id = ?',
        whereArgs: [id],
      );

      // If update affected no rows (row missing), insert a new minimal row to
      // ensure the update is not lost. Insert uses ConflictAlgorithm.replace so
      // this is safe if a concurrent insert happens.
      if (rows == 0) {
        final toInsert = Map<String, dynamic>.from(coerced);
        toInsert['id'] = id;
        try {
          await db.insert(
            'songs',
            toInsert,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _markLocalDataChanged();
          return 1;
        } catch (e) {
          // If insert fails, return 0 to indicate no rows changed
          return 0;
        }
      }

      await _markLocalDataChanged();
      return rows;
    } catch (e) {
      // Fallback: try direct update to avoid losing the update entirely.
      song['updated_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rows = await db.update(
        'songs',
        song,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows == 0) {
        song['id'] = id;
        try {
          await db.insert(
            'songs',
            song,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _markLocalDataChanged();
          return 1;
        } catch (_) {
          return 0;
        }
      }
      await _markLocalDataChanged();
      return rows;
    }
  }

  Future<int> deleteSong(String id) async {
    final db = await database;
    final result = await db.delete('songs', where: 'id = ?', whereArgs: [id]);
    if (result > 0) {
      await _markLocalDataChanged();
    }
    return result;
  }

  // ---- Playlist methods ----

  /// Create a new playlist
  Future<void> createPlaylist(String id, String name) async {
    final db = await database;
    await db.insert('playlists', {
      'id': id,
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    await _markLocalDataChanged();
  }

  /// Get all playlists
  Future<List<Map<String, dynamic>>> getAllPlaylists() async {
    final db = await database;
    return await db.query('playlists', orderBy: 'created_at DESC');
  }

  /// Get a specific playlist
  Future<Map<String, dynamic>?> getPlaylist(String id) async {
    final db = await database;
    final rows = await db.query(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Update playlist name
  Future<void> updatePlaylist(String id, String name) async {
    final db = await database;
    await db.update(
      'playlists',
      {
        'name': name,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _markLocalDataChanged();
  }

  /// Delete a playlist and all its songs
  Future<void> deletePlaylist(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete all songs from the playlist first
      await txn.delete(
        'playlist_songs',
        where: 'playlist_id = ?',
        whereArgs: [id],
      );
      // Then delete the playlist itself
      await txn.delete('playlists', where: 'id = ?', whereArgs: [id]);
    });
    await _markLocalDataChanged();
  }

  /// Add a song to a playlist
  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final db = await database;

    await db.transaction((txn) async {
      // Check if song is already in the playlist
      final existing = await txn.query(
        'playlist_songs',
        where: 'playlist_id = ? AND song_id = ?',
        whereArgs: [playlistId, songId],
      );

      if (existing.isEmpty) {
        // Get the current max position
        final maxPositionResult = await txn.rawQuery(
          'SELECT COALESCE(MAX(position), -1) as max_pos FROM playlist_songs WHERE playlist_id = ?',
          [playlistId],
        );
        final maxPosition = maxPositionResult.first['max_pos'] as int;

        // Add song at the end
        await txn.insert('playlist_songs', {
          'playlist_id': playlistId,
          'song_id': songId,
          'position': maxPosition + 1,
          'added_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });

        // Update playlist's updated_at timestamp
        await txn.update(
          'playlists',
          {'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
          where: 'id = ?',
          whereArgs: [playlistId],
        );
      }
    });
    await _markLocalDataChanged();
  }

  /// Remove a song from a playlist
  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final db = await database;

    await db.transaction((txn) async {
      // Get the position of the song to be removed
      final songResult = await txn.query(
        'playlist_songs',
        columns: ['position'],
        where: 'playlist_id = ? AND song_id = ?',
        whereArgs: [playlistId, songId],
      );

      if (songResult.isNotEmpty) {
        final removedPosition = songResult.first['position'] as int;

        // Remove the song
        await txn.delete(
          'playlist_songs',
          where: 'playlist_id = ? AND song_id = ?',
          whereArgs: [playlistId, songId],
        );

        // Update positions of songs that came after the removed song
        await txn.rawUpdate(
          'UPDATE playlist_songs SET position = position - 1 WHERE playlist_id = ? AND position > ?',
          [playlistId, removedPosition],
        );

        // Update playlist's updated_at timestamp
        await txn.update(
          'playlists',
          {'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
          where: 'id = ?',
          whereArgs: [playlistId],
        );
      }
    });
    await _markLocalDataChanged();
  }

  /// Get all songs in a playlist (in order)
  Future<List<String>> getPlaylistSongs(String playlistId) async {
    final db = await database;
    final result = await db.query(
      'playlist_songs',
      columns: ['song_id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return result.map((row) => row['song_id'] as String).toList();
  }

  /// Get playlist song count
  Future<int> getPlaylistSongCount(String playlistId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM playlist_songs WHERE playlist_id = ?',
      [playlistId],
    );
    return result.first['count'] as int;
  }

  /// Reorder songs in a playlist
  Future<void> reorderPlaylistSongs(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      // Get all songs in order
      final songsQuery = await txn.query(
        'playlist_songs',
        columns: ['song_id'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );

      // Create a mutable list from the query results
      final songs = List<Map<String, Object?>>.from(songsQuery);

      debugPrint(
        'DatabaseHelper: Reorder playlist $playlistId - oldIndex: $oldIndex, newIndex: $newIndex, total songs: ${songs.length}',
      );

      if (oldIndex >= 0 &&
          oldIndex < songs.length &&
          newIndex >= 0 &&
          newIndex < songs.length) {
        // Remove the song from its old position
        final songId = songs.removeAt(oldIndex)['song_id'] as String;
        // Insert it at the new position
        songs.insert(newIndex, {'song_id': songId});

        debugPrint(
          'DatabaseHelper: Moving song $songId from $oldIndex to $newIndex',
        );

        // Update all positions
        for (int i = 0; i < songs.length; i++) {
          final updateCount = await txn.update(
            'playlist_songs',
            {'position': i},
            where: 'playlist_id = ? AND song_id = ?',
            whereArgs: [playlistId, songs[i]['song_id']],
          );
          debugPrint(
            'DatabaseHelper: Updated position $i for song ${songs[i]['song_id']} (rows affected: $updateCount)',
          );
        }

        // Update playlist's updated_at timestamp
        await txn.update(
          'playlists',
          {'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
          where: 'id = ?',
          whereArgs: [playlistId],
        );

        debugPrint('DatabaseHelper: Reorder completed successfully');
      } else {
        debugPrint(
          'DatabaseHelper: Invalid indices - oldIndex: $oldIndex, newIndex: $newIndex, length: ${songs.length}',
        );
      }
    });
  }

  /// Get the last added song ID for a playlist (for thumbnail)
  Future<String?> getPlaylistThumbnailSongId(String playlistId) async {
    final db = await database;
    final result = await db.query(
      'playlist_songs',
      columns: ['song_id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first['song_id'] as String : null;
  }

  /// Get top played song IDs from a user playlist (for collage thumbnail)
  /// Returns up to 4 song IDs ordered by play_time DESC
  Future<List<String>> getPlaylistTopPlayedSongIds(
    String playlistId, {
    int limit = 4,
  }) async {
    final db = await database;
    try {
      final result = await db.rawQuery(
        '''
        SELECT ps.song_id, s.play_time
        FROM playlist_songs ps
        INNER JOIN songs s ON ps.song_id = s.id
        WHERE ps.playlist_id = ?
        ORDER BY s.play_time DESC, ps.added_at DESC
        LIMIT ?
      ''',
        [playlistId, limit],
      );

      final songIds = result.map((r) => r['song_id'] as String).toList();
      debugPrint(
        'DatabaseHelper: Retrieved ${songIds.length} top played songs for playlist $playlistId',
      );
      return songIds;
    } catch (e) {
      debugPrint('DatabaseHelper: Error getting playlist top played songs: $e');
      return [];
    }
  }

  /// Get most played songs by play time (limit to specified count)
  Future<List<Map<String, dynamic>>> getMostPlayedSongs({
    int limit = 10,
  }) async {
    final db = await database;
    try {
      final result = await db.query(
        'songs',
        where: 'play_time > 0',
        orderBy: 'play_time DESC, updated_at DESC',
        limit: limit,
      );
      debugPrint(
        'DatabaseHelper: Retrieved ${result.length} most played songs by play time',
      );
      return result;
    } catch (e) {
      debugPrint('DatabaseHelper: Error getting most played songs: $e');
      return [];
    }
  }

  /// Add play time to a song (in seconds)
  Future<void> addPlayTime(String songId, int seconds) async {
    final db = await database;
    try {
      await db.rawUpdate(
        '''
        UPDATE songs 
        SET play_time = play_time + ?, 
            updated_at = strftime('%s','now')
        WHERE id = ?
      ''',
        [seconds, songId],
      );
      debugPrint(
        'DatabaseHelper: Added $seconds seconds of play time to song $songId',
      );
    } catch (e) {
      debugPrint('DatabaseHelper: Error adding play time for $songId: $e');
    }
  }

  /// Get play time for a specific song (in seconds)
  Future<int> getPlayTime(String songId) async {
    final db = await database;
    try {
      final result = await db.query(
        'songs',
        columns: ['play_time'],
        where: 'id = ?',
        whereArgs: [songId],
        limit: 1,
      );
      if (result.isNotEmpty) {
        return result.first['play_time'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('DatabaseHelper: Error getting play time for $songId: $e');
      return 0;
    }
  }

  /// Record a recently played song
  /// Uses REPLACE to update the played_at timestamp if the song already exists
  /// This moves the song to the top of the recent list
  Future<void> recordRecentSong(String songId) async {
    final db = await database;
    try {
      await db.insert('recent_songs', {
        'song_id': songId,
        'played_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      debugPrint('DatabaseHelper: Recorded recent song: $songId');
    } catch (e) {
      debugPrint('DatabaseHelper: Error recording recent song: $e');
    }
  }

  /// Get recently played songs, ordered by most recent first
  /// Returns full song details by joining with the songs table
  Future<List<Map<String, dynamic>>> getRecentSongs({int limit = 20}) async {
    final db = await database;
    try {
      final result = await db.rawQuery(
        '''
        SELECT s.*, rs.played_at
        FROM recent_songs rs
        INNER JOIN songs s ON rs.song_id = s.id
        ORDER BY rs.played_at DESC
        LIMIT ?
      ''',
        [limit],
      );
      debugPrint('DatabaseHelper: Retrieved ${result.length} recent songs');
      return result;
    } catch (e) {
      debugPrint('DatabaseHelper: Error getting recent songs: $e');
      return [];
    }
  }

  /// Remove a specific song from recent songs
  Future<void> removeRecentSong(String songId) async {
    final db = await database;
    try {
      await db.delete(
        'recent_songs',
        where: 'song_id = ?',
        whereArgs: [songId],
      );
      debugPrint('DatabaseHelper: Removed recent song: $songId');
    } catch (e) {
      debugPrint('DatabaseHelper: Error removing recent song: $e');
    }
  }

  /// Clear all recent songs
  Future<void> clearRecentSongs() async {
    final db = await database;
    try {
      await db.delete('recent_songs');
      debugPrint('DatabaseHelper: Cleared all recent songs');
    } catch (e) {
      debugPrint('DatabaseHelper: Error clearing recent songs: $e');
    }
  }

  /// Search library songs (songs in playlists, offline songs, and device files)
  /// Supports filtering by artist, album, or track
  Future<List<Map<String, dynamic>>> searchLibrarySongs({
    required String query,
    String? filterType, // 'artist', 'album', or 'track'
  }) async {
    if (query.trim().isEmpty) return [];

    final db = await database;
    try {
      // Build search query based on filter type
      final searchTerm = '%${query.trim().toLowerCase()}%';
      String whereClause;
      List<dynamic> whereArgs;

      // Base condition: song must be in a playlist OR be liked OR be offline OR be a device file
      String libraryCondition = '''
        (id IN (SELECT DISTINCT song_id FROM playlist_songs) 
         OR liked_status = 'true'
         OR on_device_status = 'true' 
         OR source = 'device')
      ''';

      if (filterType == 'artist') {
        whereClause = '$libraryCondition AND LOWER(artists) LIKE ?';
        whereArgs = [searchTerm];
      } else if (filterType == 'album') {
        whereClause = '$libraryCondition AND LOWER(album) LIKE ?';
        whereArgs = [searchTerm];
      } else if (filterType == 'track') {
        whereClause = '$libraryCondition AND LOWER(title) LIKE ?';
        whereArgs = [searchTerm];
      } else {
        // Search all fields
        whereClause =
            '''
          $libraryCondition AND 
          (LOWER(title) LIKE ? OR LOWER(artists) LIKE ? OR LOWER(album) LIKE ?)
        ''';
        whereArgs = [searchTerm, searchTerm, searchTerm];
      }

      final results = await db.query(
        'songs',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'title ASC',
        limit: 50, // Limit library results
      );

      debugPrint(
        'DatabaseHelper: Found ${results.length} library songs for query "$query"',
      );
      return results;
    } catch (e) {
      debugPrint('DatabaseHelper: Error searching library songs: $e');
      return [];
    }
  }

  /// Get total listening duration for liked songs in seconds
  Future<int> getTotalListeningDuration() async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT SUM(play_time) as total_duration
        FROM songs
        WHERE liked_status IN (1, '1', 'true')
      ''');

      if (result.isNotEmpty && result.first['total_duration'] != null) {
        return (result.first['total_duration'] as num).toInt();
      }
      return 0;
    } catch (e) {
      debugPrint('DatabaseHelper: Error getting total listening duration: $e');
      return 0;
    }
  }

  /// Reset play history for a specific song (set play_time and play_count to 0)
  Future<void> resetPlayHistory(String songId) async {
    try {
      final db = await database;
      await db.update(
        'songs',
        {'play_time': 0, 'play_count': 0},
        where: 'id = ?',
        whereArgs: [songId],
      );
      debugPrint('DatabaseHelper: Reset play history for song $songId');
    } catch (e) {
      debugPrint('DatabaseHelper: Error resetting play history: $e');
      rethrow;
    }
  }

  /// Toggle song disliked status
  Future<bool> toggleDislikedStatus(String songId) async {
    try {
      final db = await database;
      final song = await getSong(songId);

      if (song == null) {
        debugPrint('DatabaseHelper: Song $songId not found');
        return false;
      }

      final currentStatus = song['disliked_status'];
      final newStatus =
          (currentStatus == 1 ||
              currentStatus == '1' ||
              currentStatus == 'true' ||
              currentStatus == true)
          ? 0
          : 1;

      // When disliking (newStatus = 1), also clear liked status
      final updateData = <String, dynamic>{'disliked_status': newStatus};
      if (newStatus == 1) {
        updateData['liked_status'] =
            'false'; // Clear liked status when disliking
      }

      await db.update(
        'songs',
        updateData,
        where: 'id = ?',
        whereArgs: [songId],
      );

      debugPrint(
        'DatabaseHelper: Toggled disliked status for $songId to $newStatus${newStatus == 1 ? " (also cleared liked status)" : ""}',
      );

      return newStatus ==
          1; // Return true if now disliked, false if un-disliked
    } catch (e) {
      debugPrint('DatabaseHelper: Error toggling disliked status: $e');
      return false;
    }
  }

  /// Get all disliked song IDs
  Future<List<String>> getDislikedSongIds() async {
    try {
      final db = await database;
      final results = await db.query(
        'songs',
        columns: ['id'],
        where: 'disliked_status IN (1, \'1\', \'true\')',
      );

      return results.map((row) => row['id'] as String).toList();
    } catch (e) {
      debugPrint('DatabaseHelper: Error getting disliked song IDs: $e');
      return [];
    }
  }

  /// Set song disliked status (for recommendations)
  Future<void> setDislikedStatus(String songId, bool disliked) async {
    try {
      final db = await database;
      await db.update(
        'songs',
        {'disliked_status': disliked ? 1 : 0},
        where: 'id = ?',
        whereArgs: [songId],
      );
      debugPrint(
        'DatabaseHelper: Set disliked status for $songId to $disliked',
      );
    } catch (e) {
      debugPrint('DatabaseHelper: Error setting disliked status: $e');
      rethrow;
    }
  }
}
