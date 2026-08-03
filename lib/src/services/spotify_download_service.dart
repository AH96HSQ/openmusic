import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'status_message_controller.dart';
import 'download_settings_service.dart';

/// Result of a download operation
class DownloadResult {
  final bool ok;
  final bool cancelled;
  final String? path;
  final int? sizeBytes;
  final String? mime;
  final String? error;

  const DownloadResult.success({
    required String this.path,
    this.sizeBytes,
    this.mime,
  }) : ok = true,
       cancelled = false,
       error = null;

  const DownloadResult.failure(this.error)
    : ok = false,
      cancelled = false,
      path = null,
      sizeBytes = null,
      mime = null;

  const DownloadResult.aborted()
    : ok = false,
      cancelled = true,
      error = 'Download cancelled',
      path = null,
      sizeBytes = null,
      mime = null;
}

/// On-device Spotify download service with 5 download methods
/// Priority order:
/// 1. RapidAPI (spotify-downloader9) - most reliable
/// 2. DS RapidAPI (spotify-and-deezer-download) - backup
/// 3. SpotMate - fallback 1
/// 4. FabDL - fallback 2
/// 5. SpotiMP3 - fallback 3
class SpotifyDownloadService {
  static final SpotifyDownloadService instance =
      SpotifyDownloadService._internal();
  SpotifyDownloadService._internal();

  // API Keys - can be updated from backend
  String _rapidApiKey = '353911e03dmshfc92380284fba44p164b70jsnba7769ba4608';
  String _dsRapidApiKey = '353911e03dmshfc92380284fba44p164b70jsnba7769ba4608';

  /// Update API keys (called from credentials service)
  void updateApiKeys({String? rapidApiKey, String? dsRapidApiKey}) {
    if (rapidApiKey != null && rapidApiKey.isNotEmpty) {
      _rapidApiKey = rapidApiKey;
    }
    if (dsRapidApiKey != null && dsRapidApiKey.isNotEmpty) {
      _dsRapidApiKey = dsRapidApiKey;
    }
  }

  /// Check if device has internet connectivity by pinging Google
  Future<bool> _hasNetworkConnection() async {
    try {
      final result = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      return result.statusCode == 200;
    } catch (e) {
      debugPrint('🌐 Network check failed: $e');
      return false;
    }
  }

  /// Get the music directory for saving downloaded files
  Future<Directory> _getMusicDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${appDir.path}/music');
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  /// Minimum valid MP3 file size (500 KB) - anything smaller is likely corrupted or HTML error
  static const int _minMp3SizeBytes = 500 * 1024;

  /// Validate that a file is actually an MP3 and not an error page or corrupted data
  Future<String?> _validateMp3File(File file) async {
    try {
      final stat = await file.stat();

      // Check minimum size - a real song should be at least 500 KB
      if (stat.size < _minMp3SizeBytes) {
        return 'File too small (${stat.size} bytes) - likely not a valid audio file';
      }

      // Check MP3 magic bytes
      // MP3 files start with either:
      // - ID3 tag: 0x49 0x44 0x33 ("ID3")
      // - Frame sync: 0xFF 0xFB/0xFA/0xF3/0xF2 (MPEG audio frame)
      final bytes = await file.openRead(0, 10).expand((e) => e).toList();
      if (bytes.length < 3) {
        return 'File too short to validate';
      }

      final hasId3Tag =
          bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
      final hasMpegSync = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;

      if (!hasId3Tag && !hasMpegSync) {
        // Check if it's HTML (error page)
        final headerStr = String.fromCharCodes(bytes.take(10));
        if (headerStr.toLowerCase().contains('<!doctype') ||
            headerStr.toLowerCase().contains('<html')) {
          return 'Downloaded HTML error page instead of audio';
        }
        return 'Invalid MP3 header - file may be corrupted';
      }

      return null; // Valid
    } catch (e) {
      return 'Validation error: $e';
    }
  }

  /// Generate a unique filename for a track
  String _generateFilename(String trackId, {String? artist, String? title}) {
    String safe(String? s) =>
        s?.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_') ?? '';
    final artistPart = safe(artist);
    final titlePart = safe(title);
    if (artistPart.isNotEmpty || titlePart.isNotEmpty) {
      return '${artistPart.isNotEmpty ? "$artistPart-" : ""}$titlePart-$trackId.mp3';
    }
    return '$trackId.mp3';
  }

