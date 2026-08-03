import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/system_service.dart';
import '../services/status_message_controller.dart';

class CryptoPaymentPage extends StatefulWidget {
  const CryptoPaymentPage({super.key});

  @override
  State<CryptoPaymentPage> createState() => _CryptoPaymentPageState();
}

class _CryptoPaymentPageState extends State<CryptoPaymentPage> {
  CryptoAddresses? _cryptoAddresses;
  bool _isLoading = true;
  String? _selectedCurrency;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      final donationInfo = await SystemService.instance.getDonationInfo();
      if (mounted) {
        setState(() {
          _cryptoAddresses = donationInfo?.crypto;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        StatusMessageController.instance.showMessage(
          'Failed to load crypto addresses: ${e.toString()}',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    StatusMessageController.instance.showMessage(
      'Address copied to clipboard',
      duration: const Duration(seconds: 2),
    );
  }

  String _getCurrencyName(String key) {
    switch (key) {
      case 'btc':
        return 'Bitcoin (BTC)';
      case 'eth':
        return 'Ethereum (ETH)';
      case 'ltc':
        return 'Litecoin (LTC)';
      case 'usdtTron':
        return 'USDT (TRC20)';
      case 'usdtEth':
        return 'USDT (ERC20)';
      case 'usdcEth':
        return 'USDC (ERC20)';
      default:
        return key.toUpperCase();
    }
  }

  String _getAddress(String key) {
    if (_cryptoAddresses == null) return '';
    switch (key) {
      case 'btc':
        return _cryptoAddresses!.btc;
      case 'eth':
        return _cryptoAddresses!.eth;
      case 'ltc':
        return _cryptoAddresses!.ltc;
      case 'usdtTron':
        return _cryptoAddresses!.usdtTron;
      case 'usdtEth':
        return _cryptoAddresses!.usdtEth;
      case 'usdcEth':
        return _cryptoAddresses!.usdcEth;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_selectedCurrency != null) {
      return _buildAddressView(theme, cs);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Donate with Crypto'),
        backgroundColor: cs.surface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cryptoAddresses == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: cs.error),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load crypto addresses',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadAddresses,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Select Cryptocurrency',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Send any amount to support OpenMusic',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._buildCurrencyOptions(theme, cs),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildCurrencyOptions(ThemeData theme, ColorScheme cs) {
    final currencies = [
      ('btc', Icons.currency_bitcoin),
      ('eth', Icons.currency_exchange),
      ('ltc', Icons.currency_bitcoin),
      ('usdtTron', Icons.account_balance_wallet),
      ('usdtEth', Icons.account_balance_wallet),
      ('usdcEth', Icons.account_balance_wallet),
    ];

    return currencies.map((currency) {
      final key = currency.$1;
      final icon = currency.$2;
      final address = _getAddress(key);

      if (address.isEmpty) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => setState(() => _selectedCurrency = key),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: cs.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getCurrencyName(key),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildAddressView(ThemeData theme, ColorScheme cs) {
    final address = _getAddress(_selectedCurrency!);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getCurrencyName(_selectedCurrency!)),
        backgroundColor: cs.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _selectedCurrency = null),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // QR Code
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: QrImageView(
                data: address,
                version: QrVersions.auto,
                size: 180,
              ),
            ),

            const SizedBox(height: 20),

            // Instruction
            Text(
              'Send ${_getCurrencyName(_selectedCurrency!)} to:',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            // Address container
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  SelectableText(
                    address,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _copyAddress(address),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Address'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.favorite, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Thank you for supporting OpenMusic!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
