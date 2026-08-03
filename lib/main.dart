import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/main_scaffold.dart';
import 'src/theme/theme_controller.dart';
import 'src/services/simple_playback_controller.dart';
import 'src/services/playlists_service.dart';
import 'src/services/status_message_controller.dart';
import 'src/services/system_service.dart';
import 'src/services/auth_service.dart';
import 'src/services/sync_service.dart';
import 'src/services/crypto_payment_service.dart';
import 'src/services/album_art_helper.dart';
import 'src/widgets/animated_status_capsule.dart';
import 'src/services/audio_handler_service.dart';
import 'src/services/notification_permission_helper.dart';
import 'src/ui/pages/welcome_page.dart';
import 'src/ui/pages/splash_screen.dart';
import 'src/services/spotify_client.dart';
import 'src/services/download_credentials_service.dart';
import 'src/services/download_settings_service.dart';
import 'src/data/database_helper.dart';

/// Check if running on a mobile platform (Android/iOS)
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

/// Check if running on a desktop platform (Windows/macOS/Linux)
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database factory for desktop platforms (Windows/Linux use FFI)
  initDatabaseFactory();

  // Load environment variables from .env before anything else so widgets
  // can read dotenv.env in their initState safely.
  await dotenv.load(fileName: '.env');
  // Initialize Spotify client for on-device search
  await SpotifyClient.instance.init();
  // Initialize download credentials for on-device downloading
  await DownloadCredentialsService.instance.init();
  // Initialize download settings (method order)
  await DownloadSettingsService.instance.init();
  // Initialize services
  SystemService.instance.init();
  await AuthService.instance.init();
  await SyncService.instance.init();
  await CryptoPaymentService.instance.init();

  // Sync is now event-based (on app background/foreground) - no periodic timer needed

  await SimplePlaybackController.instance.init();

  // Initialize audio service only on mobile platforms (Android/iOS)
  // Desktop platforms don't have native media notification integration
  if (isMobilePlatform) {
    debugPrint('Main: calling initAudioService at startup');
    await initAudioService();
  } else {
    debugPrint('Main: Skipping audio service on desktop platform');
  }

  // Ensure default playlists exist
  await PlaylistsService.ensureDefaultPlaylistsExist();
  final themeController = await ThemeController.load();
  runApp(MyApp(themeController: themeController));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final ThemeController _themeController;
  bool _isFirstLaunch = false;
  bool _checkingFirstLaunch = true;
  bool _justCompletedFirstLaunch =
      false; // Track if user just completed welcome
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _themeController = widget.themeController;
    WidgetsBinding.instance.addObserver(this);
    _checkFirstLaunch();
    _setupDeepLinkListener();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Ensure notifications permission on Android 13+ so media notification is visible
        await NotificationPermissionHelper.requestNotificationsIfNeeded();
      } catch (e) {
        debugPrint('Deferred permission request failed: $e');
      }
      // Check for initial link (app launched via deep link)
      _checkInitialLink();

      // Download missing album artwork in background for existing songs
      // This runs asynchronously and doesn't block app startup
      try {
        AlbumArtHelper.instance.downloadAllMissingArtwork();
      } catch (e) {
        debugPrint('Background artwork download failed: $e');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Save current play time before app goes to background
      SimplePlaybackController.instance.saveCurrentPlayTime();
      // Sync data when app goes to background (event-based, no timer)
      if (AuthService.instance.isLoggedIn) {
        SyncService.instance.syncData();
      }
      debugPrint('App paused: Saved play time and synced data');
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed');
    }
  }

  void _setupDeepLinkListener() {
    // Deep links are only supported on mobile platforms
    if (!isMobilePlatform) return;

    // Listen for incoming deep links while app is running
    const platform = MethodChannel('openmusic/deeplink');
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final uri = Uri.parse(call.arguments as String);
        _handleDeepLink(uri);
      }
    });
  }

  Future<void> _checkInitialLink() async {
    // Deep links are only supported on mobile platforms
    if (!isMobilePlatform) return;

    try {
      // Check if app was launched with a deep link
      const platform = MethodChannel('openmusic/deeplink');
      final String? initialLink = await platform.invokeMethod('getInitialLink');
      if (initialLink != null && initialLink.isNotEmpty) {
        final uri = Uri.parse(initialLink);
        _handleDeepLink(uri);
      }
    } catch (e) {
      debugPrint('Error checking initial link: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Handling deep link: $uri');
    debugPrint(
      'Deep link scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}',
    );

    // Deep link handling can be added here if needed in the future
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunchedBefore = prefs.getBool('has_launched_before') ?? false;

    setState(() {
      _isFirstLaunch = !hasLaunchedBefore;
      _checkingFirstLaunch = false;
    });

    if (_isFirstLaunch) {
      debugPrint('First launch detected');
    }
  }

  Future<void> _handleGetStarted() async {
    // Mark as launched
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_launched_before', true);

    // Close welcome page and navigate to main app with search open
    setState(() {
      _isFirstLaunch = false;
      _justCompletedFirstLaunch = true; // Signal to open search on Library page
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) {
        final seed = _themeController.seedColor;
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'OpenMusic',
          themeMode: _themeController.mode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            // Build a color scheme from seed but enforce the primary to be the exact seed color
            colorScheme: () {
              final cs = ColorScheme.fromSeed(seedColor: seed);
              return cs.copyWith(
                primary: seed,
                onPrimary: seed.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              );
            }(),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              selectedItemColor: seed,
              unselectedItemColor: ColorScheme.fromSeed(
                seedColor: seed,
              ).onSurface.withAlpha((0.60 * 255).round()),
              // Make navigation bar much darker in light mode - use a gray tone
              backgroundColor: Colors.grey[300],
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: ColorScheme.fromSeed(seedColor: seed).onSurface,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: () {
              final cs = ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              );
              return cs.copyWith(
                primary: seed,
                onPrimary: seed.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
                surface: const Color(0xFF121212),
                onSurface: Colors.white,
              );
            }(),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              selectedItemColor: seed,
              unselectedItemColor: ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              ).onSurface.withAlpha((0.60 * 255).round()),
              backgroundColor: ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              ).surface,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              ).onSurface,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          home: _checkingFirstLaunch
              ? const SplashScreen()
              : _isFirstLaunch
              ? WelcomePage(onGetStarted: _handleGetStarted)
              : MainScaffold(
                  themeController: _themeController,
                  openSearchOnStart: _justCompletedFirstLaunch,
                ),
          builder: (context, child) {
            return Stack(
              children: [
                child!,
                // Global status message overlay - positioned just above the navigation bar
                Positioned(
                  bottom:
                      65, // Position above the navigation bar with some extra margin
                  left: 0,
                  right: 0,
                  child: ListenableBuilder(
                    listenable: StatusMessageController.instance,
                    builder: (context, child) {
                      return AnimatedStatusCapsule(
                        message:
                            StatusMessageController.instance.currentMessage,
                        backgroundColor:
                            Theme.of(
                              context,
                            ).bottomNavigationBarTheme.backgroundColor ??
                            Theme.of(context).colorScheme.surface,
                        textColor: Theme.of(context).colorScheme.primary,
                        bottomPadding: 8,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