  /// Extract track ID from Spotify URL
  String? _extractTrackId(String spotifyUrl) {
    final match = RegExp(r'track/([a-zA-Z0-9]{22})').firstMatch(spotifyUrl);
    return match?.group(1);
  }

  /// Default browser-like headers for web scraping
  Map<String, String> get _defaultHeaders => {
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Encoding': 'gzip, deflate',
    'Accept-Language': 'en-US,en;q=0.9',
    'Cache-Control': 'max-age=0',
    'Sec-Ch-Ua':
        '"Google Chrome";v="123", "Not:A-Brand";v="8", "Chromium";v="123"',
    'Sec-Ch-Ua-Mobile': '?0',
    'Sec-Ch-Ua-Platform': '"Windows"',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-User': '?1',
    'Upgrade-Insecure-Requests': '1',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  };

  /// Download method selection
  static const int methodAuto = 0; // Try all methods in configured order
  static const int methodSRA = 1; // SRA (Spotify RapidAPI)
  static const int methodDSRA = 2; // DSRA (Deezer & Spotify RapidAPI)
  static const int methodSMP = 3; // SMP (SpotiMP3)

  // Legacy aliases for compatibility
  static const int methodRapidApi = methodSRA;
  static const int methodDsRapidApi = methodDSRA;
  static const int methodSpotiMp3 = methodSMP;

  /// Main download method - tries methods in priority order with retries
  /// Each method gets 2 attempts = 6 total attempts
  /// Uses method order from DownloadSettingsService
  /// Pass [isCancelled] callback to check if the operation should be aborted
  /// Pass [method] to force a specific download method (0=auto, 1=RapidAPI, 2=DS RapidAPI, 3=SpotiMP3)
  /// Pass [batchCurrent] and [batchTotal] for batch download context
  Future<DownloadResult> downloadSpotifyTrack(
    String spotifyUrl, {
    void Function(int bytesWritten, int? total)? onProgress,
    bool Function()? isCancelled,
    int method = 0, // 0 = auto (try all)
    int? batchCurrent,
    int? batchTotal,
  }) async {
    debugPrint(
      '🎵 SpotifyDownloadService: Starting download for $spotifyUrl (method: $method)',
    );

    final trackId = _extractTrackId(spotifyUrl);
    if (trackId == null) {
      return const DownloadResult.failure('Invalid Spotify URL format');
    }

    // Check if cancelled before starting
    if (isCancelled?.call() == true) {
      debugPrint('🛑 Download cancelled before starting');
      return const DownloadResult.aborted();
    }

    // Network check before trying any methods
    debugPrint('🌐 Checking network connectivity...');
    if (!await _hasNetworkConnection()) {
      debugPrint('❌ No network connection detected');
      StatusMessageController.instance.showOffline();
      return const DownloadResult.failure('No internet connection');
    }
    debugPrint('✅ Network connection OK');

    // If a specific method is requested, only try that method
    if (method != methodAuto) {
      return _downloadWithSpecificMethod(
        method,
        spotifyUrl,
        trackId,
        onProgress,
        isCancelled,
        batchCurrent: batchCurrent,
        batchTotal: batchTotal,
      );
    }

    // Auto mode: try all methods in configured order
    return _downloadWithAutoMode(
      spotifyUrl,
      trackId,
      onProgress,
      isCancelled,
      batchCurrent: batchCurrent,
      batchTotal: batchTotal,
    );
  }

