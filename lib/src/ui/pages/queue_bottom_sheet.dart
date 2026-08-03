import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../services/queue_service.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/status_message_controller.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/download_menu_helper.dart';
import '../widgets/song_tile.dart';
import 'add_to_playlist_bottom_sheet.dart';
import '../../data/database_helper.dart';

bool get _isDesktopPlatform {
  try {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  } catch (e) {
    return false;
  }
}

/// Helper enum for queue item types
enum _QueueItemType { previous, current, next }

/// Helper class for queue display items
class _QueueDisplayItem {
  final String songId;
  final int originalIndex;
  final _QueueItemType displayType;

  _QueueDisplayItem({
    required this.songId,
    required this.originalIndex,
    required this.displayType,
  });
}

/// Shows the current queue in a modal bottom sheet. Height = 0.9 * screen.
Future<void> showQueueBottomSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      final height = MediaQuery.of(ctx).size.height * 0.9;
      return SizedBox(height: height, child: const _QueueSheetContent());
    },
  );
}

class _QueueSheetContent extends StatefulWidget {
  const _QueueSheetContent();

  @override
  State<_QueueSheetContent> createState() => _QueueSheetContentState();
}

class _QueueSheetContentState extends State<_QueueSheetContent> {
  final QueueService svc = QueueService.instance;

  @override
  void initState() {
    super.initState();
    svc.initialize();
    svc.addListener(_onSvc);
  }

  @override
  void dispose() {
    svc.removeListener(_onSvc);
    super.dispose();
  }

  void _onSvc() => setState(() {});

  /// Handle reordering of display items and map back to queue positions
  void _onReorderDisplayItems(
    QueueService q,
    List<_QueueDisplayItem> displayItems,
    int oldIndex,
    int newIndex,
  ) {
    // Handle the case where newIndex equals list length (dragging to end)
    // Only clamp if it goes beyond the list length, allow dragging to the end
    if (newIndex > displayItems.length) {
      newIndex = displayItems.length;
    }

    // Map display indices back to original queue positions
    final oldOriginalIndex = displayItems[oldIndex].originalIndex;

    // For dragging to the end, use the last item's index + 1 or handle appropriately
    int newOriginalIndex;
    if (newIndex >= displayItems.length) {
      // Moving to end - use the queue service's logic for end positioning
      newOriginalIndex = q.queue.length;
    } else {
      newOriginalIndex = displayItems[newIndex].originalIndex;
    }

    // Perform the reorder in the actual queue
    q.reorder(oldOriginalIndex, newOriginalIndex);

    // Force immediate UI update to prevent visual glitch
    setState(() {});
  }

