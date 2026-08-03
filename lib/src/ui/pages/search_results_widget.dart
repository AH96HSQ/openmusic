import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../models/track_hit.dart';
import '../../models/search_history_item.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../services/status_message_controller.dart';
import '../../services/download_helper.dart';
import '../../data/search_history.dart';
import '../../data/database_helper.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/download_menu_helper.dart';
import '../widgets/song_tile.dart';
import 'add_to_playlist_bottom_sheet.dart';

/// A results-only search widget. The parent (e.g. LibraryPage) owns the
/// search TextField and performs the actual searches; this widget only
/// renders the results list, search history, and loading indicator.
class SearchResultsWidget extends StatefulWidget {
  final List<TrackHit> results; // Global results from backend
  final List<Map<String, dynamic>>
  libraryResults; // Library results from local playlists
  final bool loading;
  final bool loadingMore;
  final String currentQuery; // What user is currently typing
  final Function(SearchHistoryItem)?
  onHistoryTap; // Callback when history item is tapped
  final VoidCallback? onLoadMore; // Callback when user scrolls to bottom

  // Filter chip states
  final bool artistFilterActive;
  final bool albumFilterActive;
  final bool trackFilterActive;
  final Function(bool)? onArtistFilterChanged;
  final Function(bool)? onAlbumFilterChanged;
  final Function(bool)? onTrackFilterChanged;

  // Offline mode - hides global section
  final bool isOffline;

  // Track if a search has been performed (to show "no results" vs search history)
  final bool hasSearched;

  const SearchResultsWidget({
    super.key,
    required this.results,
    this.libraryResults = const [],
    this.loading = false,
    this.loadingMore = false,
    this.currentQuery = '',
    this.onHistoryTap,
    this.onLoadMore,
    this.artistFilterActive = false,
    this.albumFilterActive = false,
    this.trackFilterActive = false,
    this.onArtistFilterChanged,
    this.onAlbumFilterChanged,
    this.onTrackFilterChanged,
    this.isOffline = false,
    this.hasSearched = false,
  });

  @override
  State<SearchResultsWidget> createState() => _SearchResultsWidgetState();
}

class _SearchResultsWidgetState extends State<SearchResultsWidget> {
  List<SearchHistoryItem> _searchHistory = [];
  final ScrollController _scrollController = ScrollController();

