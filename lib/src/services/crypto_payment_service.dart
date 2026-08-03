import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class CryptoPaymentService {
  static final CryptoPaymentService _instance =
      CryptoPaymentService._internal();
  static CryptoPaymentService get instance => _instance;
  CryptoPaymentService._internal();

  late final Dio _dio;
  late final String _baseUrl;
  late final String _apiKey;

  Future<void> init() async {
    final envBase = dotenv.env['CRYPTO_PAYMENT_URL']?.trim();
    _baseUrl = envBase?.isNotEmpty == true
        ? envBase!.replaceAll(RegExp(r'/+$'), '')
        : 'http://localhost:5004';

    _apiKey = dotenv.env['CRYPTO_PAYMENT_API_KEY']?.trim() ?? '';

    _dio = Dio(
      BaseOptions(
        baseUrl: '$_baseUrl/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'X-API-Key': _apiKey},
      ),
    );

    debugPrint('CryptoPaymentService initialized: $_baseUrl');
  }

  /// Create a new payment (user-defined amount mode for donations)
  Future<Map<String, dynamic>> createPayment({
    required String orderId,
    required double amount,
    required String currency,
    String paymentMode = 'user_defined',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await _dio.post(
        '/payments',
        data: {
          'orderId': orderId,
          'amount': amount,
          'currency': currency,
          'paymentMode': paymentMode,
          if (metadata != null) 'metadata': metadata,
        },
      );

      return response.data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error creating payment: $e');
      rethrow;
    }
  }

  /// Check payment status (public endpoint, no auth needed)
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) async {
    try {
      final response = await _dio.get(
        '/payments/$paymentId/status',
        options: Options(
          headers: {}, // Remove API key for public endpoint
        ),
      );

      return response.data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error checking payment status: $e');
      rethrow;
    }
  }

  /// Poll payment status until completed or timeout
  Stream<Map<String, dynamic>> pollPaymentStatus(
    String paymentId, {
    Duration interval = const Duration(seconds: 5),
    Duration timeout = const Duration(minutes: 30),
  }) async* {
    final startTime = DateTime.now();

    while (true) {
      if (DateTime.now().difference(startTime) > timeout) {
        throw Exception('Payment timeout');
      }

      try {
        final status = await getPaymentStatus(paymentId);
        yield status;

        // Stop polling if payment is completed or failed
        if (status['status'] == 'completed' ||
            status['status'] == 'failed' ||
            status['status'] == 'expired') {
          break;
        }
      } catch (e) {
        debugPrint('Error polling payment status: $e');
        // Continue polling on error
      }

      await Future.delayed(interval);
    }
  }

  /// Get list of supported currencies
  List<String> getSupportedCurrencies() {
    return ['BTC', 'ETH', 'LTC', 'USDT_ERC20', 'USDC_ERC20'];
  }

  /// Get currency display name
  String getCurrencyDisplayName(String currency) {
    switch (currency) {
      case 'BTC':
        return 'Bitcoin';
      case 'ETH':
        return 'Ethereum';
      case 'LTC':
        return 'Litecoin';
      case 'USDT_ERC20':
        return 'Tether (ERC20)';
      case 'USDC_ERC20':
        return 'USD Coin (ERC20)';
      default:
        return currency;
    }
  }
}
