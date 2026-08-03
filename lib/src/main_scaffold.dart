import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/pages/now_playing.dart';
import 'pages/library_page.dart';
import 'pages/recommendations_page.dart';
import 'pages/more_page.dart';
import 'theme/theme_controller.dart';
import 'services/status_message_controller.dart';

/// Check if running on desktop platform
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class MainScaffold extends StatefulWidget {
  const MainScaffold({
    super.key,
    this.themeController,
    this.openSearchOnStart = false,
  });

  final ThemeController? themeController;
  final bool openSearchOnStart;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  // For mobile: 0=NowPlaying, 1=Library, 2=Recommendations, 3=More
  // For desktop: 0=Library, 1=Recommendations, 2=More (NowPlaying is always visible)
  int _selectedIndex = 0;
  DateTime? _lastBackPress;
  final _libraryPageKey = GlobalKey<LibraryPageState>();
  bool _hasOpenedSearchOnStart = false;

  // Mobile pages (includes NowPlaying)
  late final List<Widget> _mobilePages = <Widget>[
    NowPlayingPage(songId: '', onNavigateToLibrary: () => _onItemTapped(1)),
    LibraryPage(key: _libraryPageKey),
    const RecommendationsPage(),
    MorePage(themeController: widget.themeController),
  ];

  // Desktop pages (NowPlaying is separate, always visible)
  late final List<Widget> _desktopPages = <Widget>[
    LibraryPage(key: _libraryPageKey),
    const RecommendationsPage(),
    MorePage(themeController: widget.themeController),
  ];

  @override
  void initState() {
    super.initState();
    // If first launch, start on Library page and open search
    if (widget.openSearchOnStart) {
      _selectedIndex = isDesktopPlatform
          ? 0
          : 1; // Library page (index differs by platform)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openSearchOnStart();
      });
    }
  }

  void _openSearchOnStart() {
    if (_hasOpenedSearchOnStart) return;
    _hasOpenedSearchOnStart = true;

    final libraryState = _libraryPageKey.currentState;
    if (libraryState != null) {
      libraryState.openSearch();
    }
  }

  void _onItemTapped(int index) {
    // Handle Library page search closing
    final libraryIndex = isDesktopPlatform ? 0 : 1;
    if (_selectedIndex == libraryIndex) {
      final libraryState = _libraryPageKey.currentState;
      if (libraryState != null && libraryState.isSearchActive) {
        libraryState.closeSearch();
        // If user clicked Library button again, don't change index
        if (index == libraryIndex) {
          return;
        }
      }
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return _buildDesktopLayout(context);
    } else {
      return _buildMobileLayout(context);
    }
  }

  /// Desktop layout: NowPlaying on left side (fixed aspect ratio), content on right with NavigationRail
  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Row(
        children: [
          // Now Playing panel on the left - fixed width with aspect ratio
          SizedBox(
            width: 400, // Fixed width for Now Playing panel
            child: NowPlayingPage(
              songId: '',
              onNavigateToLibrary: () => _onItemTapped(0),
            ),
          ),
          // Divider between Now Playing and content
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
          // Navigation Rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            backgroundColor: scaffoldBg,
            indicatorColor: primaryColor.withValues(alpha: 0.2),
            selectedIconTheme: IconThemeData(color: primaryColor, size: 28),
            unselectedIconTheme: IconThemeData(
              color:
                  theme.iconTheme.color?.withValues(alpha: 0.7) ??
                  Colors.white70,
              size: 28,
            ),
            labelType: NavigationRailLabelType.selected,
            selectedLabelTextStyle: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            unselectedLabelTextStyle: TextStyle(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              fontSize: 12,
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: Text('Discover'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more_horiz),
                label: Text('More'),
              ),
            ],
          ),
          // Another divider after NavigationRail
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
          // Main content area
          Expanded(child: _desktopPages[_selectedIndex]),
        ],
      ),
    );
  }

  /// Mobile layout: Traditional BottomNavigationBar with all 4 tabs
  Widget _buildMobileLayout(BuildContext context) {
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final primaryColor = theme.colorScheme.primary;

    // compute a nav background that is a bit lighter (for dark) or slightly
    // darker (for light) than the scaffold background to create a subtle bar.
    final navBg = theme.brightness == Brightness.dark
        ? Color.lerp(scaffoldBg, Colors.white, 0.06)!
        : Color.lerp(
            scaffoldBg,
            Colors.black,
            0.15,
          )!; // Increased from 0.02 to 0.15 for much darker nav bar

    final bottomNavBar = Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        elevation: 0,
        backgroundColor: navBg,
        selectedItemColor: primaryColor,
        unselectedItemColor:
            theme.iconTheme.color?.withAlpha((0.7 * 255).round()) ??
            Colors.white70,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        selectedIconTheme: const IconThemeData(size: 34),
        unselectedIconTheme: const IconThemeData(size: 34),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle_fill),
            label: 'Now Playing',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: 'Recommendations',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        // If on Library page (index 1), let it handle search closing first
        if (_selectedIndex == 1) {
          final libraryState = _libraryPageKey.currentState;
          if (libraryState != null && libraryState.isSearchActive) {
            libraryState.closeSearch();
            return;
          }
        }

        // If not on Now Playing (index 0), navigate to Now Playing
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return;
        }

        // On Now Playing tab - double back to exit
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          StatusMessageController.instance.showMessage(
            'Press back again to exit',
            duration: const Duration(milliseconds: 1800),
          );
          return;
        }

        // Exit app on second back press within 2 seconds
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: scaffoldBg,
        body: SafeArea(child: _mobilePages[_selectedIndex]),
        bottomNavigationBar: bottomNavBar,
      ),
    );
  }
}
