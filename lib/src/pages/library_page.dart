import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/pages/search_results_widget.dart' as ui_search;
import '../repositories/search_repository.dart';
import '../models/track_hit.dart';
import '../data/search_history.dart';
import '../data/database_helper.dart';
import '../services/download_helper.dart';
import '../ui/widgets/recent_wheel.dart';
import '../ui/widgets/playlists_list.dart';
import '../ui/widgets/library_section_selector.dart';
import '../ui/pages/playlist_bottom_sheet.dart';
import '../ui/pages/all_songs_list.dart';
import '../ui/pages/artists_list.dart';
import '../ui/pages/albums_list.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage> with WidgetsBindingObserver {
  bool _searchActive = false;
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  final List<TrackHit> _searchResults = <TrackHit>[]; // Global results
  final List<Map<String, dynamic>> _libraryResults =
      <Map<String, dynamic>>[]; // Library results
  bool _loading = false;
  bool _loadingMore = false;
  late final SearchRepository _searchRepo;

  // Public getter for search state
  bool get isSearchActive => _searchActive;

  // Pagination state
  int _currentOffset = 0;
  String _currentQuery = '';
  bool _hasMore = true;
  static const int _pageSize = 20;

  // Filter chip states
  bool _artistFilterActive = false;
  bool _albumFilterActive = false;
  bool _trackFilterActive = false;

  // Offline mode state
  bool _isOffline = false;

  // Track if a search has been performed (to show "no results" vs search history)
  bool _hasSearched = false;

  // Key to force PlaylistsList refresh
  Key _playlistsListKey = UniqueKey();

  // Library section state
  LibrarySection _currentSection = LibrarySection.playlists;

  // PageController for swiping between sections
  late PageController _sectionPageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // SearchRepository uses SpotifyClient directly - no backend needed
    _searchRepo = SearchRepository(baseUrl: '');
    // Initialize page controller with playlists as default (index 1)
    _sectionPageController = PageController(
      initialPage: LibrarySection.values.indexOf(_currentSection),
    );
    // Listen for download completion to refresh search results
    DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DownloadHelper.instance.removeDownloadCompleteListener(_onDownloadComplete);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _sectionPageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh playlists when app comes back to foreground
      _refreshPlaylists();
    }
  }

  /// Called when a download completes - refresh library search results
  void _onDownloadComplete(String songId) {
    // If search is active with results, refresh the library results
    if (_searchActive && _currentQuery.isNotEmpty && mounted) {
      _refreshLibraryResults();
    }
  }

  /// Refresh only the library results portion of search
  Future<void> _refreshLibraryResults() async {
    if (_currentQuery.isEmpty) return;

    try {
      String? filterType;
      if (_artistFilterActive) {
        filterType = 'artist';
      } else if (_albumFilterActive) {
        filterType = 'album';
      } else if (_trackFilterActive) {
        filterType = 'track';
      }

      final libraryItems = await DatabaseHelper.instance.searchLibrarySongs(
        query: _currentQuery,
        filterType: filterType,
      );

      if (mounted) {
        setState(() {
          _libraryResults
            ..clear()
            ..addAll(libraryItems);
        });
      }
    } catch (e) {
      debugPrint('Failed to refresh library results: $e');
    }
  }

  void _refreshPlaylists() {
    // Force PlaylistsList widget to rebuild by changing its key
    setState(() {
      _playlistsListKey = UniqueKey();
    });
  }

  void _openSearch() {
    setState(() => _searchActive = true);
    // request focus and show keyboard after the UI updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocus);
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _searchResults.clear();
      _libraryResults.clear();
      _searchCtrl.clear();
      _hasSearched = false;
      // Reset pagination state
      _currentOffset = 0;
      _currentQuery = '';
      _hasMore = true;
      _loadingMore = false;
      // Reset filter chips
      _artistFilterActive = false;
      _albumFilterActive = false;
      _trackFilterActive = false;
    });
  }

  // Public method to close search (for back button handling)
  void closeSearch() {
    _closeSearch();
  }

  // Public method to open search (for first launch)
  void openSearch() {
    _openSearch();
  }

  Future<void> _doSearch([String? query, bool isLoadMore = false]) async {
    final q = (query ?? _searchCtrl.text).trim();
    if (q.isEmpty) return;

    // For new searches, reset pagination state
    if (!isLoadMore) {
      _currentOffset = 0;
      _currentQuery = q;
      _hasMore = true;
      // Close keyboard when search is performed
      FocusScope.of(context).unfocus();
      // Update controller if query was provided
      if (query != null) {
        _searchCtrl.text = query;
      }
    }

    // Don't proceed if we're already loading or have no more results
    if ((isLoadMore && _loadingMore) || (isLoadMore && !_hasMore)) return;

    // Show loading immediately before connectivity check
    setState(() {
      if (isLoadMore) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
    });

    // Check connectivity (this may take up to 2 seconds if offline)
    final isOnline = await _searchRepo.checkConnectivity();

    // Update offline status
    if (mounted) {
      setState(() {
        _isOffline = !isOnline;
      });
    }

    try {
      // Search library (local playlists) - only on new searches, not load more
      List<Map<String, dynamic>> libraryItems = [];
      if (!isLoadMore) {
        String? filterType;
        if (_artistFilterActive) {
          filterType = 'artist';
        } else if (_albumFilterActive) {
          filterType = 'album';
        } else if (_trackFilterActive) {
          filterType = 'track';
        }
        libraryItems = await DatabaseHelper.instance.searchLibrarySongs(
          query: q,
          filterType: filterType,
        );
      }

      // Only search Spotify (global) if we're online
      // When offline, we only show library results
      List<TrackHit> items = [];

      if (!_isOffline) {
        if (_artistFilterActive) {
          items = await _searchRepo.searchByArtist(
            q,
            limit: _pageSize,
            offset: _currentOffset,
          );
        } else if (_albumFilterActive) {
          items = await _searchRepo.searchByAlbum(
            q,
            limit: _pageSize,
            offset: _currentOffset,
          );
        } else if (_trackFilterActive) {
          items = await _searchRepo.searchByTrack(
            q,
            limit: _pageSize,
            offset: _currentOffset,
          );
        } else {
          // No filters active - use general search
          items = await _searchRepo.searchTracks(
            q,
            limit: _pageSize,
            offset: _currentOffset,
          );
        }
      }

      if (!mounted) return;

      // Add to search history when search is performed (only for new searches)
      if (!isLoadMore) {
        String? filterType;
        if (_artistFilterActive) {
          filterType = 'artist';
        } else if (_albumFilterActive) {
          filterType = 'album';
        } else if (_trackFilterActive) {
          filterType = 'track';
        }
        await SearchHistory.addQuery(q, filterType: filterType);
      }

      setState(() {
        _hasSearched = true; // Mark that a search was performed
        if (isLoadMore) {
          _searchResults.addAll(items);
        } else {
          _searchResults
            ..clear()
            ..addAll(items);
          _libraryResults
            ..clear()
            ..addAll(libraryItems);
        }

        // Update pagination state
        _currentOffset += items.length;
        _hasMore =
            items.length ==
            _pageSize; // If we got fewer than requested, no more results
        debugPrint(
          'LibraryPage: Got ${items.length} items, hasMore=$_hasMore, offset=$_currentOffset',
        );
      });
    } catch (e) {
      if (!mounted) return;
      // Snackbar removed - error logged to console
      debugPrint('Search failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    // Don't load more if offline - there's no pagination for local results
    if (_isOffline) return;
    if (!_hasMore || _loadingMore || _currentQuery.isEmpty) return;
    debugPrint(
      'LibraryPage: Loading more results for "$_currentQuery" at offset $_currentOffset',
    );
    await _doSearch(_currentQuery, true);
  }

  void _onFilterChanged() {
    // If we have search results, re-trigger search with new filter
    if (_searchResults.isNotEmpty && _currentQuery.isNotEmpty) {
      _doSearch(_currentQuery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          GestureDetector(
            onTap: _openSearch,
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.primary, width: 2),
                color: Colors.transparent,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _searchActive
                        ? TextField(
                            focusNode: _searchFocus,
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _doSearch(),
                            onChanged: (_) {
                              // Trigger rebuild to update search history filtering
                              setState(() {
                                // Clear results when typing to show history
                                _searchResults.clear();
                                _hasSearched = false;
                              });
                            },
                          )
                        : Text(
                            'Search',
                            style: TextStyle(
                              color: theme.hintColor,
                              fontSize: 18,
                            ),
                          ),
                  ),
                  if (_searchActive) ...[
                    GestureDetector(
                      onTap: _closeSearch,
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.close, color: cs.primary),
                      ),
                    ),
                    const SizedBox(width: 0),
                  ],
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.search, color: cs.onPrimary),
                      onPressed: _searchActive ? _doSearch : _openSearch,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Replace the rest of the page with the search UX when active
          if (_searchActive)
            Expanded(
              child: ui_search.SearchResultsWidget(
                results: _searchResults,
                libraryResults: _libraryResults,
                loading: _loading,
                loadingMore: _loadingMore,
                currentQuery: _searchCtrl.text,
                onHistoryTap: (item) {
                  // Restore filter conditions from history
                  setState(() {
                    _artistFilterActive = item.filterType == 'artist';
                    _albumFilterActive = item.filterType == 'album';
                    _trackFilterActive = item.filterType == 'track';
                  });
                  _doSearch(item.query);
                },
                onLoadMore: _loadMore,
                artistFilterActive: _artistFilterActive,
                albumFilterActive: _albumFilterActive,
                trackFilterActive: _trackFilterActive,
                onArtistFilterChanged: (value) {
                  setState(() {
                    _artistFilterActive = value;
                    if (value) {
                      // Turn off other filters when this one is turned on
                      _albumFilterActive = false;
                      _trackFilterActive = false;
                    }
                  });
                  _onFilterChanged();
                },
                onAlbumFilterChanged: (value) {
                  setState(() {
                    _albumFilterActive = value;
                    if (value) {
                      // Turn off other filters when this one is turned on
                      _artistFilterActive = false;
                      _trackFilterActive = false;
                    }
                  });
                  _onFilterChanged();
                },
                onTrackFilterChanged: (value) {
                  setState(() {
                    _trackFilterActive = value;
                    if (value) {
                      // Turn off other filters when this one is turned on
                      _artistFilterActive = false;
                      _albumFilterActive = false;
                    }
                  });
                  _onFilterChanged();
                },
                isOffline: _isOffline,
                hasSearched: _hasSearched,
              ),
            )
          else
            // Library content when not searching
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recently Played Section (fixed, doesn't scroll with pages)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      'Recently Played',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  RecentWheel(),

                  const SizedBox(height: 32),

                  // Library Section Selector (synced with PageView)
                  LibrarySectionSelector(
                    initialSection: _currentSection,
                    currentSection: _currentSection,
                    onSectionChanged: (section) {
                      final index = LibrarySection.values.indexOf(section);
                      _sectionPageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                      setState(() {
                        _currentSection = section;
                      });
                    },
                  ),

                  // Swipeable section content
                  Expanded(
                    child: PageView(
                      controller: _sectionPageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentSection = LibrarySection.values[index];
                        });
                      },
                      children: [
                        // AllSongs
                        const SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: AllSongsList(),
                          ),
                        ),
                        // Playlists
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: PlaylistsList(
                              key: _playlistsListKey,
                              onPlaylistTap: _onPlaylistTap,
                            ),
                          ),
                        ),
                        // Artists
                        const SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: ArtistsList(),
                          ),
                        ),
                        // Albums
                        const SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: AlbumsList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _onPlaylistTap(String playlistId, String playlistName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => PlaylistBottomSheet(
        playlistId: playlistId,
        playlistName: playlistName,
      ),
    ).then((_) {
      // Refresh playlists when bottom sheet is closed
      _refreshPlaylists();
    });
  }
}
