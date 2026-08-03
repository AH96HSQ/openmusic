import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/database_helper.dart';
import 'playlists_service.dart';

/// Service for scanning local device storage for music files
class DeviceFilesScanner {
  static final DeviceFilesScanner instance = DeviceFilesScanner._internal();
  DeviceFilesScanner._internal();

  bool _isScanning = false;
  int _totalFiles = 0;
  int _scannedFiles = 0;
  String _currentPath = '';
  String? _offlineMusicDirPath; // Exclusion: app's own offline downloads

  bool get isScanning => _isScanning;
  int get totalFiles => _totalFiles;
  int get scannedFiles => _scannedFiles;
  String get currentPath => _currentPath;
  double get progress => _totalFiles > 0 ? _scannedFiles / _totalFiles : 0.0;

  /// Supported audio file extensions
  static const List<String> _supportedExtensions = [
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.wma',
  ];

  /// Start scanning device for music files
  Future<int> startScan({
    required Function(int scanned, int total, String currentPath) onProgress,
    required Function(String songId) onSongFound,
  }) async {
    if (_isScanning) {
      debugPrint('DeviceFilesScanner: Scan already in progress');
      return 0;
    }

    // Check and request permissions first
    final hasPermission = await _checkAndRequestPermissions();
    if (!hasPermission) {
      debugPrint('DeviceFilesScanner: Storage permissions not granted');
      return 0;
    }

    _isScanning = true;
    _totalFiles = 0;
    _scannedFiles = 0;
    _currentPath = '';

    // Compute offline music directory path to exclude from scan
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _offlineMusicDirPath = _normalizePath('${appDocDir.path}/music');
      debugPrint(
        'DeviceFilesScanner: Excluding offline dir: $_offlineMusicDirPath',
      );
    } catch (_) {
      _offlineMusicDirPath = null;
    }

    debugPrint(
      'DeviceFilesScanner: Supported extensions: $_supportedExtensions',
    );

