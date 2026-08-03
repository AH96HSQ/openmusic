import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;
  AuthService._internal();

  late final String _baseUrl;
  Map<String, dynamic>? _currentUser;

  // Storage keys
  static const String _keyUserId = 'auth_user_id';
  static const String _keyUserEmail = 'auth_user_email';
  static const String _keyUserCreatedAt = 'auth_user_created_at';

  /// Get current logged in user
  Map<String, dynamic>? get currentUser => _currentUser;

  /// Check if user is logged in
  bool get isLoggedIn => _currentUser != null;

  Future<void> init() async {
    final envBase = dotenv.env['BACKEND_BASE_URL']?.trim();
    _baseUrl = envBase?.isNotEmpty == true
        ? envBase!.replaceAll(RegExp(r'/+$'), '')
        : 'http://localhost:5002';

    // Load saved user on init
    await _loadSavedUser();
  }

  /// Load saved user from SharedPreferences
  Future<void> _loadSavedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_keyUserId);
      final userEmail = prefs.getString(_keyUserEmail);
      final userCreatedAt = prefs.getString(_keyUserCreatedAt);

      if (userId != null && userEmail != null) {
        _currentUser = {
          'id': userId,
          'email': userEmail,
          'createdAt': userCreatedAt,
        };
      }
    } catch (e) {
      // Ignore errors loading saved user
      _currentUser = null;
    }
  }

  /// Save user to SharedPreferences
  Future<void> _saveUser(Map<String, dynamic> user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserId, user['id'] ?? '');
      await prefs.setString(_keyUserEmail, user['email'] ?? '');
      await prefs.setString(_keyUserCreatedAt, user['createdAt'] ?? '');
      _currentUser = user;
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Clear saved user
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUserId);
      await prefs.remove(_keyUserEmail);
      await prefs.remove(_keyUserCreatedAt);
      _currentUser = null;
    } catch (e) {
      // Ignore errors
      _currentUser = null;
    }
  }

  /// Check if email exists in the database
  /// Returns: {exists: bool, requiresPassword: bool, requiresOtp: bool}
  Future<Map<String, dynamic>> checkEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/v1/auth/check-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to check email');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Request OTP to be sent to email
  /// Returns: {success: bool, message: String, expiresIn: int}
  Future<Map<String, dynamic>> requestOTP(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/v1/email/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Verify OTP code
  /// Returns: {success: bool, verified: bool}
  Future<Map<String, dynamic>> verifyOTP(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to verify OTP');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Login with email and password
  /// Returns: {success: bool, user: {id, email, createdAt}}
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        // Save user to persistent storage
        if (result['success'] == true && result['user'] != null) {
          await _saveUser(result['user']);
        }
        return result;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to login');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Create new account with email and password
  /// Returns: {success: bool, user: {id, email, createdAt}}
  Future<Map<String, dynamic>> createAccount(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/v1/auth/create-account'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        // Save user to persistent storage
        if (result['success'] == true && result['user'] != null) {
          await _saveUser(result['user']);
        }
        return result;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to create account');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Reset password for an existing user
  /// Returns: {success: bool, message: String}
  Future<Map<String, dynamic>> resetPassword(
    String email,
    String newPassword,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/v1/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'newPassword': newPassword}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to reset password');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
