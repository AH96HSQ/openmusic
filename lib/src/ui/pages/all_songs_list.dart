import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../services/download_helper.dart';
import '../widgets/song_tile.dart';
import 'add_to_playlist_bottom_sheet.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/download_menu_helper.dart';
import '../../services/status_message_controller.dart';

/// Widget that displays all songs from the database in a list
class AllSongsList extends StatefulWidget {
  const AllSongsList({super.key});

  @override
  State<AllSongsList> createState() => _AllSongsListState();
}

class _AllSongsListState extends State<AllSongsList>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _songs = [];
  bool _loading = true;
  DateTime? _lastRefresh;

  // Pagination for performance
  static const int _pageSize = 50;
  int _displayedCount = _pageSize;

  // Sort options
  static const String _sortPrefKey = 'all_songs_sort_by';
  String _sortBy = 'newest'; // 'playtime', 'name', 'newest', 'oldest'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
    _loadSortPreference();
    _loadSongs();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSort = prefs.getString(_sortPrefKey);
    if (savedSort != null && mounted) {
      setState(() {
        _sortBy = savedSort;
        _sortSongs();
      });
    }
  }

  Future<void> _saveSortPreference(String sortBy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefKey, sortBy);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DownloadHelper.instance.removeDownloadCompleteListener(_onDownloadComplete);
    super.dispose();
  }

  /// Called when a download completes - refresh to update menu options
  void _onDownloadComplete(String songId) {
    // Check if this song is in our list and refresh if so
    final hasThisSong = _songs.any((s) => s['id']?.toString() == songId);
    if (hasThisSong && mounted) {
      _loadSongs();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfNeeded();
    }
  }

  void _refreshIfNeeded() {
    final now = DateTime.now();
    if (_lastRefresh == null || now.difference(_lastRefresh!).inSeconds > 2) {
      _loadSongs();
    }
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await DatabaseHelper.instance.getAllSongs();
      if (mounted) {
        setState(() {
          _songs = songs;
          _sortSongs();
          _loading = false;
          _lastRefresh = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('AllSongsList: Error loading songs: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _lastRefresh = DateTime.now();
        });
      }
    }
  }

  void _sortSongs() {
    final sorted = List<Map<String, dynamic>>.from(_songs);
    switch (_sortBy) {
      case 'playtime':
        sorted.sort((a, b) {
          final aTime = a['play_time'] as int? ?? 0;
          final bTime = b['play_time'] as int? ?? 0;
          return bTime.compareTo(aTime); // DESC
        });
        break;
      case 'name':
        sorted.sort((a, b) {
          final aName = (a['title'] as String? ?? '').toLowerCase();
          final bName = (b['title'] as String? ?? '').toLowerCase();
          return aName.compareTo(bName); // ASC
        });
        break;
      case 'newest':
        sorted.sort((a, b) {
          final aDate = a['created_at'] as int? ?? 0;
          final bDate = b['created_at'] as int? ?? 0;
          return bDate.compareTo(aDate); // DESC
        });
        break;
      case 'oldest':
        sorted.sort((a, b) {
          final aDate = a['created_at'] as int? ?? 0;
          final bDate = b['created_at'] as int? ?? 0;
          return aDate.compareTo(bDate); // ASC
        });
        break;
    }
    _songs = sorted;
  }

  void _onSortChanged(String? newSort) {
    if (newSort != null && newSort != _sortBy) {
      setState(() {
        _sortBy = newSort;
        _sortSongs();
      });
      _saveSortPreference(newSort);
    }
  }

  Future<void> _playSong(String songId, int index) async {
    try {
      // Set queue to all songs starting from this index
      final songIds = _songs.map((s) => s['id'] as String).toList();

      await QueueService.instance.setQueue(
        songIds,
        startIndex: index,
        context: PlaybackContext.playlist,
        contextId: 'all_songs',
      );

      await SimplePlaybackController.instance.play(songId, null);
    } catch (e) {
      debugPrint('AllSongsList: Error playing song: $e');
    }
  }

  List<PopupMenuOption> _getMenuOptions(
    String songId,
    Map<String, dynamic> song,
  ) {
    final songTitle = song['title'] as String?;
    final isDeviceFile =
        song['source'] == 'device' || song['is_device_file'] == 'true';

    return [
      PopupMenuOption(
        id: 'play_next',
        label: 'Play Next',
        onSelected: () async {
          await QueueService.instance.playNext(songId);
          StatusMessageController.instance.showMessage(
            'Will play "${songTitle ?? 'song'}" next',
            duration: const Duration(milliseconds: 2200),
          );
        },
      ),
      PopupMenuOption(
        id: 'add_to_queue',
        label: 'Add to Queue',
        onSelected: () async {
          await QueueService.instance.addToQueue(songId);
          StatusMessageController.instance.showMessage(
            'Added "${songTitle ?? 'song'}" to queue',
            duration: const Duration(milliseconds: 2200),
          );
        },
      ),
      PopupMenuOption(
        id: 'add_to_playlist',
        label: 'Add to playlist',
        onSelected: () async {
          final contextRef = context;
          if (contextRef.mounted) {
            showAddToPlaylistBottomSheet(
              contextRef,
              songId,
              songTitle: songTitle,
            );
          }
        },
      ),
      ...MusicNavigationHelper.createNavigationMenuOptions(context, songId),
      // Show 'Save to disk' for non-device files that are available offline
      if (!isDeviceFile &&
          song['on_device_status'] == 'true' &&
          song['on_device_filename'] != null &&
          (song['on_device_filename'] as String).isNotEmpty)
        PopupMenuOption(
          id: 'save_to_disk',
          label: 'Save to disk',
          onSelected: () => SaveToDiskHelper.saveToDisk(
            context: context,
            songId: songId,
            sourceFilePath: song['on_device_filename'] as String?,
            songTitle: songTitle,
            artistName: song['artists'] as String?,
          ),
        ),
      // Download / Redownload options (not for device files)
      if (!isDeviceFile)
        ...DownloadMenuHelper.createDownloadMenuOptions(
          songId: songId,
          context: context,
          onComplete: _loadSongs,
        ),
      if (isDeviceFile)
        PopupMenuOption(
          id: 'delete_from_device',
          label: 'Delete from device',
          onSelected: () => _deleteFromDevice(songId, song),
        )
      else
        PopupMenuOption(
          id: 'remove_from_library',
          label: 'Remove from library',
          onSelected: () => _removeFromLibrary(songId, songTitle),
        ),
    ];
  }

  Future<void> _deleteFromDevice(
    String songId,
    Map<String, dynamic> song,
  ) async {
    final songTitle = song['title'] as String?;
    final filePath =
        song['on_device_filename'] as String? ?? song['file_path'] as String?;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from device?'),
        content: Text(
          'Are you sure you want to delete "${songTitle ?? 'this song'}" from your device? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete the file from device
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('AllSongsList: Deleted device file: $filePath');
        }
      }

      // Delete from database
      await DatabaseHelper.instance.deleteSong(songId);

      // Refresh the list
      _loadSongs();

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Deleted "${songTitle ?? 'song'}" from device',
          duration: const Duration(milliseconds: 1500),
        );
      }
    } catch (e) {
      debugPrint('AllSongsList: Error deleting song: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to delete song',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  Future<void> _removeFromLibrary(String songId, String? songTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text(
          'Are you sure you want to remove "${songTitle ?? 'this song'}" from your library? This will also delete any offline files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Get song to check for offline file
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song != null) {
        // Delete offline file if exists
        final filePath = song['on_device_filename'] as String?;
        if (filePath != null && filePath.isNotEmpty) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            debugPrint('AllSongsList: Deleted offline file: $filePath');
          }
        }
      }

      // Delete from database
      await DatabaseHelper.instance.deleteSong(songId);

      // Refresh the list
      _loadSongs();

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Removed "${songTitle ?? 'song'}" from library',
          duration: const Duration(milliseconds: 1500),
        );
      }
    } catch (e) {
      debugPrint('AllSongsList: Error removing song: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to remove song',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_songs.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No songs in your library',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with song count and sort dropdown
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_songs.length} song${_songs.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              // Sort dropdown
              DropdownButton<String>(
                value: _sortBy,
                isDense: true,
                underline: const SizedBox(),
                icon: const Icon(Icons.sort, size: 18),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                items: const [
                  DropdownMenuItem(value: 'playtime', child: Text('Playtime')),
                  DropdownMenuItem(value: 'name', child: Text('Name')),
                  DropdownMenuItem(value: 'newest', child: Text('Newest')),
                  DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                ],
                onChanged: _onSortChanged,
              ),
            ],
          ),
        ),
        // Song tiles - limited to _displayedCount for performance
        for (
          int index = 0;
          index < _displayedCount && index < _songs.length;
          index++
        )
          SongTile.fromData(
            songId: _songs[index]['id'] as String,
            songData: _songs[index],
            onTap: () => _playSong(_songs[index]['id'] as String, index),
            menuOptions: _getMenuOptions(
              _songs[index]['id'] as String,
              _songs[index],
            ),
          ),
        // Show more button if there are more songs
        if (_displayedCount < _songs.length)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _displayedCount += _pageSize;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: Text(
                  'Show more (${_songs.length - _displayedCount} remaining)',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