    try {
      debugPrint('DeviceFilesScanner: Starting device scan...');

      // Get directories to scan
      final directoriesToScan = await _getDirectoriesToScan();
      debugPrint(
        'DeviceFilesScanner: Found ${directoriesToScan.length} directories to scan',
      );

      // First pass: count total files
      for (final directory in directoriesToScan) {
        await _countFilesInDirectory(directory);
      }

      debugPrint(
        'DeviceFilesScanner: Found $_totalFiles audio files to process',
      );
      onProgress(_scannedFiles, _totalFiles, _currentPath);

      // Second pass: process files
      int songsAdded = 0;
      for (final directory in directoriesToScan) {
        songsAdded += await _scanDirectory(
          directory,
          onProgress: onProgress,
          onSongFound: onSongFound,
        );
      }

      // Third pass: clean up files that no longer exist
      final removedCount = await _cleanupMissingFiles();

      debugPrint(
        'DeviceFilesScanner: Scan completed. Added $songsAdded songs, removed $removedCount missing files',
      );
      return songsAdded;
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error during scan: $e');
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// Get directories that might contain music files
  Future<List<Directory>> _getDirectoriesToScan() async {
    final directories = <Directory>[];

    try {
      // First, try to get managed folders from user preferences
      final managedFolders = await _getManagedFolders();

      if (managedFolders.isNotEmpty) {
        // Use managed folders if available
        for (final folderPath in managedFolders) {
          final dir = Directory(folderPath);
          if (await dir.exists()) {
            try {
              // Test if we can list the directory
              final testList = await dir.list().take(5).toList();
              directories.add(dir);
              debugPrint(
                'DeviceFilesScanner: Added managed directory: $folderPath (${testList.length} items visible)',
              );
            } catch (e) {
              debugPrint(
                'DeviceFilesScanner: Cannot access managed directory: $folderPath - $e',
              );
            }
          } else {
            debugPrint(
              'DeviceFilesScanner: Managed directory not found: $folderPath',
            );
          }
        }
        // Filter out the app's offline music directory if it was added by user
        _filterExcludedDirectories(directories);
        debugPrint(
          'DeviceFilesScanner: Using ${directories.length} managed folders',
        );
      } else {
        // Fallback to default directories if no managed folders
        await _addDefaultDirectories(directories);
        // Filter out excluded directories (e.g., app offline dir)
        _filterExcludedDirectories(directories);
        debugPrint(
          'DeviceFilesScanner: Using ${directories.length} default folders',
        );
      }
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error getting scan directories: $e');
      // Fallback to default directories on error
      await _addDefaultDirectories(directories);
    }

    return directories;
  }

  void _filterExcludedDirectories(List<Directory> dirs) {
    final before = dirs.length;
    dirs.removeWhere((d) => _shouldExcludeDir(d.path));
    final after = dirs.length;
    if (after != before) {
      debugPrint(
        'DeviceFilesScanner: Excluded ${before - after} directories (offline downloads)',
      );
    }
  }

  /// Get managed folders from SharedPreferences
  Future<List<String>> _getManagedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foldersJson = prefs.getString('managed_folders') ?? '[]';
      final List<dynamic> foldersList = jsonDecode(foldersJson);
      return foldersList.map((folder) => folder.toString()).toList();
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error getting managed folders: $e');
      return [];
    }
  }

  /// Add default directories when no managed folders are available
  Future<void> _addDefaultDirectories(List<Directory> directories) async {
    try {
      if (Platform.isAndroid) {
        // Common Android music directories
        final androidDirs = [
          '/storage/emulated/0/Music',
          '/storage/emulated/0/Download',
          '/storage/emulated/0/DCIM',
          '/sdcard/Music',
          '/sdcard/Download',
        ];

        for (final path in androidDirs) {
          final dir = Directory(path);
          if (await dir.exists()) {
            directories.add(dir);
            debugPrint('DeviceFilesScanner: Added Android directory: $path');
          }
        }

        // Add external storage directory if available on Android
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            directories.add(externalDir);
            debugPrint(
              'DeviceFilesScanner: Added external storage: ${externalDir.path}',
            );
          }
        } catch (e) {
          debugPrint('DeviceFilesScanner: External storage not available: $e');
        }
      } else if (Platform.isWindows) {
        // Windows: Add common music directories
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          final windowsDirs = [
            '$userProfile\\Music',
            '$userProfile\\Downloads',
            '$userProfile\\Desktop',
          ];

          for (final path in windowsDirs) {
            final dir = Directory(path);
            if (await dir.exists()) {
              directories.add(dir);
              debugPrint('DeviceFilesScanner: Added Windows directory: $path');
            }
          }
        }
      } else if (Platform.isMacOS || Platform.isLinux) {
        // macOS/Linux: Add common music directories
        final home = Platform.environment['HOME'];
        if (home != null) {
          final unixDirs = ['$home/Music', '$home/Downloads', '$home/Desktop'];

          for (final path in unixDirs) {
            final dir = Directory(path);
            if (await dir.exists()) {
              directories.add(dir);
              debugPrint('DeviceFilesScanner: Added Unix directory: $path');
            }
          }
        }
      }

      // Intentionally DO NOT add the app's internal music directory to avoid
      // showing offline downloads in the device-scanned list.
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error adding default directories: $e');
    }
  }

  /// Count files in a directory (recursive)
  Future<void> _countFilesInDirectory(Directory directory) async {
    await _countFilesRecursive(directory);
  }

  /// Recursively count files in directory and subdirectories
  Future<void> _countFilesRecursive(Directory directory) async {
    try {
      if (_shouldExcludeDir(directory.path)) {
        debugPrint(
          'DeviceFilesScanner: Skipping excluded dir (count): ${directory.path}',
        );
        return;
      }
      debugPrint('DeviceFilesScanner: Counting files in ${directory.path}');
      int fileCount = 0;
      int audioFileCount = 0;
      int subdirCount = 0;

      // List directory contents (non-recursive first)
      final entities = await directory.list().toList();
      debugPrint(
        'DeviceFilesScanner: Found ${entities.length} entities in ${directory.path}',
      );

      for (final entity in entities) {
        if (entity is File) {
          fileCount++;
          final extension = _getFileExtension(entity.path).toLowerCase();
          debugPrint(
            'DeviceFilesScanner: Found file: ${entity.path} with extension: $extension',
          );

          if (_isSupportedAudioFile(entity.path)) {
            audioFileCount++;
            _totalFiles++;
            debugPrint(
              'DeviceFilesScanner: ✓ Audio file detected: ${entity.path}',
            );
          }
        } else if (entity is Directory) {
          if (_shouldExcludeDir(entity.path)) {
            debugPrint(
              'DeviceFilesScanner: Skipping excluded subdir (count): ${entity.path}',
            );
            continue;
          }
          subdirCount++;
          debugPrint('DeviceFilesScanner: Found subdirectory: ${entity.path}');
          // Recursively scan subdirectory
          await _countFilesRecursive(entity);
        }
      }

      debugPrint(
        'DeviceFilesScanner: Directory ${directory.path} - Files: $fileCount, Audio: $audioFileCount, Subdirs: $subdirCount',
      );
    } catch (e) {
      debugPrint(
        'DeviceFilesScanner: Error counting files in ${directory.path}: $e',
      );
    }
  }

  /// Scan a directory for music files
  Future<int> _scanDirectory(
    Directory directory, {
    required Function(int scanned, int total, String currentPath) onProgress,
    required Function(String songId) onSongFound,
  }) async {
    return await _scanDirectoryRecursive(
      directory,
      onProgress: onProgress,
      onSongFound: onSongFound,
    );
  }

  /// Recursively scan directory and subdirectories for music files
  Future<int> _scanDirectoryRecursive(
    Directory directory, {
    required Function(int scanned, int total, String currentPath) onProgress,
    required Function(String songId) onSongFound,
  }) async {
    int songsAdded = 0;

    try {
      if (_shouldExcludeDir(directory.path)) {
        debugPrint(
          'DeviceFilesScanner: Skipping excluded dir (scan): ${directory.path}',
        );
        return 0;
      }
      debugPrint('DeviceFilesScanner: Scanning directory ${directory.path}');

      // List directory contents (non-recursive first)
      final entities = await directory.list().toList();
      debugPrint(
        'DeviceFilesScanner: Found ${entities.length} entities in ${directory.path}',
      );

      for (final entity in entities) {
        if (entity is File) {
          final extension = _getFileExtension(entity.path).toLowerCase();
          debugPrint(
            'DeviceFilesScanner: Processing file: ${entity.path} (ext: $extension)',
          );

          if (_isSupportedAudioFile(entity.path)) {
            debugPrint(
              'DeviceFilesScanner: ✓ Processing audio file: ${entity.path}',
            );
            _currentPath = entity.path;
            _scannedFiles++;

            onProgress(_scannedFiles, _totalFiles, _currentPath);

            try {
              final songId = await _processAudioFile(entity);
              if (songId != null) {
                onSongFound(songId);
                songsAdded++;
                debugPrint(
                  'DeviceFilesScanner: ✓ Successfully added song: $songId',
                );
              } else {
                debugPrint(
                  'DeviceFilesScanner: ✗ Failed to add song from: ${entity.path}',
                );
              }
            } catch (e) {
              debugPrint(
                'DeviceFilesScanner: Error processing ${entity.path}: $e',
              );
            }
          }
        } else if (entity is Directory) {
          if (_shouldExcludeDir(entity.path)) {
            debugPrint(
              'DeviceFilesScanner: Skipping excluded subdir (scan): ${entity.path}',
            );
            continue;
          }
          debugPrint(
            'DeviceFilesScanner: Recursively scanning subdirectory: ${entity.path}',
          );
          // Recursively scan subdirectory
          final subSongsAdded = await _scanDirectoryRecursive(
            entity,
            onProgress: onProgress,
            onSongFound: onSongFound,
          );
          songsAdded += subSongsAdded;
        }
      }

      debugPrint(
        'DeviceFilesScanner: Completed scanning ${directory.path}, added $songsAdded songs',
      );
    } catch (e) {
      debugPrint(
        'DeviceFilesScanner: Error scanning directory ${directory.path}: $e',
      );
    }

    return songsAdded;
  }

  bool _shouldExcludeDir(String path) {
    if (_offlineMusicDirPath == null) return false;
    final n = _normalizePath(path);
    return n == _offlineMusicDirPath || n.startsWith('$_offlineMusicDirPath/');
  }

  String _normalizePath(String p) {
    // Normalize to forward slashes and lowercase (case-insensitive comparison)
    return p.replaceAll('\\', '/');
  }

  /// Check if file is a supported audio file
  bool _isSupportedAudioFile(String filePath) {
    final extension = _getFileExtension(filePath).toLowerCase();
    return _supportedExtensions.contains(extension);
  }

  /// Get file extension from path
  String _getFileExtension(String filePath) {
    final lastDot = filePath.lastIndexOf('.');
    return lastDot != -1 ? filePath.substring(lastDot) : '';
  }

  /// Process an audio file and add to database
  Future<String?> _processAudioFile(File file) async {
    try {
      final fileName = _getFileName(file.path);
      final stats = await file.stat();

      // Generate a unique ID based on file path and modification time
      final songId = _generateSongId(file.path, stats.modified);

      // Check if already exists in database
      final db = DatabaseHelper.instance;
      final existingSong = await db.getSong(songId);

      if (existingSong != null) {
        debugPrint('DeviceFilesScanner: Song $songId already exists, skipping');
        return songId;
      }

      // Extract basic metadata from filename
      final metadata = _extractMetadataFromFilename(fileName);

      // Ensure title is never empty - use filename as fallback
      final title = (metadata['title']?.trim().isNotEmpty == true)
          ? metadata['title']!
          : fileName;

      // Create song record
      await db.insertSong({
        'id': songId,
        'title': title,
        'artists': metadata['artist'] ?? 'Unknown Artist',
        'album': metadata['album'] ?? 'Unknown Album',
        'duration_ms': null, // Could be extracted with audio metadata package
        'source': 'device',
        'on_device_status': 'true',
        'on_device_filename': file.path,
        'file_exists': 'true',
        'is_device_file': 'true',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      // Add to device files playlist
      await PlaylistsService.addSongToPlaylist(
        PlaylistsService.deviceFilesId,
        songId,
      );

      debugPrint(
        'DeviceFilesScanner: Added device file: $fileName (ID: $songId)',
      );
      return songId;
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error processing file ${file.path}: $e');
      return null;
    }
  }

  /// Generate unique song ID from file path and modification time
  String _generateSongId(String filePath, DateTime modTime) {
    final input = '$filePath:${modTime.millisecondsSinceEpoch}';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return 'device_${digest.toString().substring(0, 16)}';
  }

  /// Get filename without path and extension
  String _getFileName(String filePath) {
    // Handle both Windows and Unix path separators
    final fileName = filePath.split(Platform.pathSeparator).last;
    final lastDot = fileName.lastIndexOf('.');
    return lastDot != -1 ? fileName.substring(0, lastDot) : fileName;
  }

  /// Extract basic metadata from filename
  Map<String, String?> _extractMetadataFromFilename(String fileName) {
    // Try common patterns like "Artist - Title" or "Artist - Album - Title"
    final patterns = [
      RegExp(r'^(.+?)\s*-\s*(.+?)\s*-\s*(.+)$'), // Artist - Album - Title
      RegExp(r'^(.+?)\s*-\s*(.+)$'), // Artist - Title
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(fileName);
      if (match != null) {
        if (match.groupCount == 3) {
          return {
            'artist': match.group(1)?.trim(),
            'album': match.group(2)?.trim(),
            'title': match.group(3)?.trim(),
          };
        } else if (match.groupCount == 2) {
          return {
            'artist': match.group(1)?.trim(),
            'title': match.group(2)?.trim(),
            'album': null,
          };
        }
      }
    }

    // If no pattern matches, use filename as title
    return {'title': fileName, 'artist': null, 'album': null};
  }

  /// Scan a specific directory selected by user
  Future<int> scanSpecificDirectory(
    String directoryPath, {
    required Function(int scanned, int total, String currentPath) onProgress,
    required Function(String songId) onSongFound,
  }) async {
    if (_isScanning) {
      debugPrint('DeviceFilesScanner: Scan already in progress');
      return 0;
    }

    _isScanning = true;
    _totalFiles = 0;
    _scannedFiles = 0;
    _currentPath = '';

    try {
      debugPrint(
        'DeviceFilesScanner: Starting scan of directory: $directoryPath',
      );

      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        throw Exception('Directory does not exist: $directoryPath');
      }

      // First pass: count total files
      await _countFilesInDirectory(directory);
      debugPrint(
        'DeviceFilesScanner: Found $_totalFiles audio files to process in $directoryPath',
      );
      onProgress(_scannedFiles, _totalFiles, _currentPath);

      // Second pass: process files
      final songsAdded = await _scanDirectory(
        directory,
        onProgress: onProgress,
        onSongFound: onSongFound,
      );

      debugPrint(
        'DeviceFilesScanner: Directory scan completed. Added $songsAdded songs from $directoryPath',
      );
      return songsAdded;
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error during directory scan: $e');
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// Check and request storage permissions
  Future<bool> _checkAndRequestPermissions() async {
    try {
      debugPrint('DeviceFilesScanner: Checking storage permissions...');

      // For Android 11+ (API 30+), we need MANAGE_EXTERNAL_STORAGE
      if (Platform.isAndroid) {
        // Check if we already have the permission
        var permission = Permission.manageExternalStorage;
        var status = await permission.status;

        debugPrint(
          'DeviceFilesScanner: MANAGE_EXTERNAL_STORAGE status: $status',
        );

        if (status.isGranted) {
          debugPrint(
            'DeviceFilesScanner: MANAGE_EXTERNAL_STORAGE already granted',
          );
          return true;
        }

        // Also check regular storage permission
        var storagePermission = Permission.storage;
        var storageStatus = await storagePermission.status;
        debugPrint(
          'DeviceFilesScanner: Storage permission status: $storageStatus',
        );

        // Request permissions
        if (!status.isGranted) {
          debugPrint(
            'DeviceFilesScanner: Requesting MANAGE_EXTERNAL_STORAGE permission...',
          );
          status = await permission.request();
          debugPrint(
            'DeviceFilesScanner: MANAGE_EXTERNAL_STORAGE request result: $status',
          );
        }

        if (!storageStatus.isGranted) {
          debugPrint('DeviceFilesScanner: Requesting storage permission...');
          storageStatus = await storagePermission.request();
          debugPrint(
            'DeviceFilesScanner: Storage request result: $storageStatus',
          );
        }

        // Return true if we have either permission
        final hasPermission = status.isGranted || storageStatus.isGranted;
        debugPrint(
          'DeviceFilesScanner: Final permission status: $hasPermission',
        );

        if (!hasPermission) {
          debugPrint(
            'DeviceFilesScanner: ⚠️  Storage permissions denied. Files will not be visible.',
          );
          debugPrint(
            'DeviceFilesScanner: ⚠️  Please grant "All files access" permission in Settings > Apps > openmusic > Permissions',
          );
        }

        return hasPermission;
      }

      // For non-Android platforms, assume we have permission
      return true;
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error checking permissions: $e');
      return false;
    }
  }

  /// Clean up device files from database that no longer exist on disk
  Future<int> _cleanupMissingFiles() async {
    int removedCount = 0;

    try {
      debugPrint('DeviceFilesScanner: Checking for missing files...');

      // Get all device files from the playlist
      final deviceSongIds = await PlaylistsService.getPlaylistSongs(
        PlaylistsService.deviceFilesId,
      );

      if (deviceSongIds.isEmpty) {
        debugPrint('DeviceFilesScanner: No device files to check');
        return 0;
      }

      debugPrint(
        'DeviceFilesScanner: Checking ${deviceSongIds.length} device files...',
      );

      final db = DatabaseHelper.instance;

      for (final songId in deviceSongIds) {
        try {
          final song = await db.getSong(songId);
          if (song == null) continue;

          final filePath = song['on_device_filename'] as String?;
          if (filePath == null || filePath.isEmpty) continue;

          // Check if file still exists
          final file = File(filePath);
          if (!await file.exists()) {
            debugPrint('DeviceFilesScanner: File missing, removing: $filePath');

            // Remove from playlist
            await PlaylistsService.removeSongFromPlaylist(
              PlaylistsService.deviceFilesId,
              songId,
            );

            // Remove from database
            await db.deleteSong(songId);

            removedCount++;
          }
        } catch (e) {
          debugPrint('DeviceFilesScanner: Error checking file $songId: $e');
        }
      }

      if (removedCount > 0) {
        debugPrint(
          'DeviceFilesScanner: Removed $removedCount missing files from database',
        );
      }
    } catch (e) {
      debugPrint('DeviceFilesScanner: Error during cleanup: $e');
    }

    return removedCount;
  }

  /// Cancel current scan
  void cancelScan() {
    _isScanning = false;
    debugPrint('DeviceFilesScanner: Scan cancelled');
  }
}
