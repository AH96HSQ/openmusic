import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class SystemService {
  static final SystemService _instance = SystemService._internal();
  static SystemService get instance => _instance;
  SystemService._internal();

  late final String _baseUrl;

  void init() {
    final envBase = dotenv.env['BACKEND_BASE_URL']?.trim();
    _baseUrl = envBase?.isNotEmpty == true
        ? envBase!.replaceAll(RegExp(r'/+$'), '')
        : 'http://localhost:5002';
    debugPrint('SystemService: Base URL = $_baseUrl');
  }

  /// Get donation information including progress and payment details
  Future<DonationInfo?> getDonationInfo() async {
    try {
      final url = '$_baseUrl/v1/system/donation';
      debugPrint('SystemService: Fetching donation info from $url');

      final response = await http.get(Uri.parse(url));
      debugPrint('SystemService: Donation response ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['donation'] != null) {
          return DonationInfo.fromJson(data['donation']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('SystemService: Error fetching donation info: $e');
      return null;
    }
  }

  /// Get system performance metrics
  Future<SystemPerformance?> getSystemPerformance() async {
    try {
      final url = '$_baseUrl/v1/system/info/formatted';
      debugPrint('SystemService: Fetching system performance from $url');

      final response = await http.get(Uri.parse(url));
      debugPrint(
        'SystemService: System performance response ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['system'] != null) {
          return SystemPerformance.fromJson(data['system']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('SystemService: Error fetching system performance: $e');
      return null;
    }
  }

  /// Check if user is online by pinging Spotify (reliable external service)
  Future<bool> isOnline() async {
    try {
      final response = await http
          .get(
            Uri.parse('https://api.spotify.com/v1'),
            headers: {
              'Authorization': 'Bearer invalid',
            }, // We expect 401, not timeout
          )
          .timeout(const Duration(seconds: 5));

      // If we get any response (even 401), user is online
      return response.statusCode == 401;
    } catch (e) {
      return false;
    }
  }

  /// Check server status: Live/Down/User Offline
  Future<ServerStatus> getServerStatus() async {
    try {
      // First check if server is reachable
      final url = '$_baseUrl/health';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ServerStatus.live;
      } else {
        // Server responded but with error
        return ServerStatus.down;
      }
    } catch (e) {
      // Server not reachable, check if user is online
      final online = await isOnline();
      return online ? ServerStatus.down : ServerStatus.offline;
    }
  }

  /// Get latest version information from server
  static Future<Map<String, dynamic>> getVersion() async {
    try {
      final envBase = dotenv.env['BACKEND_BASE_URL']?.trim();
      final baseUrl = envBase?.isNotEmpty == true
          ? envBase!.replaceAll(RegExp(r'/+$'), '')
          : 'http://localhost:5002';

      final url = '$baseUrl/v1/system/version';
      debugPrint('SystemService: Checking version from $url');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['version'] != null) {
          debugPrint(
            'SystemService: Latest version: ${data['version']['latest']}',
          );
          return data['version'];
        }
      }
      return {'latest': '0.1.0'};
    } catch (e) {
      debugPrint('SystemService: Error checking version: $e');
      return {'latest': '0.1.0'};
    }
  }
}

class DonationInfo {
  final int monthlyGoal;
  final int collected;
  final double progress;
  final String iranCardNumber;
  final String skrillEmail;
  final CryptoAddresses crypto;

  DonationInfo({
    required this.monthlyGoal,
    required this.collected,
    required this.progress,
    required this.iranCardNumber,
    required this.skrillEmail,
    required this.crypto,
  });

  factory DonationInfo.fromJson(Map<String, dynamic> json) {
    return DonationInfo(
      monthlyGoal: json['monthlyGoal'] ?? 100,
      collected: json['collected'] ?? 0,
      progress: (json['progress'] ?? 0.0).toDouble(),
      iranCardNumber: json['iranCardNumber'] ?? '',
      skrillEmail: json['skrillEmail'] ?? '',
      crypto: CryptoAddresses.fromJson(json['crypto'] ?? {}),
    );
  }
}

class CryptoAddresses {
  final String btc;
  final String eth;
  final String ltc;
  final String usdtTron;
  final String usdtEth;
  final String usdcEth;

  CryptoAddresses({
    required this.btc,
    required this.eth,
    required this.ltc,
    required this.usdtTron,
    required this.usdtEth,
    required this.usdcEth,
  });

  factory CryptoAddresses.fromJson(Map<String, dynamic> json) {
    return CryptoAddresses(
      btc: json['btc'] ?? '',
      eth: json['eth'] ?? '',
      ltc: json['ltc'] ?? '',
      usdtTron: json['usdtTron'] ?? '',
      usdtEth: json['usdtEth'] ?? '',
      usdcEth: json['usdcEth'] ?? '',
    );
  }
}

class SystemPerformance {
  final MemoryInfo memory;
  final CpuInfo cpu;
  final StorageInfo storage;
  final DatabaseInfo database;

  SystemPerformance({
    required this.memory,
    required this.cpu,
    required this.storage,
    required this.database,
  });

  factory SystemPerformance.fromJson(Map<String, dynamic> json) {
    return SystemPerformance(
      memory: MemoryInfo.fromJson(json['memory'] ?? {}),
      cpu: CpuInfo.fromJson(json['cpu'] ?? {}),
      storage: StorageInfo.fromJson(json['storage'] ?? {}),
      database: DatabaseInfo.fromJson(json['database'] ?? {}),
    );
  }
}

class MemoryInfo {
  final String total;
  final String used;
  final String free;
  final String usagePercent;

  MemoryInfo({
    required this.total,
    required this.used,
    required this.free,
    required this.usagePercent,
  });

  factory MemoryInfo.fromJson(Map<String, dynamic> json) {
    return MemoryInfo(
      total: json['total'] ?? '0 B',
      used: json['used'] ?? '0 B',
      free: json['free'] ?? '0 B',
      usagePercent: json['usagePercent'] ?? '0%',
    );
  }

  double get usagePercentValue {
    final match = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(usagePercent);
    return match != null ? double.tryParse(match.group(1)!) ?? 0.0 : 0.0;
  }
}

class CpuInfo {
  final String model;
  final int cores;
  final String speed;
  final String currentUsage;

  CpuInfo({
    required this.model,
    required this.cores,
    required this.speed,
    required this.currentUsage,
  });

  factory CpuInfo.fromJson(Map<String, dynamic> json) {
    return CpuInfo(
      model: json['model'] ?? 'Unknown',
      cores: json['cores'] ?? 0,
      speed: json['speed'] ?? '0 MHz',
      currentUsage: json['currentUsage'] ?? '0%',
    );
  }

  double get usagePercentValue {
    final match = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(currentUsage);
    return match != null ? double.tryParse(match.group(1)!) ?? 0.0 : 0.0;
  }
}

class StorageInfo {
  final String totalStorage;
  final String totalUsed;
  final String totalFree;
  final String totalUsagePercent;

  StorageInfo({
    required this.totalStorage,
    required this.totalUsed,
    required this.totalFree,
    required this.totalUsagePercent,
  });

  factory StorageInfo.fromJson(Map<String, dynamic> json) {
    return StorageInfo(
      totalStorage: json['totalStorage'] ?? '0 B',
      totalUsed: json['totalUsed'] ?? '0 B',
      totalFree: json['totalFree'] ?? '0 B',
      totalUsagePercent: json['totalUsagePercent'] ?? '0%',
    );
  }

  double get usagePercentValue {
    final match = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(totalUsagePercent);
    return match != null ? double.tryParse(match.group(1)!) ?? 0.0 : 0.0;
  }
}

class DatabaseInfo {
  final String totalSongs;
  final String downloadedFiles;
  final String readyFiles;
  final String pendingFiles;
  final String failedFiles;
  final String successRate;

  DatabaseInfo({
    required this.totalSongs,
    required this.downloadedFiles,
    required this.readyFiles,
    required this.pendingFiles,
    required this.failedFiles,
    required this.successRate,
  });

  factory DatabaseInfo.fromJson(Map<String, dynamic> json) {
    return DatabaseInfo(
      totalSongs: json['totalSongs']?.toString() ?? '0',
      downloadedFiles: json['downloadedFiles']?.toString() ?? '0',
      readyFiles: json['readyFiles']?.toString() ?? '0',
      pendingFiles: json['pendingFiles']?.toString() ?? '0',
      failedFiles: json['failedFiles']?.toString() ?? '0',
      successRate: json['successRate']?.toString() ?? '0%',
    );
  }

  int get totalSongsValue {
    // Remove commas and parse as int
    final cleaned = totalSongs.replaceAll(',', '');
    return int.tryParse(cleaned) ?? 0;
  }
}

enum ServerStatus { live, down, offline }

extension ServerStatusExtension on ServerStatus {
  String get displayName {
    switch (this) {
      case ServerStatus.live:
        return 'Server Live!';
      case ServerStatus.down:
        return 'Server Down';
      case ServerStatus.offline:
        return 'You seem offline';
    }
  }

  Color get color {
    switch (this) {
      case ServerStatus.live:
        return const Color(0xFF4CAF50); // Green
      case ServerStatus.down:
        return const Color(0xFFF44336); // Red
      case ServerStatus.offline:
        return const Color(0xFFFF9800); // Orange
    }
  }
}
