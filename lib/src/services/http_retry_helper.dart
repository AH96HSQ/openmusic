import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Helper class for HTTP requests with timeout and retry logic
class HttpRetryHelper {
  /// Default timeout duration for HTTP requests
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Default number of retry attempts
  static const int defaultMaxRetries = 3;

  /// Delay between retry attempts
  static const Duration retryDelay = Duration(seconds: 2);

  /// Make a GET request with timeout and retry logic
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
    int maxRetries = defaultMaxRetries,
    bool enableRetry = true,
  }) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < (enableRetry ? maxRetries : 1)) {
      attempts++;
      try {
        debugPrint(
          'HttpRetryHelper: GET $url (attempt $attempts/${enableRetry ? maxRetries : 1})',
        );

        final response = await http
            .get(url, headers: headers)
            .timeout(
              timeout,
              onTimeout: () {
                throw TimeoutException(
                  'Request timed out after $timeout',
                  timeout,
                );
              },
            );

        debugPrint(
          'HttpRetryHelper: GET $url succeeded with status ${response.statusCode}',
        );
        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint(
          'HttpRetryHelper: GET $url timed out (attempt $attempts): $e',
        );
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint(
          'HttpRetryHelper: GET $url client error (attempt $attempts): $e',
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception('Unknown error: $e');
        debugPrint('HttpRetryHelper: GET $url error (attempt $attempts): $e');
      }

      // If we have more retries left and retry is enabled, wait before retrying
      if (enableRetry && attempts < maxRetries) {
        debugPrint(
          'HttpRetryHelper: Waiting ${retryDelay.inSeconds}s before retry...',
        );
        await Future.delayed(retryDelay);
      }
    }

    // All retries exhausted
    final errorMsg = enableRetry
        ? 'Failed after $maxRetries attempts'
        : 'Request failed';
    debugPrint('HttpRetryHelper: GET $url $errorMsg. Last error: $lastError');
    throw lastError ?? Exception(errorMsg);
  }

  /// Make a POST request with timeout and retry logic
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = defaultTimeout,
    int maxRetries = defaultMaxRetries,
    bool enableRetry = true,
  }) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < (enableRetry ? maxRetries : 1)) {
      attempts++;
      try {
        debugPrint(
          'HttpRetryHelper: POST $url (attempt $attempts/${enableRetry ? maxRetries : 1})',
        );

        final response = await http
            .post(url, headers: headers, body: body)
            .timeout(
              timeout,
              onTimeout: () {
                throw TimeoutException(
                  'Request timed out after $timeout',
                  timeout,
                );
              },
            );

        debugPrint(
          'HttpRetryHelper: POST $url succeeded with status ${response.statusCode}',
        );
        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint(
          'HttpRetryHelper: POST $url timed out (attempt $attempts): $e',
        );
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint(
          'HttpRetryHelper: POST $url client error (attempt $attempts): $e',
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception('Unknown error: $e');
        debugPrint('HttpRetryHelper: POST $url error (attempt $attempts): $e');
      }

      // If we have more retries left and retry is enabled, wait before retrying
      if (enableRetry && attempts < maxRetries) {
        debugPrint(
          'HttpRetryHelper: Waiting ${retryDelay.inSeconds}s before retry...',
        );
        await Future.delayed(retryDelay);
      }
    }

    // All retries exhausted
    final errorMsg = enableRetry
        ? 'Failed after $maxRetries attempts'
        : 'Request failed';
    debugPrint('HttpRetryHelper: POST $url $errorMsg. Last error: $lastError');
    throw lastError ?? Exception(errorMsg);
  }

  /// Make a DELETE request with timeout and retry logic
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
    int maxRetries = defaultMaxRetries,
    bool enableRetry = false, // Usually don't retry deletes
  }) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < (enableRetry ? maxRetries : 1)) {
      attempts++;
      try {
        debugPrint(
          'HttpRetryHelper: DELETE $url (attempt $attempts/${enableRetry ? maxRetries : 1})',
        );

        final response = await http
            .delete(url, headers: headers)
            .timeout(
              timeout,
              onTimeout: () {
                throw TimeoutException(
                  'Request timed out after $timeout',
                  timeout,
                );
              },
            );

        debugPrint(
          'HttpRetryHelper: DELETE $url succeeded with status ${response.statusCode}',
        );
        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint(
          'HttpRetryHelper: DELETE $url timed out (attempt $attempts): $e',
        );
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint(
          'HttpRetryHelper: DELETE $url client error (attempt $attempts): $e',
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception('Unknown error: $e');
        debugPrint(
          'HttpRetryHelper: DELETE $url error (attempt $attempts): $e',
        );
      }

      // If we have more retries left and retry is enabled, wait before retrying
      if (enableRetry && attempts < maxRetries) {
        debugPrint(
          'HttpRetryHelper: Waiting ${retryDelay.inSeconds}s before retry...',
        );
        await Future.delayed(retryDelay);
      }
    }

    // All retries exhausted
    final errorMsg = enableRetry
        ? 'Failed after $maxRetries attempts'
        : 'Request failed';
    debugPrint(
      'HttpRetryHelper: DELETE $url $errorMsg. Last error: $lastError',
    );
    throw lastError ?? Exception(errorMsg);
  }

  /// Make a streamed GET request with timeout (no retry for streaming)
  static Future<http.StreamedResponse> getStreamed(
    http.Client client,
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
  }) async {
    try {
      debugPrint('HttpRetryHelper: Streamed GET $url');

      final request = http.Request('GET', url);
      if (headers != null) {
        request.headers.addAll(headers);
      }

      final response = await client
          .send(request)
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException('Stream request timed out after $timeout');
            },
          );

      debugPrint(
        'HttpRetryHelper: Streamed GET $url succeeded with status ${response.statusCode}',
      );
      return response;
    } on TimeoutException catch (e) {
      debugPrint('HttpRetryHelper: Streamed GET $url timed out: $e');
      rethrow;
    } catch (e) {
      debugPrint('HttpRetryHelper: Streamed GET $url error: $e');
      rethrow;
    }
  }
}