  /// Download using auto mode - tries all methods in configured order
  Future<DownloadResult> _downloadWithAutoMode(
    String spotifyUrl,
    String trackId,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled, {
    int? batchCurrent,
    int? batchTotal,
  }) async {
    // Get method order from settings
    final methodOrder = DownloadSettingsService.instance.methodOrder;

    const int retriesPerMethod = 2;
    final int totalAttempts = methodOrder.length * retriesPerMethod;
    DownloadResult? lastResult;

    // Try each method in the configured order
    for (int methodIndex = 0; methodIndex < methodOrder.length; methodIndex++) {
      final methodId = methodOrder[methodIndex];
      final methodName = DownloadSettingsService.getMethodName(methodId);
      final serviceMethod = DownloadSettingsService.toServiceMethod(methodId);

      for (int retry = 0; retry < retriesPerMethod; retry++) {
        debugPrint(
          '🚀 Attempting Method ${methodIndex + 1} ($methodName), attempt ${retry + 1}/$retriesPerMethod...',
        );
        StatusMessageController.instance.showTryingMethod(
          methodName,
          isFirstAttempt: retry == 0,
          batchCurrent: batchCurrent,
          batchTotal: batchTotal,
        );

        lastResult = await _executeDownloadMethod(
          serviceMethod,
          spotifyUrl,
          trackId,
          onProgress,
          isCancelled,
        );

        if (lastResult.cancelled) {
          debugPrint('🛑 Download cancelled during $methodName');
          return lastResult;
        }
        if (lastResult.ok) {
          debugPrint(
            '✅ $methodName download successful on attempt ${retry + 1}!',
          );
          return lastResult;
        }
        debugPrint(
          '❌ $methodName attempt ${retry + 1} failed: ${lastResult.error}',
        );

        // Check if cancelled before retry
        if (isCancelled?.call() == true) {
          return const DownloadResult.aborted();
        }

        // 2.4 second cooldown between attempts
        if (retry < retriesPerMethod - 1) {
          await Future.delayed(const Duration(milliseconds: 2400));
        }
      }

      // Cooldown between methods
      if (methodIndex < methodOrder.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // All attempts failed - show error message
    debugPrint('💥 All $totalAttempts download attempts failed');
    StatusMessageController.instance.showAllAttemptsFailed();

    return DownloadResult.failure(
      'All download methods failed after $totalAttempts attempts. Last error: ${lastResult?.error}',
    );
  }

  /// Execute a specific download method
  Future<DownloadResult> _executeDownloadMethod(
    int method,
    String spotifyUrl,
    String trackId,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled,
  ) async {
    switch (method) {
      case methodSRA:
        return _downloadRapidAPI(spotifyUrl, trackId, onProgress, isCancelled);
      case methodDSRA:
        return _downloadDSRapidAPI(
          spotifyUrl,
          trackId,
          onProgress,
          isCancelled,
        );
      case methodSMP:
        return _downloadSpotiMP3(spotifyUrl, trackId, onProgress, isCancelled);
      default:
        return const DownloadResult.failure('Invalid download method');
    }
  }

  /// Download using a specific method only (with retries)
  Future<DownloadResult> _downloadWithSpecificMethod(
    int method,
    String spotifyUrl,
    String trackId,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled, {
    int? batchCurrent,
    int? batchTotal,
  }) async {
    const int retriesPerMethod = 2;
    DownloadResult? lastResult;

    String methodName;
    switch (method) {
      case methodSRA:
        methodName = 'SRA';
        break;
      case methodDSRA:
        methodName = 'DSRA';
        break;
      case methodSMP:
        methodName = 'SMP';
        break;
      default:
        return const DownloadResult.failure('Invalid download method');
    }

    for (int retry = 0; retry < retriesPerMethod; retry++) {
      debugPrint(
        '🚀 Attempting $methodName, attempt ${retry + 1}/$retriesPerMethod...',
      );
      StatusMessageController.instance.showTryingMethod(
        methodName,
        isFirstAttempt: retry == 0,
        batchCurrent: batchCurrent,
        batchTotal: batchTotal,
      );

      switch (method) {
        case methodSRA:
          lastResult = await _downloadRapidAPI(
            spotifyUrl,
            trackId,
            onProgress,
            isCancelled,
          );
          break;
        case methodDSRA:
          lastResult = await _downloadDSRapidAPI(
            spotifyUrl,
            trackId,
            onProgress,
            isCancelled,
          );
          break;
        case methodSMP:
          lastResult = await _downloadSpotiMP3(
            spotifyUrl,
            trackId,
            onProgress,
            isCancelled,
          );
          break;
      }

      if (lastResult?.cancelled == true) {
        debugPrint('🛑 Download cancelled during $methodName');
        return lastResult!;
      }
      if (lastResult?.ok == true) {
        debugPrint(
          '✅ $methodName download successful on attempt ${retry + 1}!',
        );
        return lastResult!;
      }
      debugPrint(
        '❌ $methodName attempt ${retry + 1} failed: ${lastResult?.error}',
      );

      // Check if cancelled before retry
      if (isCancelled?.call() == true) {
        return const DownloadResult.aborted();
      }

      // 2.4 second cooldown between attempts
      if (retry < retriesPerMethod - 1) {
        await Future.delayed(const Duration(milliseconds: 2400));
      }
    }

    // All attempts failed
    debugPrint(
      '💥 $methodName download failed after $retriesPerMethod attempts',
    );
    StatusMessageController.instance.showAllAttemptsFailed();

    return DownloadResult.failure(
      '$methodName download failed after $retriesPerMethod attempts. Last error: ${lastResult?.error}',
    );
  }

  /// Method 1: RapidAPI (spotify-downloader9.p.rapidapi.com)
  Future<DownloadResult> _downloadRapidAPI(
    String spotifyUrl,
    String trackId,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled,
  ) async {
    try {
      // Check cancellation before API call
      if (isCancelled?.call() == true) {
        return const DownloadResult.aborted();
      }

      final encodedUrl = Uri.encodeComponent(spotifyUrl);
      final apiUrl =
          'https://spotify-downloader9.p.rapidapi.com/downloadSong?songId=$encodedUrl';

      debugPrint('📡 [RapidAPI] URL: $apiUrl');
      debugPrint(
        '📡 [RapidAPI] Using key: ${_rapidApiKey.substring(0, 10)}...',
      );

      final response = await http
          .get(
            Uri.parse(apiUrl),
            headers: {
              'x-rapidapi-key': _rapidApiKey,
              'x-rapidapi-host': 'spotify-downloader9.p.rapidapi.com',
            },
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📡 [RapidAPI] Status: ${response.statusCode}');
      debugPrint(
        '📡 [RapidAPI] Response body: ${response.body.substring(0, response.body.length.clamp(0, 500))}',
      );

      if (response.statusCode != 200) {
        return DownloadResult.failure(
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body);
      debugPrint('📡 [RapidAPI] Parsed data keys: ${data.keys.toList()}');

      // Extract download link from response
      String? downloadLink;
      dynamic downloadData;
      if (data['response']?['data'] != null) {
        downloadData = data['response']['data'];
        downloadLink = downloadData['downloadLink'] as String?;
        debugPrint(
          '📡 [RapidAPI] Found downloadLink in response.data: $downloadLink',
        );
      } else if (data['data'] != null) {
        downloadData = data['data'];
        downloadLink = downloadData['downloadLink'] as String?;
        debugPrint('📡 [RapidAPI] Found downloadLink in data: $downloadLink');
      } else {
        debugPrint(
          '📡 [RapidAPI] No response.data or data found! Full response: $data',
        );
      }

      if (downloadLink == null || downloadLink.isEmpty) {
        return DownloadResult.failure(
          'No download link in response. Keys: ${data.keys.toList()}',
        );
      }

      // Extract metadata for filename
      final artist = downloadData?['artist'] as String?;
      final title = downloadData?['title'] as String?;
      debugPrint('📡 [RapidAPI] Metadata - Artist: $artist, Title: $title');

      // Download the actual file
      debugPrint('📡 [RapidAPI] Downloading file from: $downloadLink');
      return await _downloadFile(
        downloadLink,
        trackId,
        artist: artist,
        title: title,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } catch (e, stack) {
      debugPrint('📡 [RapidAPI] Exception: $e');
      debugPrint('📡 [RapidAPI] Stack: $stack');
      return DownloadResult.failure(e.toString());
    }
  }

  /// Method 2: DS RapidAPI (spotify-and-deezer-download.p.rapidapi.com)
  Future<DownloadResult> _downloadDSRapidAPI(
    String spotifyUrl,
    String trackId,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled,
  ) async {
    try {
      // Check cancellation before API call
      if (isCancelled?.call() == true) {
        return const DownloadResult.aborted();
      }

      final encodedUrl = Uri.encodeComponent(spotifyUrl);
      final apiUrl =
          'https://spotify-and-deezer-download.p.rapidapi.com/api/music?url=$encodedUrl';

      debugPrint('📡 [DS-RapidAPI] URL: $apiUrl');
      debugPrint(
        '📡 [DS-RapidAPI] Using key: ${_dsRapidApiKey.substring(0, 10)}...',
      );

      final response = await http
          .get(
            Uri.parse(apiUrl),
            headers: {
              'x-rapidapi-key': _dsRapidApiKey,
              'x-rapidapi-host': 'spotify-and-deezer-download.p.rapidapi.com',
            },
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📡 [DS-RapidAPI] Status: ${response.statusCode}');
      debugPrint(
        '📡 [DS-RapidAPI] Response body: ${response.body.substring(0, response.body.length.clamp(0, 500))}',
      );

      if (response.statusCode != 200) {
        return DownloadResult.failure(
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body);
      debugPrint('📡 [DS-RapidAPI] Parsed data keys: ${data.keys.toList()}');
      debugPrint(
        '📡 [DS-RapidAPI] success=${data['success']}, error=${data['error']}',
      );

      // Check for failure: success must be true AND error must not be a truthy value or error message
      final errorValue = data['error'];
      final hasError =
          errorValue != null &&
          errorValue != false &&
          errorValue.toString().isNotEmpty;
      if (data['success'] != true || hasError) {
        return DownloadResult.failure(
          'success=${data['success']}, error=${errorValue?.toString() ?? 'null'}',
        );
      }

      final medias = data['medias'] as List<dynamic>?;
      debugPrint('📡 [DS-RapidAPI] Medias count: ${medias?.length ?? 0}');
      if (medias != null && medias.isNotEmpty) {
        debugPrint('📡 [DS-RapidAPI] First media: ${medias[0]}');
      }

      if (medias == null || medias.isEmpty) {
        return DownloadResult.failure('No media in response. Full data: $data');
      }

      final downloadUrl = medias[0]['url'] as String?;
      debugPrint('📡 [DS-RapidAPI] Download URL: $downloadUrl');

      if (downloadUrl == null || downloadUrl.isEmpty) {
        return DownloadResult.failure(
          'No download URL in media. Media[0]: ${medias[0]}',
        );
      }

      final artist = data['author'] as String?;
      final title = data['title'] as String?;
      debugPrint('📡 [DS-RapidAPI] Metadata - Author: $artist, Title: $title');

      debugPrint('📡 [DS-RapidAPI] Downloading file from: $downloadUrl');
      return await _downloadFile(
        downloadUrl,
        trackId,
        artist: artist,
        title: title,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } catch (e, stack) {
      debugPrint('📡 [DS-RapidAPI] Exception: $e');
      debugPrint('📡 [DS-RapidAPI] Stack: $stack');
      return DownloadResult.failure(e.toString());
    }
  }

  /// Method 3: SpotiMP3 (spotimp3.com) - Fallback
  Future<DownloadResult> _downloadSpotiMP3(
    String spotifyUrl,
    String trackId,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled,
  ) async {
    try {
      // Wrap the entire method in a timeout to prevent hanging
      return await Future.any([
        _downloadSpotiMP3Internal(spotifyUrl, trackId, onProgress, isCancelled),
        Future.delayed(const Duration(seconds: 45), () {
          debugPrint('🎯 [SpotiMP3] Total timeout reached (45s)');
          return const DownloadResult.failure('SpotiMP3 timeout after 45s');
        }),
      ]);
    } catch (e) {
      return DownloadResult.failure(e.toString());
    }
  }

  Future<DownloadResult> _downloadSpotiMP3Internal(
    String spotifyUrl,
    String trackId,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled,
  ) async {
    try {
      // Check cancellation before API call
      if (isCancelled?.call() == true) {
        return const DownloadResult.aborted();
      }

      // Step 1: Get song details (and cookies)
      final detailsResponse = await http
          .get(
            Uri.parse(
              'https://www.spotimp3.com/api/song-details?url=${Uri.encodeComponent(spotifyUrl)}',
            ),
            headers: _defaultHeaders,
          )
          .timeout(const Duration(seconds: 20));

      final cookies = detailsResponse.headers['set-cookie'] ?? '';

      // Check cancellation before download
      if (isCancelled?.call() == true) {
        return const DownloadResult.aborted();
      }

      // Step 2: Download directly
      final downloadResponse = await http
          .post(
            Uri.parse('https://www.spotimp3.com/api/download'),
            headers: {
              ..._defaultHeaders,
              'Content-Type': 'application/json',
              'Cookie': cookies,
              'Origin': 'https://spotimp3.com',
              'Referer': 'https://spotimp3.com/',
            },
            body: jsonEncode({'url': spotifyUrl}),
          )
          .timeout(const Duration(seconds: 30));

      // Check cancellation after download
      if (isCancelled?.call() == true) {
        return const DownloadResult.aborted();
      }

      if (downloadResponse.statusCode != 200) {
        return DownloadResult.failure('HTTP ${downloadResponse.statusCode}');
      }

      // This method returns the file directly in the response
      final bytes = downloadResponse.bodyBytes;
      if (bytes.isEmpty) {
        return const DownloadResult.failure('Empty response');
      }

      // Save to file
      final musicDir = await _getMusicDir();
      final filename = _generateFilename(trackId);
      final file = File('${musicDir.path}/$filename');
      await file.writeAsBytes(bytes);

      onProgress?.call(bytes.length, bytes.length);

      // Validate the downloaded file is actually an MP3
      final validationError = await _validateMp3File(file);
      if (validationError != null) {
        debugPrint('📥 [SpotiMP3] ❌ Validation failed: $validationError');
        try {
          await file.delete();
        } catch (_) {}
        return DownloadResult.failure(validationError);
      }

      return DownloadResult.success(
        path: file.path,
        sizeBytes: bytes.length,
        mime: 'audio/mpeg',
      );
    } catch (e) {
      return DownloadResult.failure(e.toString());
    }
  }

  /// Download a file from URL with progress tracking
  Future<DownloadResult> _downloadFile(
    String url,
    String trackId, {
    String? artist,
    String? title,
    void Function(int, int?)? onProgress,
    bool Function()? isCancelled,
  }) async {
    try {
      // Check cancellation before starting
      if (isCancelled?.call() == true) {
        return const DownloadResult.aborted();
      }

      debugPrint('📥 [DownloadFile] Starting download from: $url');
      final request = http.Request('GET', Uri.parse(url));
      final client = http.Client();

      try {
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));

        debugPrint('📥 [DownloadFile] Response status: ${response.statusCode}');
        debugPrint(
          '📥 [DownloadFile] Content-Length: ${response.contentLength}',
        );
        debugPrint(
          '📥 [DownloadFile] Content-Type: ${response.headers['content-type']}',
        );

        if (response.statusCode >= 400) {
          return DownloadResult.failure('Download HTTP ${response.statusCode}');
        }

        final contentLength = response.contentLength;
        final musicDir = await _getMusicDir();
        final filename = _generateFilename(
          trackId,
          artist: artist,
          title: title,
        );
        final file = File('${musicDir.path}/$filename');
        debugPrint('📥 [DownloadFile] Saving to: ${file.path}');

        final sink = file.openWrite();
        int bytesWritten = 0;
        bool wasCancelled = false;

        await for (final chunk in response.stream) {
          // Check for cancellation during download
          if (isCancelled?.call() == true) {
            debugPrint('📥 [DownloadFile] 🛑 Download cancelled mid-stream');
            wasCancelled = true;
            break;
          }

          sink.add(chunk);
          bytesWritten += chunk.length;
          onProgress?.call(bytesWritten, contentLength);
        }

        await sink.close();

        // If cancelled, delete partial file and return
        if (wasCancelled) {
          try {
            if (await file.exists()) {
              await file.delete();
              debugPrint('📥 [DownloadFile] Deleted partial file');
            }
          } catch (_) {}
          return const DownloadResult.aborted();
        }

        final stat = await file.stat();
        debugPrint(
          '📥 [DownloadFile] ✅ Download complete! Size: ${stat.size} bytes',
        );

        // Validate the downloaded file is actually an MP3
        final validationError = await _validateMp3File(file);
        if (validationError != null) {
          debugPrint('📥 [DownloadFile] ❌ Validation failed: $validationError');
          try {
            await file.delete();
          } catch (_) {}
          return DownloadResult.failure(validationError);
        }

        return DownloadResult.success(
          path: file.path,
          sizeBytes: stat.size,
          mime: response.headers['content-type'] ?? 'audio/mpeg',
        );
      } finally {
        client.close();
      }
    } catch (e, stack) {
      debugPrint('📥 [DownloadFile] Exception: $e');
      debugPrint('📥 [DownloadFile] Stack: $stack');
      return DownloadResult.failure(e.toString());
    }
  }
}