  /// Build queue list with current song at top and previous songs accessible by scrolling up
  Widget _buildQueueList(QueueService q) {
    if (q.queue.isEmpty) {
      return const Center(child: Text('Queue is empty'));
    }

    // Create display order: previous songs + current song + next songs
    final displayItems = <_QueueDisplayItem>[];
    final currentIdx = q.currentIndex;

    // Add previous songs (before current index) - these will appear at top when scrolling up
    for (int i = 0; i < currentIdx; i++) {
      displayItems.add(
        _QueueDisplayItem(
          songId: q.queue[i],
          originalIndex: i,
          displayType: _QueueItemType.previous,
        ),
      );
    }

    // Add current song (will be at top of visible area initially)
    if (currentIdx < q.queue.length) {
      displayItems.add(
        _QueueDisplayItem(
          songId: q.queue[currentIdx],
          originalIndex: currentIdx,
          displayType: _QueueItemType.current,
        ),
      );
    }

    // Add next songs (after current index)
    for (int i = currentIdx + 1; i < q.queue.length; i++) {
      displayItems.add(
        _QueueDisplayItem(
          songId: q.queue[i],
          originalIndex: i,
          displayType: _QueueItemType.next,
        ),
      );
    }

    return ReorderableListView.builder(
      // Start at the current song position (previous songs are above, accessible by scrolling up)
      scrollController: ScrollController(
        initialScrollOffset: currentIdx > 0 ? currentIdx * 72.0 : 0,
      ),
      buildDefaultDragHandles:
          !_isDesktopPlatform, // Disable default handles on desktop
      itemCount: displayItems.length,
      onReorder: (oldIndex, newIndex) =>
          _onReorderDisplayItems(q, displayItems, oldIndex, newIndex),
      itemBuilder: (ctx, displayIdx) {
        final item = displayItems[displayIdx];
        final isCurrentSong = item.displayType == _QueueItemType.current;

        final songTile = SongTile.database(
          songId: item.songId,
          onTap: () async {
            // Move to this index and start playing
            await q.moveToIndex(item.originalIndex);
            await SimplePlaybackController.instance.play(item.songId, null);

            // Don't close the sheet - user can manually close when they want
          },
          menuOptions: [
            PopupMenuOption(
              id: 'add_to_playlist',
              label: 'Add to playlist',
              onSelected: () async {
                // Capture context before async operations
                final contextRef = context;

                // Get song title for display
                String? songTitle;
                try {
                  final song = await DatabaseHelper.instance.getSong(
                    item.songId,
                  );
                  songTitle = song?['title'] as String?;
                } catch (e) {
                  debugPrint('Error getting song title: $e');
                }

                // Check if widget is still mounted before using context
                if (contextRef.mounted) {
                  showAddToPlaylistBottomSheet(
                    contextRef,
                    item.songId,
                    songTitle: songTitle,
                  );
                }
              },
            ),
            ...MusicNavigationHelper.createNavigationMenuOptions(
              context,
              item.songId,
            ),
            PopupMenuOption(
              id: 'save_to_disk',
              label: 'Save to disk',
              onSelected: () async {
                final savedContext = context;
                // Fetch song data to check if it's available for saving
                final song = await DatabaseHelper.instance.getSong(item.songId);
                if (song == null) return;

                final isDeviceFile =
                    song['source'] == 'device' ||
                    song['is_device_file'] == 'true';
                final isOfflineAvailable =
                    !isDeviceFile &&
                    song['on_device_status'] == 'true' &&
                    song['on_device_filename'] != null &&
                    (song['on_device_filename'] as String).isNotEmpty;

                if (!isOfflineAvailable) {
                  StatusMessageController.instance.showMessage(
                    'Song not available offline',
                    duration: const Duration(milliseconds: 2000),
                  );
                  return;
                }

                if (savedContext.mounted) {
                  SaveToDiskHelper.saveToDisk(
                    context: savedContext,
                    songId: item.songId,
                    sourceFilePath: song['on_device_filename'] as String?,
                    songTitle: song['title'] as String?,
                    artistName: song['artists'] as String?,
                  );
                }
              },
            ),
            // Download / Redownload options (not for device files)
            ...DownloadMenuHelper.createDownloadMenuOptions(
              songId: item.songId,
              context: context,
            ),
            // Remove from library option (not for device files)
            PopupMenuOption(
              id: 'remove_from_library',
              label: 'Remove from Library',
              onSelected: () async {
                final song = await DatabaseHelper.instance.getSong(item.songId);
                if (song == null) return;

                final isDeviceFile =
                    song['source'] == 'device' ||
                    song['is_device_file'] == 'true';
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
                  item.songId,
                  songTitle,
                  onRemoved: () {
                    // Also remove from queue when removed from library
                    q.removeAt(item.originalIndex);
                  },
                );
              },
            ),
            PopupMenuOption(
              id: 'remove',
              label: 'Remove from queue',
              onSelected: () async {
                await q.removeAt(item.originalIndex);
              },
            ),
          ],
        );

        // On desktop, wrap with Row that has drag handle on left
        if (_isDesktopPlatform) {
          return Container(
            key: ValueKey('row_${item.originalIndex}_${item.songId}'),
            decoration: isCurrentSong
                ? BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                  )
                : null,
            child: Row(
              children: [
                // Drag handle on left for desktop
                ReorderableDragStartListener(
                  index: displayIdx,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(
                      Icons.drag_handle,
                      color: Theme.of(
                        context,
                      ).iconTheme.color?.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Expanded(child: songTile),
              ],
            ),
          );
        }

        // On mobile, use normal layout (default drag handles work fine)
        return Container(
          key: ValueKey('row_${item.originalIndex}_${item.songId}'),
          decoration: isCurrentSong
              ? BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 4,
                    ),
                  ),
                )
              : null,
          child: songTile,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = svc;
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Queue (${q.queue.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: q.queue.isEmpty
                    ? null
                    : () async {
                        await q.toggleShuffle();
                      },
                icon: Icon(
                  Icons.shuffle,
                  color: q.shuffleEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).iconTheme.color,
                ),
              ),
              IconButton(
                onPressed: q.queue.isEmpty
                    ? null
                    : () async {
                        await q.cycleRepeatMode();
                      },
                icon: Icon(
                  q.repeatMode == 2 ? Icons.repeat_one : Icons.repeat,
                  color: q.repeatMode == 0
                      ? Theme.of(context).iconTheme.color
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Queue list with current song at top
        Expanded(child: _buildQueueList(q)),
      ],
    );
  }
}
