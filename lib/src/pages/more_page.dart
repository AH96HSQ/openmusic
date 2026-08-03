import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/theme_controller.dart';
import '../widgets/color_picker_page.dart';
import '../services/system_service.dart';
import '../services/status_message_controller.dart';
import '../services/download_settings_service.dart';
import '../ui/widgets/auth_widget.dart';
import 'crypto_payment_page.dart';

/// Check if running on desktop platform
bool get _isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class MorePage extends StatefulWidget {
  const MorePage({super.key, this.themeController});
  final ThemeController? themeController;

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  // Data from server
  DonationInfo? _donationInfo;

  // UI state
  final bool _showDonatePanel = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load donation info and system performance in parallel
    final futures = await Future.wait([
      SystemService.instance.getDonationInfo(),
      SystemService.instance.getSystemPerformance(),
    ]);

    if (mounted) {
      setState(() {
        _donationInfo = futures[0] as DonationInfo?;
      });
    }
  }

  // Quick util: open external URL
  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      StatusMessageController.instance.showMessage(
        'Could not open link.',
        duration: const Duration(milliseconds: 2200),
      );
    }
  }

  // Copy helper with status message
  Future<void> _copy(String text, {String copiedLabel = 'Copied!'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    StatusMessageController.instance.showMessage(
      copiedLabel,
      duration: const Duration(milliseconds: 4000),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.themeController;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Get screen dimensions
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final screenHeight = size.height;

    // On desktop, use fixed sizes; on mobile, use responsive sizes
    final isDesktop = _isDesktopPlatform;
    final contentPadding = isDesktop ? 16.0 : screenWidth * 0.04;
    final borderRadius = isDesktop ? 16.0 : screenWidth * 0.05;
    final spacing = isDesktop ? 16.0 : screenHeight * 0.02;
    final buttonHeight = isDesktop ? 48.0 : screenHeight * 0.07;
    final fontSize = isDesktop ? 16.0 : screenWidth * 0.045;
    final smallFontSize = isDesktop ? 14.0 : screenWidth * 0.035;
    final iconSize = isDesktop ? 20.0 : screenWidth * 0.06;

    cs.onSurface.withAlpha((0.10 * 255).round());

    // Wrap content in a centered container with max width on desktop
    Widget content = ListView(
      padding: EdgeInsets.all(contentPadding),
      children: [
        // ===== Donation header box =====
        Container(
          padding: EdgeInsets.all(contentPadding),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: cs.onSurface.withAlpha((0.08 * 255).round()),
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Help keep the servers running!',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  SizedBox(height: spacing),
                  // --- Row 2: Donate Now Button ---
                  Container(
                    height: buttonHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                      ),
                      borderRadius: BorderRadius.circular(borderRadius * 0.8),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(borderRadius * 0.8),
                      onTap: () {
                        // Open crypto payment page
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const CryptoPaymentPage(),
                          ),
                        );
                      },
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.favorite_border,
                              color: cs.onPrimary,
                              size: iconSize,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Donate Now!',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onPrimary,
                                fontSize: fontSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // --- Tabbed rectangle appears here ---
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: !_showDonatePanel
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _DonateTabs(
                              onCopy: _copy,
                              onOpen: _open,
                              donationInfo: _donationInfo,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),

        SizedBox(height: spacing),

        // ===== Account section =====
        Container(
          padding: EdgeInsets.all(contentPadding),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: cs.onSurface.withAlpha((0.08 * 255).round()),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Account header
              Text(
                'Account',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              SizedBox(height: spacing),

              // Auth widget handles all authentication UI
              const AuthWidget(),
            ],
          ),
        ),

        SizedBox(height: spacing),

        // ===== Settings section =====
        Container(
          padding: EdgeInsets.all(contentPadding),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: cs.onSurface.withAlpha((0.08 * 255).round()),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Settings header
              Text(
                'Settings',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              SizedBox(height: spacing),

              // Theme selector - no title, just segments
              if (tc != null)
                ListenableBuilder(
                  listenable: tc,
                  builder: (context, _) => Row(
                    children: [
                      Expanded(
                        child: _ThemeButton(
                          label: 'System',
                          isSelected: tc.mode == ThemeMode.system,
                          onTap: () => tc.setMode(ThemeMode.system),
                          colorScheme: cs,
                          isDesktop: isDesktop,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ThemeButton(
                          label: 'Light',
                          isSelected: tc.mode == ThemeMode.light,
                          onTap: () => tc.setMode(ThemeMode.light),
                          colorScheme: cs,
                          isDesktop: isDesktop,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ThemeButton(
                          label: 'Dark',
                          isSelected: tc.mode == ThemeMode.dark,
                          onTap: () => tc.setMode(ThemeMode.dark),
                          colorScheme: cs,
                          isDesktop: isDesktop,
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: spacing * 0.75),

              // Color picker - full width with centered text
              if (tc != null)
                InkWell(
                  onTap: () async {
                    final c = await Navigator.of(context).push<Color?>(
                      MaterialPageRoute(
                        builder: (_) => ColorPickerPage(initial: tc.seedColor),
                      ),
                    );
                    if (c != null) tc.setSeedColor(c);
                  },
                  borderRadius: BorderRadius.circular(
                    isDesktop ? 12 : screenWidth * 0.03,
                  ),
                  child: Container(
                    width: double.infinity,
                    height: isDesktop ? 40 : screenHeight * 0.05,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(
                        isDesktop ? 12 : screenWidth * 0.03,
                      ),
                      border: Border.all(
                        color: cs.onSurface.withAlpha((0.12 * 255).round()),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Color',
                        style: TextStyle(
                          fontSize: smallFontSize,
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

              SizedBox(height: spacing),

              // Download Method Order section header
              Text(
                'Download Method Priority',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),

              // Reorderable method list
              _DownloadMethodOrderWidget(
                colorScheme: cs,
                isDesktop: isDesktop,
                smallFontSize: smallFontSize,
              ),
            ],
          ),
        ),

        SizedBox(height: spacing),

        // ===== Support & Version section =====
        Container(
          padding: EdgeInsets.all(contentPadding),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: cs.onSurface.withAlpha((0.08 * 255).round()),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Support & Version header
              Text(
                'Support & Updates',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              SizedBox(height: spacing),

              // Row with Contact Support and Version buttons
              Row(
                children: [
                  // Contact Support button
                  Expanded(
                    child: _SupportButton(
                      label: 'Contact Support',
                      icon: Icons.telegram,
                      onTap: () async {
                        final url = Uri.parse('https://t.me/MyAppsSupport96');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      colorScheme: cs,
                      isDesktop: isDesktop,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Version Check button
                  Expanded(
                    child: _VersionButton(
                      colorScheme: cs,
                      isDesktop: isDesktop,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    // On desktop, constrain the max width and center the content
    if (isDesktop) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: content,
        ),
      );
    }

    return content;
  }
}

// Circular performance indicator widget
// Pulsating dot widget for server status
class _PulsatingDot extends StatefulWidget {
  final bool isOnline;

  const _PulsatingDot({required this.isOnline});

  @override
  State<_PulsatingDot> createState() => __PulsatingDotState();
}

class __PulsatingDotState extends State<_PulsatingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    if (widget.isOnline) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_PulsatingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline != oldWidget.isOnline) {
      if (widget.isOnline) {
        _animationController.repeat(reverse: true);
      } else {
        _animationController.stop();
        _animationController.reset();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isOnline
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.4);

    if (!widget.isOnline) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

// ------- Donate tabs widget (rounded rectangle + tabs) -------
class _DonateTabs extends StatelessWidget {
  const _DonateTabs({
    required this.onCopy,
    required this.onOpen,
    required this.donationInfo,
  });

  final Future<void> Function(String text, {String copiedLabel}) onCopy;
  final Future<void> Function(String url) onOpen;
  final DonationInfo? donationInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withAlpha((0.08 * 255).round())),
      ),
      child: DefaultTabController(
        length: 3,
        initialIndex: 2, // Start with crypto tab
        child: Column(
          children: [
            // Tabs header
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                color: cs.surfaceContainerHighest,
              ),
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(text: 'Iran'),
                  Tab(text: 'Global'),
                  Tab(text: 'Crypto'),
                ],
              ),
            ),
            const Divider(height: 1),
            // Tab bodies
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SizedBox(
                // Adjusted height for full-width chips
                height: 280,
                child: TabBarView(
                  children: [
                    // --- Iran ---
                    _TwoColChips(
                      children: [
                        ActionChip(
                          label: const Text(
                            'Card to Card',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: donationInfo != null
                              ? () => onCopy(
                                  donationInfo!.iranCardNumber,
                                  copiedLabel: 'Card number copied!',
                                )
                              : null,
                        ),
                        ActionChip(
                          label: const Text(
                            'CoffeeBede',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () =>
                              onOpen('https://coffeebede.com/hsq96'),
                        ),
                      ],
                    ),

                    // --- Global ---
                    _TwoColChips(
                      children: [
                        ActionChip(
                          label: const Text(
                            'Pay with Skrill',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: donationInfo != null
                              ? () => onCopy(
                                  donationInfo!.skrillEmail,
                                  copiedLabel: 'Email address copied!',
                                )
                              : null,
                        ),
                      ],
                    ),

                    // --- Crypto ---
                    _TwoColChips(
                      children: [
                        ActionChip(
                          label: const Text(
                            'Bitcoin (BTC)',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: donationInfo != null
                              ? () => onCopy(
                                  donationInfo!.crypto.btc,
                                  copiedLabel: 'BTC address copied!',
                                )
                              : null,
                        ),
                        ActionChip(
                          label: const Text(
                            'Ethereum (ETH)',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: donationInfo != null
                              ? () => onCopy(
                                  donationInfo!.crypto.eth,
                                  copiedLabel: 'ETH address copied!',
                                )
                              : null,
                        ),
                        ActionChip(
                          label: const Text(
                            'Litecoin (LTC)',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: donationInfo != null
                              ? () => onCopy(
                                  donationInfo!.crypto.ltc,
                                  copiedLabel: 'LTC address copied!',
                                )
                              : null,
                        ),
                        ActionChip(
                          label: const Text(
                            'USDT (TRC20)',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: donationInfo != null
                              ? () => onCopy(
                                  donationInfo!.crypto.usdtTron,
                                  copiedLabel: 'USDT-TRC20 address copied!',
                                )
                              : null,
                        ),
                        ActionChip(
                          label: const Text(
                            'USDT (ERC20)',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: donationInfo != null
                              ? () => onCopy(
                                  donationInfo!.crypto.usdtEth,
                                  copiedLabel: 'USDT-ERC20 address copied!',
                                )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A helper that lays chips as full-width buttons with better styling
class _TwoColChips extends StatelessWidget {
  const _TwoColChips({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Filter out empty SizedBox widgets
    final validChildren = children
        .where((w) => !(w is SizedBox && w.child == null))
        .toList();

    return Column(
      children: validChildren.map((w) {
        // Extract ActionChip properties
        if (w is ActionChip) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: Material(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: w.onPressed,
                  child: Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.onSurface.withAlpha((0.12 * 255).round()),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: DefaultTextStyle(
                        style:
                            theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ) ??
                            const TextStyle(),
                        child: w.label,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        // Fallback for other widgets
        return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: w);
      }).toList(),
    );
  }
}

// Theme button widget for theme selection
class _ThemeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final bool isDesktop;

  const _ThemeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = isDesktop ? 12.0 : 12.0;
    final verticalPadding = isDesktop ? 12.0 : 10.0;
    final fontSize = isDesktop ? 14.0 : 14.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding,
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.15)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withAlpha((0.1 * 255).round()),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.8),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Support button widget
class _SupportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final bool isDesktop;

  const _SupportButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.colorScheme,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = isDesktop ? 12.0 : 12.0;
    final verticalPadding = isDesktop ? 12.0 : 12.0;
    final fontSize = isDesktop ? 14.0 : 14.0;
    final iconSize = isDesktop ? 18.0 : 18.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding,
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: colorScheme.primary, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Version button widget with update check
class _VersionButton extends StatefulWidget {
  final ColorScheme colorScheme;
  final bool isDesktop;

  const _VersionButton({required this.colorScheme, required this.isDesktop});

  @override
  State<_VersionButton> createState() => _VersionButtonState();
}

class _VersionButtonState extends State<_VersionButton> {
  String _currentVersion = '...';
  String _latestVersion = '...';
  bool _isLatest = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  Future<void> _checkVersion() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;

      // Get latest version from server
      final versionInfo = await SystemService.getVersion();
      _latestVersion = versionInfo['latest'] ?? '0.1.0';

      // Compare versions
      _isLatest = _currentVersion == _latestVersion;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentVersion = '0.1.0';
          _latestVersion = '0.1.0';
          _isLatest = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.isDesktop ? 12.0 : 12.0;
    final verticalPadding = widget.isDesktop ? 12.0 : 12.0;
    final fontSize = widget.isDesktop ? 14.0 : 14.0;
    final iconSize = widget.isDesktop ? 18.0 : 18.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLatest
            ? null
            : () async {
                final url = Uri.parse('https://openmusic.web');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding,
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            color: _isLatest
                ? widget.colorScheme.surfaceContainerHighest
                : widget.colorScheme.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: _isLatest
                  ? widget.colorScheme.onSurface.withAlpha((0.1 * 255).round())
                  : widget.colorScheme.error,
              width: _isLatest ? 1 : 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading)
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.colorScheme.primary,
                  ),
                )
              else if (!_isLatest)
                Icon(
                  Icons.update,
                  size: iconSize,
                  color: widget.colorScheme.error,
                ),
              if (!_isLoading) const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _isLoading
                      ? 'Checking...'
                      : _isLatest
                      ? 'v$_currentVersion'
                      : 'Update!',
                  style: TextStyle(
                    fontSize: fontSize,
                    color: _isLatest
                        ? widget.colorScheme.onSurface.withValues(alpha: 0.5)
                        : widget.colorScheme.error,
                    fontWeight: _isLatest ? FontWeight.w500 : FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Download Method Order Widget - reorderable list
class _DownloadMethodOrderWidget extends StatefulWidget {
  final ColorScheme colorScheme;
  final bool isDesktop;
  final double smallFontSize;

  const _DownloadMethodOrderWidget({
    required this.colorScheme,
    required this.isDesktop,
    required this.smallFontSize,
  });

  @override
  State<_DownloadMethodOrderWidget> createState() =>
      _DownloadMethodOrderWidgetState();
}

class _DownloadMethodOrderWidgetState
    extends State<_DownloadMethodOrderWidget> {
  // Local state to prevent flash during reorder
  List<DownloadMethodId>? _localOrder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadSettingsService.instance,
      builder: (context, _) {
        // Use local order if available (during reorder), otherwise use service order
        final methodOrder =
            _localOrder ?? DownloadSettingsService.instance.methodOrder;

        return Column(
          children: [
            // Hint text
            Text(
              'Drag to reorder download methods',
              style: TextStyle(
                fontSize: widget.smallFontSize * 0.85,
                color: widget.colorScheme.onSurface.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),

            // Reorderable method chips
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: methodOrder.length,
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                );
              },
              onReorder: (oldIndex, newIndex) {
                // Update local state immediately to prevent flash
                setState(() {
                  _localOrder = List.from(methodOrder);
                  final method = _localOrder!.removeAt(oldIndex);
                  _localOrder!.insert(
                    newIndex > oldIndex ? newIndex - 1 : newIndex,
                    method,
                  );
                });
                // Then persist to service (will notify and clear local state)
                DownloadSettingsService.instance
                    .reorderMethod(oldIndex, newIndex)
                    .then((_) {
                      if (mounted) setState(() => _localOrder = null);
                    });
              },
              itemBuilder: (context, index) {
                final method = methodOrder[index];
                final name = DownloadSettingsService.getMethodName(method);

                return ReorderableDragStartListener(
                  key: ValueKey(method),
                  index: index,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: widget.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.colorScheme.onSurface.withValues(
                          alpha: 0.1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Priority number
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: widget.colorScheme.primary.withValues(
                              alpha: 0.15,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: widget.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Method icon
                        Icon(
                          _getMethodIcon(method),
                          size: 20,
                          color: widget.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Method name only (no description)
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: widget.smallFontSize,
                              fontWeight: FontWeight.w600,
                              color: widget.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        // Drag handle
                        Icon(
                          Icons.drag_handle,
                          size: 20,
                          color: widget.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Reset button
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                DownloadSettingsService.instance.resetToDefault();
              },
              icon: Icon(
                Icons.restore,
                size: 16,
                color: widget.colorScheme.primary,
              ),
              label: Text(
                'Reset to Default',
                style: TextStyle(
                  fontSize: widget.smallFontSize * 0.9,
                  color: widget.colorScheme.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _getMethodIcon(DownloadMethodId method) {
    switch (method) {
      case DownloadMethodId.sra:
        return Icons.speed;
      case DownloadMethodId.dsra:
        return Icons.cloud_download;
      case DownloadMethodId.smp:
        return Icons.music_note;
    }
  }
}
