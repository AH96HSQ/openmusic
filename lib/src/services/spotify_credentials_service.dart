import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service to manage Spotify API credentials
/// Uses default credentials bundled with the app, but can be updated from backend
class SpotifyCredentialsService {
  static final SpotifyCredentialsService instance =
      SpotifyCredentialsService._internal();
  SpotifyCredentialsService._internal();

  // Default credentials bundled with the app
  static const String _defaultClientId = '497154c0fc1d49b48a1714216a59c967';
  static const String _defaultClientSecret = '9282009e8a1044cfafb54ddd94ff8eb5';

  // Persistence keys
  static const String _keyClientId = 'spotify_client_id';
  static const String _keyClientSecret = 'spotify_client_secret';
  static const String _keyLastUpdate = 'spotify_creds_last_update';

  String? _cachedClientId;
  String? _cachedClientSecret;
  bool _initialized = false;

  /// Get the current client ID
  String get clientId => _cachedClientId ?? _defaultClientId;

  /// Get the current client secret
  String get clientSecret => _cachedClientSecret ?? _defaultClientSecret;

  /// Initialize the service and load cached credentials
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedClientId = prefs.getString(_keyClientId);
      _cachedClientSecret = prefs.getString(_keyClientSecret);

      debugPrint(
        'SpotifyCredentialsService: Loaded credentials - '
        'clientId: ${_cachedClientId != null ? "custom" : "default"}, '
        'clientSecret: ${_cachedClientSecret != null ? "custom" : "default"}',
      );

      _initialized = true;

      // Check for updates from backend in background
      _checkForUpdates();
    } catch (e) {
      debugPrint('SpotifyCredentialsService: Error loading credentials: $e');
      _initialized = true;
    }
  }

  /// Check backend for updated credentials
  Future<void> _checkForUpdates() async {
    try {
      final baseUrl = dotenv.env['BACKEND_BASE_URL'] ?? '';
      if (baseUrl.isEmpty) {
        debugPrint('SpotifyCredentialsService: No backend URL configured');
        return;
      }

      final url = '$baseUrl/v1/config/spotify-credentials';
      debugPrint(
        'SpotifyCredentialsService: Checking for credential updates at $url',
      );

      final response = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newClientId = data['clientId'] as String?;
        final newClientSecret = data['clientSecret'] as String?;

        if (newClientId != null && newClientSecret != null) {
          await updateCredentials(newClientId, newClientSecret);
          debugPrint(
            'SpotifyCredentialsService: Updated credentials from backend',
          );
        }
      } else if (response.statusCode == 404) {
        // Endpoint doesn't exist yet, use defaults
        debugPrint(
          'SpotifyCredentialsService: No custom credentials from backend (404)',
        );
      } else {
        debugPrint(
          'SpotifyCredentialsService: Backend returned ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('SpotifyCredentialsService: Error checking for updates: $e');
      // Silently fail - will use cached or default credentials
    }
  }

  /// Update credentials from backend
  Future<void> updateCredentials(String clientId, String clientSecret) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyClientId, clientId);
      await prefs.setString(_keyClientSecret, clientSecret);
      await prefs.setInt(_keyLastUpdate, DateTime.now().millisecondsSinceEpoch);

      _cachedClientId = clientId;
      _cachedClientSecret = clientSecret;

      debugPrint('SpotifyCredentialsService: Credentials updated successfully');
    } catch (e) {
      debugPrint('SpotifyCredentialsService: Error updating credentials: $e');
    }
  }

  /// Reset to default credentials
  Future<void> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyClientId);
      await prefs.remove(_keyClientSecret);
      await prefs.remove(_keyLastUpdate);

      _cachedClientId = null;
      _cachedClientSecret = null;

      debugPrint('SpotifyCredentialsService: Reset to default credentials');
    } catch (e) {
      debugPrint('SpotifyCredentialsService: Error resetting credentials: $e');
    }
  }

  /// Force refresh credentials from backend
  Future<void> refreshFromBackend() async {
    await _checkForUpdates();
  }
}