  // Track songs that have become available offline (for live "Save to disk" updates)
  final Set<String> _offlineAvailableSongIds = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _scrollController.addListener(_onScroll);
    DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    DownloadHelper.instance.removeDownloadCompleteListener(_onDownloadComplete);
    super.dispose();
  }

  /// Called when a download completes - check if it's a song in our results
  void _onDownloadComplete(String songId) async {
    // Check if this song is in our global results
    final isInResults = widget.results.any((t) {
      final id =
          t.raw['id']?.toString() ?? t.raw['_id']?.toString() ?? t.id ?? '';
      return id == songId;
    });

    if (isInResults) {
      // Verify the song is actually available offline
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song != null &&
          song['on_device_status'] == 'true' &&
          song['on_device_filename'] != null &&
          (song['on_device_filename'] as String).isNotEmpty) {
        if (mounted) {
          setState(() {
            _offlineAvailableSongIds.add(songId);
          });
        }
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Trigger load more when user is 200px from bottom
      widget.onLoadMore?.call();
    }
  }

  Future<void> _loadHistory() async {
    final history = await SearchHistory.load();
    if (mounted) {
      setState(() => _searchHistory = history);
    }
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          Expanded(
            child: FilterChip(
              label: SizedBox(
                width: double.infinity,
                child: Text('Artist', textAlign: TextAlign.center),
              ),
              selected: widget.artistFilterActive,
              onSelected: widget.onArtistFilterChanged,
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
              checkmarkColor: Theme.of(context).colorScheme.primary,
              showCheckmark: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilterChip(
              label: SizedBox(
                width: double.infinity,
                child: Text('Album', textAlign: TextAlign.center),
              ),
              selected: widget.albumFilterActive,
              onSelected: widget.onAlbumFilterChanged,
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
              checkmarkColor: Theme.of(context).colorScheme.primary,
              showCheckmark: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilterChip(
              label: SizedBox(
                width: double.infinity,
                child: Text('Track', textAlign: TextAlign.center),
              ),
              selected: widget.trackFilterActive,
              onSelected: widget.onTrackFilterChanged,
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
              checkmarkColor: Theme.of(context).colorScheme.primary,
              showCheckmark: false,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When loading, show nothing but a large centered loading animation
    if (widget.loading) {
      return Center(
        child: LoadingAnimationWidget.threeArchedCircle(
          color: Theme.of(context).colorScheme.primary,
          size: 80,
        ),
      );
    }

    // When not loading, show filter chips and results or history
    return Column(
      children: [
        _buildFilterChips(),
        const SizedBox(height: 12),
        Expanded(
          child: widget.results.isEmpty && widget.libraryResults.isEmpty
              ? (widget.hasSearched ? _buildNoResults() : _buildSearchHistory())
              : _buildSearchResults(),
        ),
      ],
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isOffline ? Icons.wifi_off : Icons.search_off,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isOffline
                  ? 'Go online to find more songs!'
                  : 'Try a different search term',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHistory() {
    // Filter history by current query (live filtering)
    final filtered = SearchHistory.filterHistory(
      _searchHistory,
      widget.currentQuery,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8), // Reduced padding
      children: [
        if (filtered.isNotEmpty)
          ...filtered.map(
            (item) => ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
              ), // Reduced padding
              leading: Icon(
                Icons.history,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.query,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  if (item.filterType != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.filterType!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => widget.onHistoryTap?.call(item),
              trailing: IconButton(
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () async {
                  // Remove this item from history
                  final newHistory = List<SearchHistoryItem>.from(
                    _searchHistory,
                  );
                  newHistory.remove(item);
                  await SearchHistory.save(newHistory);
                  setState(() => _searchHistory = newHistory);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final hasLibraryResults = widget.libraryResults.isNotEmpty;
    // Don't show global results when offline
    final hasGlobalResults = !widget.isOffline && widget.results.isNotEmpty;
    final showSectionTitles = hasLibraryResults && hasGlobalResults;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 0),
      children: [
        // Library section
        if (hasLibraryResults) ...[
          if (showSectionTitles)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Library',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ...widget.libraryResults.map((song) => _buildLibrarySongTile(song)),
        ],

        // Global section
        if (hasGlobalResults) ...[
          if (showSectionTitles)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Global',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ...widget.results.map((t) => _buildGlobalSongTile(t)),
        ],

        // Loading indicator at the bottom
        if (widget.loadingMore)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: LoadingAnimationWidget.threeArchedCircle(
                color: Theme.of(context).colorScheme.primary,
                size: 30,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLibrarySongTile(Map<String, dynamic> song) {
    final songId = song['id'] as String;
    final title = song['title'] as String? ?? 'Unknown';

    // Check if song is available offline for save to disk option
    final isDeviceFile =
        song['source'] == 'device' || song['is_device_file'] == 'true';
    final isOfflineAvailable =
        !isDeviceFile &&
        song['on_device_status'] == 'true' &&
        song['on_device_filename'] != null &&
        (song['on_device_filename'] as String).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: SongTile.database(
        songId: songId,
        menuOptions: [
          PopupMenuOption(
            id: 'play_next',
            label: 'Play Next',
            onSelected: () async {
              await QueueService.instance.playNext(songId);
              StatusMessageController.instance.showMessage(
                'Will play "$title" next',
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
                'Added "$title" to queue',
                duration: const Duration(milliseconds: 2200),
              );
            },
          ),
          PopupMenuOption(
            id: 'add_to_playlist',
            label: 'Add to playlist',
            onSelected: () {
              showAddToPlaylistBottomSheet(context, songId, songTitle: title);
            },
          ),
          ...MusicNavigationHelper.createNavigationMenuOptions(context, songId),
          if (isOfflineAvailable)
            PopupMenuOption(
              id: 'save_to_disk',
              label: 'Save to disk',
              onSelected: () {
                SaveToDiskHelper.saveToDisk(
                  context: context,
                  songId: songId,
                  sourceFilePath: song['on_device_filename'] as String?,
                  songTitle: song['title'] as String?,
                  artistName: song['artists'] as String?,
                );
              },
            ),
          // Download / Redownload options for library songs (not device files)
          if (!isDeviceFile)
            ...DownloadMenuHelper.createDownloadMenuOptions(
              songId: songId,
              context: context,
            ),
          // Remove from library option (not for device files)
          if (!isDeviceFile)
            PopupMenuOption(
              id: 'remove_from_library',
              label: 'Remove from Library',
              onSelected: () async {
                await MusicNavigationHelper.removeFromLibrary(
                  context,
                  songId,
                  title,
                );
              },
            ),
        ],
        onTap: () async {
          // Add to search history
          if (widget.currentQuery.trim().isNotEmpty) {
            String? filterType;
            if (widget.artistFilterActive) {
              filterType = 'artist';
            } else if (widget.albumFilterActive) {
              filterType = 'album';
            } else if (widget.trackFilterActive) {
              filterType = 'track';
            }
            await SearchHistory.addQuery(
              widget.currentQuery.trim(),
              filterType: filterType,
            );
          }

          // Start playback from library/playlist context
          final currentContext = QueueService.instance.playbackContext;
          final currentSongId = SimplePlaybackController.instance.currentSongId;
          final isExactSamePlayback =
              currentContext == PlaybackContext.playlist &&
              currentSongId == songId;

          if (isExactSamePlayback) {
            if (SimplePlaybackController.instance.isPlaying) {
              await SimplePlaybackController.instance.pause();
            } else {
              await SimplePlaybackController.instance.resume();
            }
          } else {
            await QueueService.instance.setQueue(
              [songId],
              startIndex: 0,
              context: PlaybackContext.playlist,
            );
            final err = await SimplePlaybackController.instance.play(
              songId,
              song,
            );
            if (err != null) {
              debugPrint('Playback error: $err');
            } else {
              debugPrint('Playing "$title"');
            }
          }
        },
      ),
    );
  }

  Widget _buildGlobalSongTile(TrackHit t) {
    // Ensure songId matches what gets saved to database
    final songId =
        t.raw['id']?.toString() ?? t.raw['_id']?.toString() ?? t.id ?? '';
    debugPrint('SearchResults: Using songId: $songId for track: ${t.title}');
    debugPrint(
      'SearchResults: raw[id]: ${t.raw['id']}, raw[_id]: ${t.raw['_id']}, t.id: ${t.id}',
    );

    // Check if this song has become available offline
    final isOfflineAvailable = _offlineAvailableSongIds.contains(songId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0), // Reduced padding
      child: SongTile.custom(
        songId: songId,
        title: t.title,
        artists: t.artists.join(', '),
        album: t.album,
        albumArtUrl: t.artworkUrl,
        raw: t.raw,
        menuOptions: [
          PopupMenuOption(
            id: 'play_next',
            label: 'Play Next',
            onSelected: () async {
              await QueueService.instance.playNext(songId);
              StatusMessageController.instance.showMessage(
                'Will play "${t.title}" next',
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
                'Added "${t.title}" to queue',
                duration: const Duration(milliseconds: 2200),
              );
            },
          ),
          PopupMenuOption(
            id: 'add_to_playlist',
            label: 'Add to playlist',
            onSelected: () {
              showAddToPlaylistBottomSheet(context, songId, songTitle: t.title);
            },
          ),
          ...MusicNavigationHelper.createNavigationMenuOptions(context, songId),
          if (isOfflineAvailable)
            PopupMenuOption(
              id: 'save_to_disk',
              label: 'Save to disk',
              onSelected: () async {
                final song = await DatabaseHelper.instance.getSong(songId);
                if (song != null && mounted) {
                  SaveToDiskHelper.saveToDisk(
                    context: context,
                    songId: songId,
                    sourceFilePath: song['on_device_filename'] as String?,
                    songTitle: song['title'] as String?,
                    artistName: song['artists'] as String?,
                  );
                }
              },
            ),
          // Download / Redownload option for global search results
          PopupMenuOption(
            id: 'download_auto',
            label: isOfflineAvailable ? 'Redownload' : 'Download',
            onSelected: () async {
              if (isOfflineAvailable) {
                await DownloadMenuHelper.redownloadSongAuto(
                  songId,
                  songTitle: t.title,
                );
              } else {
                await DownloadMenuHelper.downloadSongAuto(
                  songId,
                  songTitle: t.title,
                );
              }
            },
          ),
          PopupMenuOption(
            id: 'download_choose_method',
            label: 'Choose Method',
            onSelected: () async {
              final method = await DownloadMenuHelper.showMethodSelectionDialog(
                context,
              );
              if (method == null) return;
              if (isOfflineAvailable) {
                await DownloadMenuHelper.redownloadSongWithMethod(
                  songId,
                  method,
                  songTitle: t.title,
                );
              } else {
                await DownloadMenuHelper.downloadSongWithMethod(
                  songId,
                  method,
                  songTitle: t.title,
                );
              }
            },
          ),
        ],
        onTap: () async {
          // Add to search history when user taps a result
          if (widget.currentQuery.trim().isNotEmpty) {
            String? filterType;
            if (widget.artistFilterActive) {
              filterType = 'artist';
            } else if (widget.albumFilterActive) {
              filterType = 'album';
            } else if (widget.trackFilterActive) {
              filterType = 'track';
            }
            await SearchHistory.addQuery(
              widget.currentQuery.trim(),
              filterType: filterType,
            );
          }

          // Start playback without navigating anywhere. The
          // SongTile will already persist the full `raw` item
          // to the DB; here we tell the playback controller to
          // mark this song as current and persist that id.
          final id = songId;

          String? err;
          // Check if this exact song from search context is already playing
          final currentContext = QueueService.instance.playbackContext;
          final currentSongId = SimplePlaybackController.instance.currentSongId;
          final isExactSamePlayback =
              currentContext == PlaybackContext.search && currentSongId == id;

          if (isExactSamePlayback) {
            // Exact same search song is playing - just toggle play/pause
            if (SimplePlaybackController.instance.isPlaying) {
              await SimplePlaybackController.instance.pause();
            } else {
              await SimplePlaybackController.instance.resume();
            }
          } else {
            // Different song or different context - set new queue and play
            await QueueService.instance.setQueue(
              [id],
              startIndex: 0,
              context: PlaybackContext.search,
            );
            err = await SimplePlaybackController.instance.play(id, t.raw);
          }
          if (err != null) {
            // Snackbar removed - error logged to console
            debugPrint('Playback error: $err');
          } else {
            // Snackbar removed - success logged to console
            debugPrint('Playing "${t.title}"');
          }
        },
      ), // Close SongTile.custom
    ); // Close Padding
  }
}
