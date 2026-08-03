import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../services/status_message_controller.dart';
import '../widgets/auth_widget.dart';

/// Custom painter for dotted background pattern
class DottedBackgroundPainter extends CustomPainter {
  final Color dotColor;
  final double dotRadius;
  final double spacing;

  DottedBackgroundPainter({
    required this.dotColor,
    this.dotRadius = 1.5,
    this.spacing = 24.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DottedBackgroundPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.dotRadius != dotRadius ||
        oldDelegate.spacing != spacing;
  }
}

class WelcomePage extends StatefulWidget {
  final VoidCallback onGetStarted;

  const WelcomePage({super.key, required this.onGetStarted});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _openMusicLoggedIn = false;

  Future<void> _handleOpenMusicLogin() async {
    // Show the auth widget in a bottom sheet
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).size.height * 0.12,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: 24,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: IntrinsicHeight(
              child: AuthWidget(
                onLoginSuccess: () async {
                  // Close the bottom sheet
                  Navigator.of(context).pop();

                  // Restore data but stay on welcome page
                  if (AuthService.instance.isLoggedIn) {
                    try {
                      StatusMessageController.instance.showMessage(
                        'Restoring your library',
                        duration: const Duration(seconds: 2),
                      );

                      // Restore user's data from backend
                      await SyncService.instance.restoreData();

                      // Mark as logged in
                      if (mounted) {
                        setState(() {
                          _openMusicLoggedIn = true;
                        });
                      }

                      StatusMessageController.instance.showMessage(
                        'Library restored! Click "Let\'s go!" to continue',
                        duration: const Duration(seconds: 3),
                      );

                      // Don't navigate - stay on welcome page with checkmark
                    } catch (e) {
                      StatusMessageController.instance.showMessage(
                        'Failed to restore data: $e',
                        duration: const Duration(seconds: 3),
                      );
                    }
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const brandColor = Color(0xFF006A6A);

    return Scaffold(
      body: Stack(
        children: [
          // Solid teal background
          Container(width: size.width, height: size.height, color: brandColor),
          // Dotted pattern overlay
          Positioned.fill(
            child: CustomPaint(
              painter: DottedBackgroundPainter(
                dotColor: Colors.white.withValues(alpha: 0.15),
                dotRadius: 1.5,
                spacing: 24.0,
              ),
            ),
          ),
          // Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;
                final availableWidth = constraints.maxWidth;

                // Calculate responsive sizing
                final horizontalPadding = availableWidth * 0.08;
                final verticalPadding = availableHeight * 0.03;
                final titleFontSize = availableHeight * 0.04;
                final sectionPadding = availableHeight * 0.025;
                final stepSpacing = availableHeight * 0.015;
                final buttonHeight = availableHeight * 0.07;
                final buttonSpacing = availableHeight * 0.015;

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: availableHeight),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Welcome title
                          SizedBox(height: availableHeight * 0.015),
                          Text(
                            'Welcome!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: .3),
                                  offset: const Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: availableHeight * 0.02),

                          // How it works section
                          Container(
                            padding: EdgeInsets.all(sectionPadding),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .3),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'How does OpenMusic work?',
                                      style: TextStyle(
                                        fontSize: availableHeight * 0.025,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: stepSpacing * 1.5),
                                _buildStep(
                                  '1',
                                  'You search for a song',
                                  availableHeight,
                                ),
                                SizedBox(height: stepSpacing),
                                _buildStep(
                                  '2',
                                  'You choose a song',
                                  availableHeight,
                                ),
                                SizedBox(height: stepSpacing),
                                _buildStep(
                                  '3',
                                  'We download it directly to your device',
                                  availableHeight,
                                ),
                                SizedBox(height: stepSpacing),
                                _buildStep(
                                  '4',
                                  'Play it anytime, even offline!',
                                  availableHeight,
                                ),
                                SizedBox(height: stepSpacing * 1.5),
                                Container(
                                  padding: EdgeInsets.all(
                                    availableHeight * 0.015,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'All songs are downloaded to your device for offline playback. No streaming, no buffering - just instant music!',
                                    style: TextStyle(
                                      fontSize: availableHeight * 0.016,
                                      color: Colors.white.withValues(
                                        alpha: .95,
                                      ),
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: availableHeight * 0.03),

                          // First row: Let's go button
                          SizedBox(
                            height: buttonHeight,
                            child: ElevatedButton(
                              onPressed: widget.onGetStarted,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF006A6A),
                                elevation: 8,
                                shadowColor: Colors.black.withValues(alpha: .3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    buttonHeight * 0.5,
                                  ),
                                ),
                              ),
                              child: Text(
                                "Let's go!",
                                style: TextStyle(
                                  fontSize: availableHeight * 0.022,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: buttonSpacing),

                          // Login with OpenMusic button (full width)
                          SizedBox(
                            height: buttonHeight,
                            child: ElevatedButton(
                              onPressed: _handleOpenMusicLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF20B2AA,
                                ).withValues(alpha: 0.9),
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: Colors.black.withValues(alpha: .3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    buttonHeight * 0.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_openMusicLoggedIn)
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.white,
                                      size: buttonHeight * 0.4,
                                    )
                                  else
                                    Image.asset(
                                      'assets/Logo.png',
                                      width: buttonHeight * 0.4,
                                      height: buttonHeight * 0.4,
                                    ),
                                  SizedBox(width: availableWidth * 0.02),
                                  Text(
                                    _openMusicLoggedIn
                                        ? 'Logged In'
                                        : 'Login with OpenMusic',
                                    style: TextStyle(
                                      fontSize: availableHeight * 0.022,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(height: availableHeight * 0.03),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text, double availableHeight) {
    final circleSize = availableHeight * 0.035;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: availableHeight * 0.02,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF006A6A),
              ),
            ),
          ),
        ),
        SizedBox(width: availableHeight * 0.015),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: availableHeight * 0.02,
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
