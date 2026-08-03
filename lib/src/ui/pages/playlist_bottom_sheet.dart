import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../../services/playlists_service.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/device_files_scanner.dart';
import '../../services/download_helper.dart';
import '../../services/queue_service.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/download_menu_helper.dart';
import '../../data/database_helper.dart';
import '../widgets/song_tile.dart';
import 'add_to_playlist_bottom_sheet.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/status_message_controller.dart';

bool get _isDesktopPlatform {
  try {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  } catch (e) {
    return false;
  }
}

class PlaylistBottomSheet extends StatefulWidget {
  final String playlistId;
  final String playlistName;

  const PlaylistBottomSheet({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  State<PlaylistBottomSheet> createState() => _PlaylistBottomSheetState();
}

class _PlaylistBottomSheetState extends State<PlaylistBottomSheet> {
  List<String> _songIds = [];
  bool _loading = true;
  String _totalStorageSize = '';
  bool _isOfflinePlaylist = false;
  bool _isDeviceFilesPlaylist = false;

  // Device file scanning state
  bool _isScanning = false;
  int _scanProgress = 0;
  int _totalFilesToScan = 0;
  String _currentScanPath = '';

  // Playlist rename state
  late String _playlistName;
  late TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();
  bool _isEditingName = false;

  @override
  void initState() {
    super.initState();
    _playlistName = widget.playlistName;
    _nameController = TextEditingController(text: _playlistName);
    _isOfflinePlaylist = widget.playlistId == PlaylistsService.offlineSongsId;
    _isDeviceFilesPlaylist =
        widget.playlistId == PlaylistsService.deviceFilesId;

    // Listen for focus changes to detect when editing ends
    _nameFocusNode.addListener(_onNameFocusChange);

    // Listen for download completion to refresh storage calculations
    if (_isOfflinePlaylist) {
      DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
    }

    _loadPlaylistSongs();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.removeListener(_onNameFocusChange);
    _nameFocusNode.dispose();
    if (_isOfflinePlaylist) {
      DownloadHelper.instance.removeDownloadCompleteListener(
        _onDownloadComplete,
      );
    }
    super.dispose();
  }

  void _onNameFocusChange() {
    if (!_nameFocusNode.hasFocus && _isEditingName) {
      _savePlaylistName();
    }
  }

  void _startEditingName() {
    if (_isDefaultPlaylist()) return; // Don't allow renaming default playlists

    setState(() {
      _isEditingName = true;
      _nameController.text = _playlistName;
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _playlistName.length,
      );
    });

    // Request focus after the next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
    });
  }

  Future<void> _savePlaylistName() async {
    final newName = _nameController.text.trim();

    setState(() {
      _isEditingName = false;
    });

    if (newName.isEmpty) {
      // Restore original name if empty
      _nameController.text = _playlistName;
      return;
    }

    if (newName == _playlistName) {
      // No change
      return;
    }

    try {
      await PlaylistsService.renamePlaylist(widget.playlistId, newName);
      setState(() {
        _playlistName = newName;
      });
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Playlist renamed to "$newName"',
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error renaming playlist: $e');
      _nameController.text = _playlistName; // Restore original
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to rename playlist',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  void _onDownloadComplete(String songId) {
    if (mounted && _isOfflinePlaylist) {
      debugPrint(
        'PlaylistBottomSheet: Download completed for $songId, refreshing...',
      );
      _loadPlaylistSongs();
      _calculateStorageSize();
    }
  }

  Future<void> _loadPlaylistSongs() async {
    try {
      // For device files playlist, load from DB first, then scan in background
      if (_isDeviceFilesPlaylist) {
        // First load existing songs from DB immediately
        await _loadPlaylistSongsFromDb();
        // Then start background scan to find new files (don't await)
        _startDeviceFileScan();
      } else {
        await _loadPlaylistSongsFromDb();
      }
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error loading songs: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Load playlist songs from DB without triggering a scan
  Future<void> _loadPlaylistSongsFromDb() async {
    final songIds = await PlaylistsService.getPlaylistSongs(widget.playlistId);
    if (!mounted) return;
    setState(() {
      _songIds = songIds;
      _loading = false;
    });
    if (_isOfflinePlaylist) {
      _calculateStorageSize();
    }
  }

  Future<void> _reorderSongs(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    // Update local state immediately for smooth UI
    setState(() {
      final item = _songIds.removeAt(oldIndex);
      _songIds.insert(newIndex, item);
    });

    // Update in database
    try {
      await PlaylistsService.reorderPlaylistSongs(
        widget.playlistId,
        oldIndex,
        newIndex,
      );
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error reordering songs: $e');
      // Reload the list to restore correct order if database update failed
      _loadPlaylistSongs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9; // More conservative height

    // Match the nav bar background color
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final navBg = theme.brightness == Brightness.dark
        ? Color.lerp(scaffoldBg, Colors.white, 0.06)!
        : Color.lerp(scaffoldBg, Colors.black, 0.02)!;

    return Container(
      height: maxHeight, // Constant height, not max constraint
      decoration: BoxDecoration(
        color: navBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(top: 25, bottom: 30, left: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Editable playlist name for non-default playlists
                      if (_isEditingName && !_isDefaultPlaylist())
                        TextField(
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _savePlaylistName(),
                        )
                      else
                        GestureDetector(
                          onTap: _isDefaultPlaylist()
                              ? null
                              : _startEditingName,
                          child: Text(
                            _playlistName,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Text(
                        '${_songIds.length} songs',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Manage folders chip for device files playlist
                if (_isDeviceFilesPlaylist)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: Icon(
                        _isScanning ? Icons.hourglass_empty : Icons.folder_open,
                        size: 18,
                        color: _isScanning
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                      label: Text(
                        _isScanning ? 'Scanning...' : 'Manage Folders',
                      ),
                      onPressed: _isScanning ? null : _showManageFoldersSheet,
                      backgroundColor: _isScanning
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest
                          : Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                      side: BorderSide(
                        color: _isScanning
                            ? Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.3)
                            : Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                      labelStyle: TextStyle(
                        color: _isScanning
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'queue':
                        debugPrint('Queue up playlist: ${widget.playlistId}');
                        break;
                      case 'download_all':
                        _downloadAllSongs();
                        break;
                      case 'rename':
                        _startEditingName();
                        break;
                      case 'delete':
                        _showDeletePlaylistDialog();
                        break;
                      case 'scan':
                        _startDeviceFileScan();
                        break;
                    }
                  },
                  itemBuilder: (context) {
                    if (_isDefaultPlaylist()) {
                      final menuItems = <PopupMenuItem<String>>[
                        const PopupMenuItem(
                          value: 'queue',
                          child: Row(
                            children: [
                              Icon(Icons.queue_music),
                              SizedBox(width: 12),
                              Text('Queue Up'),
                            ],
                          ),
                        ),
                      ];

                      // Add download all option for non-device-files default playlists
                      if (!_isDeviceFilesPlaylist) {
                        menuItems.add(
                          const PopupMenuItem(
                            value: 'download_all',
                            child: Row(
                              children: [
                                Icon(Icons.download),
                                SizedBox(width: 12),
                                Text('Download All'),
                              ],
                            ),
                          ),
                        );
                      }

                      // Add scan option for device files playlist
                      if (_isDeviceFilesPlaylist) {
                        menuItems.add(
                          PopupMenuItem(
                            value: 'scan',
                            enabled: !_isScanning,
                            child: Row(
                              children: [
                                Icon(
                                  _isScanning
                                      ? Icons.hourglass_empty
                                      : Icons.refresh,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _isScanning ? 'Scanning...' : 'Scan Device',
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return menuItems;
                    } else {
                      return [
                        const PopupMenuItem(
                          value: 'queue',
                          child: Row(
                            children: [
                              Icon(Icons.queue_music),
                              SizedBox(width: 12),
                              Text('Queue Up'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'download_all',
                          child: Row(
                            children: [
                              Icon(Icons.download),
                              SizedBox(width: 12),
                              Text('Download All'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit),
                              SizedBox(width: 12),
                              Text('Rename'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete),
                              SizedBox(width: 12),
                              Text('Delete List'),
                            ],
                          ),
                        ),
                      ];
                    }
                  },
                ),
              ],
            ),
          ),

          // Device file scanning progress bar
          if (_isDeviceFilesPlaylist && _isScanning)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Scanning device for music files...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _totalFilesToScan > 0
                        ? _scanProgress / _totalFilesToScan
                        : null,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 8),
                  if (_totalFilesToScan > 0)
                    Text(
                      '$_scanProgress / $_totalFilesToScan files scanned',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (_currentScanPath.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Current: ${_getCurrentScanFileName()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),

          // Storage info bar for offline playlist
          if (_isOfflinePlaylist && !_loading && _songIds.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.storage,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Total storage: $_totalStorageSize',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showDeleteAllDialog(),
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Delete All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Songs list
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_songIds.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.queue_music_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No songs in this playlist',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add songs to get started',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // Use regular ListView for default playlists (no reordering), ReorderableListView for custom playlists
            Flexible(
              child: _isDefaultPlaylist()
                  ? ListView.builder(
                      shrinkWrap: true,
                      itemCount: _songIds.length,
                      itemBuilder: (context, index) {
                        final songId = _songIds[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 6,
                          ),
                          child: Card(
                            elevation: 0,
                            margin: EdgeInsets.zero,
                            child: SongTile.database(
                              songId: songId,
                              onTap: () async {
                                try {
                                  // Check if this exact song in this exact playlist context is already playing
                                  final currentContext =
                                      QueueService.instance.playbackContext;
                                  final currentContextId =
                                      QueueService.instance.playbackContextId;
                                  final currentSongId = SimplePlaybackController
                                      .instance
                                      .currentSongId;
                                  final isExactSamePlayback =
                                      currentContext ==
                                          PlaybackContext.playlist &&
                                      currentContextId == widget.playlistId &&
                                      currentSongId == songId;

                                  debugPrint(
                                    'PlaylistBottomSheet: Context check - currentContext: $currentContext, currentContextId: $currentContextId, currentSongId: $currentSongId',
                                  );
                                  debugPrint(
                                    'PlaylistBottomSheet: This playlistId: ${widget.playlistId}, tapped songId: $songId',
                                  );
                                  debugPrint(
                                    'PlaylistBottomSheet: isExactSamePlayback: $isExactSamePlayback',
                                  );

                                  if (isExactSamePlayback) {
                                    // Exact same song in same playlist context - just toggle play/pause
                                    if (SimplePlaybackController
                                        .instance
                                        .isPlaying) {
                                      await SimplePlaybackController.instance
                                          .pause();
                                    } else {
                                      await SimplePlaybackController.instance
                                          .resume();
                                    }
                                  } else {
                                    // Different song or different context - set new queue and play
                                    await QueueService.instance.setQueue(
                                      _songIds,
                                      startIndex: index,
                                      context: PlaybackContext.playlist,
                                      contextId: widget.playlistId,
                                    );
                                    await SimplePlaybackController.instance
                                        .play(songId, null);
                                  }

                                  // Play count will be automatically tracked by SimplePlaybackController

                                  debugPrint(
                                    'Started playing song: $songId at index $index of ${_songIds.length} songs',
                                  );
                                } catch (e) {
                                  debugPrint('Error playing song $songId: $e');
                                }
                              },
                              menuOptions: _getMenuOptionsForSong(songId),
                            ),
                          ),
                        );
                      },
                    )
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      onReorder: _reorderSongs,
                      buildDefaultDragHandles: !_isDesktopPlatform,
                      itemCount: _songIds.length,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            return Material(
                              elevation: 8,
                              shadowColor: Colors.black.withValues(alpha: .2),
                              borderRadius: BorderRadius.circular(8),
                              child: child,
                            );
                          },
                          child: child,
                        );
                      },
                      itemBuilder: (context, index) {
                        final songId = _songIds[index];
                        final songTile = SongTile.database(
                          songId: songId,
                          onTap: () async {
                            try {
                              // Check if this exact song in this exact playlist context is already playing
                              final currentContext =
                                  QueueService.instance.playbackContext;
                              final currentContextId =
                                  QueueService.instance.playbackContextId;
                              final currentSongId = SimplePlaybackController
                                  .instance
                                  .currentSongId;
                              final isExactSamePlayback =
                                  currentContext == PlaybackContext.playlist &&
                                  currentContextId == widget.playlistId &&
                                  currentSongId == songId;

                              debugPrint(
                                'PlaylistBottomSheet: Context check - currentContext: $currentContext, currentContextId: $currentContextId, currentSongId: $currentSongId',
                              );
                              debugPrint(
                                'PlaylistBottomSheet: This playlistId: ${widget.playlistId}, tapped songId: $songId',
                              );
                              debugPrint(
                                'PlaylistBottomSheet: isExactSamePlayback: $isExactSamePlayback',
                              );

                              if (isExactSamePlayback) {
                                // Exact same song in same playlist context - just toggle play/pause
                                if (SimplePlaybackController
                                    .instance
                                    .isPlaying) {
                                  await SimplePlaybackController.instance
                                      .pause();
                                } else {
                                  await SimplePlaybackController.instance
                                      .resume();
                                }
                              } else {
                                // Different song or different context - set new queue and play
                                await QueueService.instance.setQueue(
                                  _songIds,
                                  startIndex: index,
                                  context: PlaybackContext.playlist,
                                  contextId: widget.playlistId,
                                );
                                await SimplePlaybackController.instance.play(
                                  songId,
                                  null,
                                );
                              }

                              // Play count will be automatically tracked by SimplePlaybackController

                              debugPrint(
                                'Started playing song: $songId at index $index of ${_songIds.length} songs',
                              );
                            } catch (e) {
                              debugPrint('Error playing song $songId: $e');
                            }
                          },
                          menuOptions: _getMenuOptionsForSong(songId),
                        );

                        // On desktop, wrap with Row that has drag handle on left
                        if (_isDesktopPlatform) {
                          return Container(
                            key: ValueKey(songId),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 6,
                            ),
                            child: Card(
                              elevation: 0,
                              margin: EdgeInsets.zero,
                              child: Row(
                                children: [
                                  // Drag handle on left for desktop
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: Icon(
                                        Icons.drag_handle,
                                        color: Theme.of(context).iconTheme.color
                                            ?.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                  Expanded(child: songTile),
                                ],
                              ),
                            ),
                          );
                        }

                        // On mobile, use normal layout
                        return Container(
                          key: ValueKey(songId),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 6,
                          ),
                          child: Card(
                            elevation: 0,
                            margin: EdgeInsets.zero,
                            child: songTile,
                          ),
                        );
                      },
                    ),
            ),

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Future<void> _calculateStorageSize() async {
    if (!_isOfflinePlaylist) return;

    try {
      int totalBytes = 0;
      final db = DatabaseHelper.instance;

      debugPrint(
        'PlaylistBottomSheet: Calculating storage for ${_songIds.length} songs',
      );

      for (final songId in _songIds) {
        final song = await db.getSong(songId);
        if (song != null) {
          final onDeviceStatus = song['on_device_status'] as String?;
          final filePath = song['on_device_filename'] as String?;

          debugPrint(
            'PlaylistBottomSheet: Song $songId - onDeviceStatus: $onDeviceStatus, filePath: $filePath',
          );

          if (onDeviceStatus == 'true' &&
              filePath != null &&
              filePath.isNotEmpty) {
            final file = File(filePath);
            final exists = await file.exists();
            debugPrint(
              'PlaylistBottomSheet: File exists: $exists for path: $filePath',
            );

            if (exists) {
              final size = await file.length();
              totalBytes += size;
              debugPrint('PlaylistBottomSheet: Added $size bytes from $songId');
            }
          }
        } else {
          debugPrint('PlaylistBottomSheet: Song $songId not found in database');
        }
      }

      debugPrint('PlaylistBottomSheet: Total bytes calculated: $totalBytes');

      if (mounted) {
        setState(() {
          _totalStorageSize = _formatBytes(totalBytes);
        });
      }
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error calculating storage size: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _deleteAllOfflineFiles() async {
    if (!_isOfflinePlaylist) return;

    try {
      for (final songId in _songIds) {
        await _deleteOfflineFile(songId);
      }

      // Refresh the list and storage size
      _loadPlaylistSongs();
      _calculateStorageSize();

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'All offline files deleted',
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error deleting all offline files: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Error deleting files: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  Future<void> _deleteOfflineFile(String songId) async {
    try {
      final db = DatabaseHelper.instance;
      final song = await db.getSong(songId);

      if (song != null) {
        final filePath = song['on_device_filename'] as String?;
        if (filePath != null && filePath.isNotEmpty) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }

        // Update database to mark as not on device
        await db.updateSong(songId, {
          'on_device_status': 'false',
          'on_device_filename': '',
        });

        // Remove from offline playlist
        await PlaylistsService.removeSongFromPlaylist(
          PlaylistsService.offlineSongsId,
          songId,
        );
      }
    } catch (e) {
      debugPrint(
        'PlaylistBottomSheet: Error deleting offline file for $songId: $e',
      );
      rethrow;
    }
  }

  bool _isDefaultPlaylist() {
    return widget.playlistId == PlaylistsService.likedSongsId ||
        widget.playlistId == PlaylistsService.offlineSongsId ||
        widget.playlistId == PlaylistsService.deviceFilesId;
  }

  Future<void> _removeSongFromPlaylist(String songId) async {
    try {
      await PlaylistsService.removeSongFromPlaylist(widget.playlistId, songId);
      _loadPlaylistSongs(); // Refresh the list
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error removing song: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to remove song: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Offline Files'),
        content: const Text(
          'This will delete all downloaded files and remove them from the offline playlist. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteAllOfflineFiles();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  /// Download all songs in this playlist
  Future<void> _downloadAllSongs() async {
    debugPrint('_downloadAllSongs: Starting with ${_songIds.length} songs');

    if (_songIds.isEmpty) {
      StatusMessageController.instance.showMessage(
        'No songs to download',
        duration: const Duration(milliseconds: 1500),
      );
      return;
    }

    // Filter out device files and already downloaded songs
    final songsToDownload = <String>[];
    for (final songId in _songIds) {
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song == null) {
        debugPrint('_downloadAllSongs: Song $songId not found in DB');
        continue;
      }

      final isDeviceFile =
          song['source'] == 'device' || song['is_device_file'] == 'true';
      if (isDeviceFile) {
        debugPrint('_downloadAllSongs: Song $songId is device file, skipping');
        continue;
      }

      final isAlreadyDownloaded =
          song['on_device_status'] == 'true' &&
          song['on_device_filename'] != null &&
          (song['on_device_filename'] as String).isNotEmpty;
      if (isAlreadyDownloaded) {
        debugPrint(
          '_downloadAllSongs: Song $songId already downloaded, skipping',
        );
        continue;
      }

      debugPrint('_downloadAllSongs: Adding song $songId to download list');
      songsToDownload.add(songId);
    }

    debugPrint(
      '_downloadAllSongs: ${songsToDownload.length} songs to download',
    );

    if (songsToDownload.isEmpty) {
      StatusMessageController.instance.showMessage(
        'All songs already downloaded',
        duration: const Duration(milliseconds: 1500),
      );
      return;
    }

    // Queue all songs for download
    debugPrint('_downloadAllSongs: Calling downloadMultipleSongs');
    DownloadMenuHelper.downloadMultipleSongs(songsToDownload);
  }

  void _showDeletePlaylistDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Delete "${widget.playlistName}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Close the bottom sheet too
              await _deletePlaylist();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePlaylist() async {
    try {
      await PlaylistsService.deletePlaylist(widget.playlistId);
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Playlist "${widget.playlistName}" deleted',
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error deleting playlist: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to delete playlist: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  Future<void> _deleteSongFromOffline(String songId) async {
    try {
      await _deleteOfflineFile(songId);
      _loadPlaylistSongs(); // Refresh the list
      _calculateStorageSize(); // Recalculate storage
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Song deleted from offline storage',
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error deleting song from offline: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to delete song: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  /// Delete a device file from device and database
  Future<void> _deleteDeviceFile(String songId) async {
    // Get song info for confirmation dialog
    final savedContext = context;
    final song = await DatabaseHelper.instance.getSong(songId);
    if (song == null) return;
    if (!savedContext.mounted) return;

    final songTitle = song['title'] as String? ?? 'this file';

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: savedContext,
      builder: (context) => AlertDialog(
        title: const Text('Delete from device?'),
        content: Text(
          'Are you sure you want to delete "$songTitle" from your device? This cannot be undone.',
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
      final filePath = song['on_device_filename'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('PlaylistBottomSheet: Deleted file: $filePath');
        }
      }

      // Remove from playlist
      await PlaylistsService.removeSongFromPlaylist(
        PlaylistsService.deviceFilesId,
        songId,
      );

      // Remove from database
      await DatabaseHelper.instance.deleteSong(songId);

      _loadPlaylistSongs(); // Refresh the list

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'File deleted from device',
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error deleting device file: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to delete file: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  /// Get menu options for a song based on playlist type
  List<PopupMenuOption> _getMenuOptionsForSong(String songId) {
    final baseOptions = [
      PopupMenuOption(
        id: 'play_next',
        label: 'Play Next',
        onSelected: () async {
          await QueueService.instance.playNext(songId);
          String? songTitle;
          try {
            final song = await DatabaseHelper.instance.getSong(songId);
            songTitle = song?['title'] as String?;
          } catch (_) {}
          StatusMessageController.instance.showMessage(
            'Will play "${songTitle ?? 'song'}" next',
            duration: const Duration(milliseconds: 2200),
          );
        },
      ),
      PopupMenuOption(
        id: 'add_to_queue',
        label: 'Queue up',
        onSelected: () async {
          await QueueService.instance.addToQueue(songId);
          String? songTitle;
          try {
            final song = await DatabaseHelper.instance.getSong(songId);
            songTitle = song?['title'] as String?;
          } catch (_) {}
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
          String? songTitle;
          try {
            final song = await DatabaseHelper.instance.getSong(songId);
            songTitle = song?['title'] as String?;
          } catch (e) {
            debugPrint('Error getting song title: $e');
          }
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
    ];

    if (_isOfflinePlaylist) {
      // For offline playlist, add save to disk option
      return [
        ...baseOptions,
        PopupMenuOption(
          id: 'save_to_disk',
          label: 'Save to disk',
          onSelected: () async {
            final savedContext = context;
            final song = await DatabaseHelper.instance.getSong(songId);
            if (song != null && savedContext.mounted) {
              SaveToDiskHelper.saveToDisk(
                context: savedContext,
                songId: songId,
                sourceFilePath: song['on_device_filename'] as String?,
                songTitle: song['title'] as String?,
                artistName: song['artists'] as String?,
              );
            }
          },
        ),
        // Download / Redownload option for offline playlist
        PopupMenuOption(
          id: 'download_auto',
          label: 'Redownload',
          onSelected: () async {
            await DownloadMenuHelper.redownloadSongAuto(
              songId,
              songTitle: null,
            );
            _loadPlaylistSongs();
          },
        ),
        PopupMenuOption(
          id: 'download_choose_method',
          label: 'Choose Method',
          onSelected: () async {
            final method = await DownloadMenuHelper.showMethodSelectionDialog(
              context,
            );
            if (method != null) {
              await DownloadMenuHelper.redownloadSongWithMethod(
                songId,
                method,
                songTitle: null,
              );
              _loadPlaylistSongs();
            }
          },
        ),
        PopupMenuOption(
          id: 'remove_from_library',
          label: 'Remove from Library',
          onSelected: () async {
            final song = await DatabaseHelper.instance.getSong(songId);
            if (song == null) return;

            // Offline playlist songs shouldn't be device files, but check anyway
            final isDeviceFile =
                song['source'] == 'device' || song['is_device_file'] == 'true';
            if (isDeviceFile) {
              StatusMessageController.instance.showMessage(
                'Cannot remove device files from library',
                duration: const Duration(milliseconds: 2000),
              );
              return;
            }

            if (!mounted) return;
            final songTitle = song['title'] as String?;
            await MusicNavigationHelper.removeFromLibrary(
              context,
              songId,
              songTitle,
              onRemoved: () {
                // Refresh the playlist view
                _loadPlaylistSongs();
              },
            );
          },
        ),
        PopupMenuOption(
          id: 'delete',
          label: 'Delete',
          onSelected: () => _deleteSongFromOffline(songId),
        ),
      ];
    } else if (_isDeviceFilesPlaylist) {
      return [
        ...baseOptions,
        PopupMenuOption(
          id: 'delete_from_device',
          label: 'Delete from device',
          onSelected: () => _deleteDeviceFile(songId),
        ),
      ];
    } else {
      // For regular playlists, check if song is available offline and add save option
      return [
        ...baseOptions,
        PopupMenuOption(
          id: 'save_to_disk',
          label: 'Save to disk',
          onSelected: () async {
            final savedContext = context;
            final song = await DatabaseHelper.instance.getSong(songId);
            if (song != null && savedContext.mounted) {
              final isDeviceFile =
                  song['source'] == 'device' ||
                  song['is_device_file'] == 'true';
              final isOffline =
                  song['on_device_status'] == 'true' &&
                  song['on_device_filename'] != null &&
                  (song['on_device_filename'] as String).isNotEmpty;
              if (!isDeviceFile && isOffline) {
                SaveToDiskHelper.saveToDisk(
                  context: savedContext,
                  songId: songId,
                  sourceFilePath: song['on_device_filename'] as String?,
                  songTitle: song['title'] as String?,
                  artistName: song['artists'] as String?,
                );
              } else {
                StatusMessageController.instance.showMessage(
                  'Song not available offline',
                  duration: const Duration(milliseconds: 2000),
                );
              }
            }
          },
        ),
        // Download / Redownload options for regular playlist
        ...DownloadMenuHelper.createDownloadMenuOptions(
          songId: songId,
          context: context,
          onComplete: _loadPlaylistSongs,
        ),
        PopupMenuOption(
          id: 'remove_from_library',
          label: 'Remove from Library',
          onSelected: () async {
            final song = await DatabaseHelper.instance.getSong(songId);
            if (song == null) return;

            final isDeviceFile =
                song['source'] == 'device' || song['is_device_file'] == 'true';
            if (isDeviceFile) {
              StatusMessageController.instance.showMessage(
                'Cannot remove device files from library',
                duration: const Duration(milliseconds: 2000),
              );
              return;
            }

            if (!mounted) return;
            final songTitle = song['title'] as String?;
            await MusicNavigationHelper.removeFromLibrary(
              context,
              songId,
              songTitle,
              onRemoved: () {
                // Refresh the playlist view
                _loadPlaylistSongs();
              },
            );
          },
        ),
        PopupMenuOption(
          id: 'remove',
          label: 'Remove from playlist',
          onSelected: () => _removeSongFromPlaylist(songId),
        ),
      ];
    }
  }

  /// Start device file scanning
  Future<void> _startDeviceFileScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _scanProgress = 0;
      _totalFilesToScan = 0;
      _currentScanPath = '';
    });

    try {
      debugPrint('PlaylistBottomSheet: Starting device file scan...');

      final songsAdded = await DeviceFilesScanner.instance.startScan(
        onProgress: (scanned, total, currentPath) {
          if (mounted) {
            setState(() {
              _scanProgress = scanned;
              _totalFilesToScan = total;
              _currentScanPath = currentPath;
            });
          }
        },
        onSongFound: (songId) {
          debugPrint('PlaylistBottomSheet: Found device song: $songId');
        },
      );

      debugPrint(
        'PlaylistBottomSheet: Device scan completed. Added $songsAdded songs',
      );

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Found $songsAdded music files on device',
          duration: const Duration(milliseconds: 1400),
        );
      }

      // Refresh the device files list from DB now that scanning is done
      await _loadPlaylistSongsFromDb();
    } catch (e) {
      debugPrint('PlaylistBottomSheet: Error during device scan: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Error scanning device files: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  /// Get the current scan file name from the full path
  String _getCurrentScanFileName() {
    if (_currentScanPath.isEmpty) return '';
    final parts = _currentScanPath.split('/');
    return parts.isNotEmpty ? parts.last : _currentScanPath;
  }

  /// Show manage folders bottom sheet
  Future<void> _showManageFoldersSheet() async {
    // Read existing managed folders, show the sheet, then compare after close.
    final oldFolders = await ManagedFoldersHelper.getManagedFolders();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      builder: (context) => const ManageFoldersBottomSheet(),
    );

    // After the sheet closes, check if folders changed and trigger a rescan
    try {
      final newFolders = await ManagedFoldersHelper.getManagedFolders();
      if (!listEquals(oldFolders, newFolders) && _isDeviceFilesPlaylist) {
        debugPrint(
          'PlaylistBottomSheet: Managed folders changed - triggering rescan',
        );
        // Trigger a fresh scan from the parent sheet
        await _startDeviceFileScan();
      }
    } catch (e) {
      debugPrint(
        'PlaylistBottomSheet: Error checking managed folders after sheet close: $e',
      );
    }
  }
}

/// Bottom sheet for managing scanned folders
class ManageFoldersBottomSheet extends StatefulWidget {
  const ManageFoldersBottomSheet({super.key});

  @override
  State<ManageFoldersBottomSheet> createState() =>
      _ManageFoldersBottomSheetState();
}

class _ManageFoldersBottomSheetState extends State<ManageFoldersBottomSheet> {
  List<String> _managedFolders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadManagedFolders();
  }

  Future<void> _loadManagedFolders() async {
    try {
      final folders = await ManagedFoldersHelper.getManagedFolders();
      if (mounted) {
        setState(() {
          _managedFolders = folders;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ManageFoldersBottomSheet: Error loading folders: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        if (!_managedFolders.contains(selectedDirectory)) {
          setState(() {
            _managedFolders.add(selectedDirectory);
          });
          await ManagedFoldersHelper.saveManagedFolders(_managedFolders);

          if (mounted) {
            StatusMessageController.instance.showMessage(
              'Folder added. You can close to scan from Device Files.',
              duration: const Duration(milliseconds: 1400),
            );
          }
        } else {
          if (mounted) {
            StatusMessageController.instance.showMessage(
              'Folder already added',
              duration: const Duration(milliseconds: 1200),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('ManageFoldersBottomSheet: Error adding folder: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Error adding folder: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  Future<void> _removeFolder(String folderPath) async {
    try {
      setState(() {
        _managedFolders.remove(folderPath);
      });
      await ManagedFoldersHelper.saveManagedFolders(_managedFolders);

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Folder removed successfully',
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      debugPrint('ManageFoldersBottomSheet: Error removing folder: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Error removing folder: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  // (Removed) Immediate scanning here was causing duplicate scans and UI lag.

  String _getFolderName(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isNotEmpty ? parts.last : path;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9;

    // Match the nav bar background color
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final navBg = theme.brightness == Brightness.dark
        ? Color.lerp(scaffoldBg, Colors.white, 0.06)!
        : Color.lerp(scaffoldBg, Colors.black, 0.02)!;

    return Container(
      height: maxHeight, // Constant height, not max constraint
      decoration: BoxDecoration(
        color: navBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(
              top: 25,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Folders',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_managedFolders.length} folders',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Add folder button
                FilledButton.icon(
                  onPressed: _addFolder,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Folder'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Folders list
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_managedFolders.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_off_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No folders added yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add folders to scan for music files',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _managedFolders.length,
                itemBuilder: (context, index) {
                  final folderPath = _managedFolders[index];
                  final folderName = _getFolderName(folderPath);

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(
                          Icons.folder,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          folderName,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          folderPath,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          onPressed: () => _showRemoveConfirmation(folderPath),
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  void _showRemoveConfirmation(String folderPath) {
    final folderName = _getFolderName(folderPath);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Folder'),
        content: Text('Remove "$folderName" from managed folders?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _removeFolder(folderPath);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

/// Helper class for managing scanned folders
class ManagedFoldersHelper {
  static const String _prefsKey = 'managed_folders';

  /// Get managed folders from SharedPreferences
  static Future<List<String>> getManagedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foldersJson = prefs.getString(_prefsKey) ?? '[]';
      final List<dynamic> foldersList = jsonDecode(foldersJson);
      return foldersList.map((folder) => folder.toString()).toList();
    } catch (e) {
      debugPrint('ManagedFoldersHelper: Error getting managed folders: $e');
      return [];
    }
  }

  /// Save managed folders to SharedPreferences
  static Future<void> saveManagedFolders(List<String> folders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foldersJson = jsonEncode(folders);
      await prefs.setString(_prefsKey, foldersJson);
      debugPrint(
        'ManagedFoldersHelper: Saved ${folders.length} managed folders',
      );
    } catch (e) {
      debugPrint('ManagedFoldersHelper: Error saving managed folders: $e');
    }
  }

  /// Add a folder to managed folders
  static Future<bool> addManagedFolder(String folderPath) async {
    try {
      final folders = await getManagedFolders();
      if (!folders.contains(folderPath)) {
        folders.add(folderPath);
        await saveManagedFolders(folders);
        return true;
      }
      return false; // Already exists
    } catch (e) {
      debugPrint('ManagedFoldersHelper: Error adding managed folder: $e');
      return false;
    }
  }

  /// Remove a folder from managed folders
  static Future<bool> removeManagedFolder(String folderPath) async {
    try {
      final folders = await getManagedFolders();
      if (folders.contains(folderPath)) {
        folders.remove(folderPath);
        await saveManagedFolders(folders);
        return true;
      }
      return false; // Doesn't exist
    } catch (e) {
      debugPrint('ManagedFoldersHelper: Error removing managed folder: $e');
      return false;
    }
  }
}
