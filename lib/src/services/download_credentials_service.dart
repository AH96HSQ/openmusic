import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'spotify_download_service.dart';

/// Service to manage download API credentials
/// Uses default credentials bundled with the app, but can be updated from backend
class DownloadCredentialsService {
  static final DownloadCredentialsService instance =
      DownloadCredentialsService._internal();
  DownloadCredentialsService._internal();

  // Default credentials bundled with the app
  static const String _defaultRapidApiKey =
      '353911e03dmshfc92380284fba44p164b70jsnba7769ba4608';
  static const String _defaultDsRapidApiKey =
      '353911e03dmshfc92380284fba44p164b70jsnba7769ba4608';

  // Persistence keys
  static const String _keyRapidApiKey = 'download_rapidapi_key';
  static const String _keyDsRapidApiKey = 'download_ds_rapidapi_key';
  static const String _keyLastUpdate = 'download_creds_last_update';

  String? _cachedRapidApiKey;
  String? _cachedDsRapidApiKey;
  bool _initialized = false;

  /// Get the current RapidAPI key
  String get rapidApiKey => _cachedRapidApiKey ?? _defaultRapidApiKey;

  /// Get the current DS RapidAPI key
  String get dsRapidApiKey => _cachedDsRapidApiKey ?? _defaultDsRapidApiKey;

  /// Initialize the service and load cached credentials
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedRapidApiKey = prefs.getString(_keyRapidApiKey);
      _cachedDsRapidApiKey = prefs.getString(_keyDsRapidApiKey);

      debugPrint(
        'DownloadCredentialsService: Loaded credentials - '
        'rapidApiKey: ${_cachedRapidApiKey != null ? "custom" : "default"}, '
        'dsRapidApiKey: ${_cachedDsRapidApiKey != null ? "custom" : "default"}',
      );

      _initialized = true;

      // Update the download service with current keys
      _updateDownloadService();

      // Check for updates from backend in background
      _checkForUpdates();
    } catch (e) {
      debugPrint('DownloadCredentialsService: Error loading credentials: $e');
      _initialized = true;
    }
  }

  /// Update the SpotifyDownloadService with current credentials
  void _updateDownloadService() {
    SpotifyDownloadService.instance.updateApiKeys(
      rapidApiKey: rapidApiKey,
      dsRapidApiKey: dsRapidApiKey,
    );
  }

  /// Check backend for updated credentials
  Future<void> _checkForUpdates() async {
    try {
      final baseUrl = dotenv.env['BACKEND_BASE_URL'] ?? '';
      if (baseUrl.isEmpty) {
        debugPrint('DownloadCredentialsService: No backend URL configured');
        return;
      }

      final url = '$baseUrl/v1/config/download-credentials';
      debugPrint(
        'DownloadCredentialsService: Checking for credential updates at $url',
      );

      final response = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newRapidApiKey = data['rapidApiKey'] as String?;
        final newDsRapidApiKey = data['dsRapidApiKey'] as String?;

        if (newRapidApiKey != null || newDsRapidApiKey != null) {
          await updateCredentials(
            rapidApiKey: newRapidApiKey,
            dsRapidApiKey: newDsRapidApiKey,
          );
          debugPrint(
            'DownloadCredentialsService: Updated credentials from backend',
          );
        }
      } else if (response.statusCode == 404) {
        // Endpoint doesn't exist yet or no custom creds, use defaults
        debugPrint(
          'DownloadCredentialsService: No custom credentials from backend (404)',
        );
      } else {
        debugPrint(
          'DownloadCredentialsService: Backend returned ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('DownloadCredentialsService: Error checking for updates: $e');
      // Silently fail - will use cached or default credentials
    }
  }

  /// Update credentials from backend
  Future<void> updateCredentials({
    String? rapidApiKey,
    String? dsRapidApiKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (rapidApiKey != null) {
        await prefs.setString(_keyRapidApiKey, rapidApiKey);
        _cachedRapidApiKey = rapidApiKey;
      }

      if (dsRapidApiKey != null) {
        await prefs.setString(_keyDsRapidApiKey, dsRapidApiKey);
        _cachedDsRapidApiKey = dsRapidApiKey;
      }

      await prefs.setInt(_keyLastUpdate, DateTime.now().millisecondsSinceEpoch);

      // Update the download service
      _updateDownloadService();

      debugPrint(
        'DownloadCredentialsService: Credentials updated successfully',
      );
    } catch (e) {
      debugPrint('DownloadCredentialsService: Error updating credentials: $e');
    }
  }

  /// Reset to default credentials
  Future<void> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyRapidApiKey);
      await prefs.remove(_keyDsRapidApiKey);
      await prefs.remove(_keyLastUpdate);

      _cachedRapidApiKey = null;
      _cachedDsRapidApiKey = null;

      // Update the download service with defaults
      _updateDownloadService();

      debugPrint('DownloadCredentialsService: Reset to default credentials');
    } catch (e) {
      debugPrint('DownloadCredentialsService: Error resetting credentials: $e');
    }
  }

  /// Force refresh credentials from backend
  Future<void> refreshFromBackend() async {
    await _checkForUpdates();
  }
}
