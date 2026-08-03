import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Download method identifiers
enum DownloadMethodId {
  sra, // SRA - Spotify RapidAPI
  dsra, // DSRA - Deezer & Spotify RapidAPI
  smp, // SMP - SpotiMP3
}

/// Service to manage download method settings
class DownloadSettingsService extends ChangeNotifier {
  static final DownloadSettingsService instance =
      DownloadSettingsService._internal();
  DownloadSettingsService._internal();

  static const String _methodOrderKey = 'download_method_order';

  /// Default order: SRA, DSRA, SMP
  static const List<DownloadMethodId> defaultOrder = [
    DownloadMethodId.sra,
    DownloadMethodId.dsra,
    DownloadMethodId.smp,
  ];

  List<DownloadMethodId> _methodOrder = List.from(defaultOrder);

  /// Get current method order
  List<DownloadMethodId> get methodOrder => List.unmodifiable(_methodOrder);

  /// Get method display name
  static String getMethodName(DownloadMethodId method) {
    switch (method) {
      case DownloadMethodId.sra:
        return 'SRA';
      case DownloadMethodId.dsra:
        return 'DSRA';
      case DownloadMethodId.smp:
        return 'SMP';
    }
  }

  /// Get method full name/description
  static String getMethodDescription(DownloadMethodId method) {
    switch (method) {
      case DownloadMethodId.sra:
        return 'Spotify RapidAPI';
      case DownloadMethodId.dsra:
        return 'Deezer & Spotify RapidAPI';
      case DownloadMethodId.smp:
        return 'SpotiMP3';
    }
  }

  /// Convert method ID to service constant
  static int toServiceMethod(DownloadMethodId method) {
    switch (method) {
      case DownloadMethodId.sra:
        return 1; // SpotifyDownloadService.methodRapidApi
      case DownloadMethodId.dsra:
        return 2; // SpotifyDownloadService.methodDsRapidApi
      case DownloadMethodId.smp:
        return 3; // SpotifyDownloadService.methodSpotiMp3
    }
  }

  /// Convert service constant to method ID
  static DownloadMethodId? fromServiceMethod(int method) {
    switch (method) {
      case 1:
        return DownloadMethodId.sra;
      case 2:
        return DownloadMethodId.dsra;
      case 3:
        return DownloadMethodId.smp;
      default:
        return null;
    }
  }

  /// Initialize the service and load saved order
  Future<void> init() async {
    await _loadMethodOrder();
  }

  /// Load method order from SharedPreferences
  Future<void> _loadMethodOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList(_methodOrderKey);

      if (savedOrder != null && savedOrder.length == 3) {
        final parsedOrder = <DownloadMethodId>[];
        for (final name in savedOrder) {
          final method = DownloadMethodId.values.firstWhere(
            (m) => m.name == name,
            orElse: () => DownloadMethodId.sra,
          );
          if (!parsedOrder.contains(method)) {
            parsedOrder.add(method);
          }
        }

        // Ensure all methods are present
        if (parsedOrder.length == 3) {
          _methodOrder = parsedOrder;
        }
      }
    } catch (e) {
      debugPrint('DownloadSettingsService: Error loading method order: $e');
    }
  }

  /// Save method order to SharedPreferences
  Future<void> _saveMethodOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _methodOrderKey,
        _methodOrder.map((m) => m.name).toList(),
      );
    } catch (e) {
      debugPrint('DownloadSettingsService: Error saving method order: $e');
    }
  }

  /// Update the method order
  Future<void> setMethodOrder(List<DownloadMethodId> newOrder) async {
    if (newOrder.length != 3) return;

    // Validate all methods are present
    final allPresent = DownloadMethodId.values.every(
      (m) => newOrder.contains(m),
    );
    if (!allPresent) return;

    _methodOrder = List.from(newOrder);
    await _saveMethodOrder();
    notifyListeners();
  }

  /// Reorder a method from one index to another
  Future<void> reorderMethod(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= 3 || newIndex < 0 || newIndex >= 3) return;
    if (oldIndex == newIndex) return;

    final method = _methodOrder.removeAt(oldIndex);
    _methodOrder.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, method);
    await _saveMethodOrder();
    notifyListeners();
  }

  /// Reset to default order
  Future<void> resetToDefault() async {
    _methodOrder = List.from(defaultOrder);
    await _saveMethodOrder();
    notifyListeners();
  }
}
