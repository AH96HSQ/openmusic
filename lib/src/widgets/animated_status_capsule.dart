import 'package:flutter/material.dart';
import '../services/status_message_controller.dart';

/// Animated status capsule that morphs from circle to capsule shape
/// Displays status messages with smooth expand/collapse animations
class AnimatedStatusCapsule extends StatefulWidget {
  final String? message;
  final Color backgroundColor;
  final Color textColor;
  final double bottomPadding;
  final Duration animationDuration;

  const AnimatedStatusCapsule({
    super.key,
    this.message,
    required this.backgroundColor,
    required this.textColor,
    this.bottomPadding = 8.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<AnimatedStatusCapsule> createState() => _AnimatedStatusCapsuleState();
}

class _AnimatedStatusCapsuleState extends State<AnimatedStatusCapsule>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _widthController;
  late AnimationController _rotationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _widthAnimation;
  late Animation<double> _heightAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    // Main controller for overall show/hide
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200), // Slower start animation
      vsync: this,
    );

    // Width controller for circle-to-capsule morphing
    _widthController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Rotation controller for loading border animation
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Rotation animation for loading border
    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    // Scale animation for pop-in/pop-out effect
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.elasticOut),
      ),
    );

    // Opacity animation
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
      ),
    );

    // Width animation for circle to capsule expansion
    _widthAnimation =
        Tween<double>(
          begin: 44.0, // Start as circle (same height)
          end: 200.0, // Default width, will be updated dynamically
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
          ),
        );

    // Height stays constant
    _heightAnimation = Tween<double>(
      begin: 44.0,
      end: 44.0,
    ).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedStatusCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.message != oldWidget.message) {
      if (widget.message != null && widget.message!.isNotEmpty) {
        // Check if this is just a progress update (same prefix, different percentage)
        final isProgressUpdate = _isProgressUpdate(
          oldWidget.message,
          widget.message,
        );

        // Update width and height animation end values for new message
        final targetWidth = _calculateCapsuleWidth(widget.message!, context);
        final targetHeight = _calculateCapsuleHeight(widget.message!, context);

        _widthAnimation = Tween<double>(begin: 44.0, end: targetWidth).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
          ),
        );

        _heightAnimation = Tween<double>(begin: 44.0, end: targetHeight)
            .animate(
              CurvedAnimation(
                parent: _controller,
                curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
              ),
            );

        // Only reset animation if this is NOT a progress update
        if (!isProgressUpdate) {
          // Show capsule with opening animation sequence
          _controller.reset();
          _controller.forward();
        }

        // Start rotation animation for "Trying" messages (e.g., "Trying SRA", "2/5 Trying DSRA")
        if (widget.message!.contains('Trying ')) {
          _rotationController.repeat();
        } else {
          _rotationController.stop();
        }
      } else {
        // Hide capsule with closing animation (reverse)
        _controller.reverse();
        _rotationController.stop();
      }
    }
  }

  /// Check if the message change is just a progress update
  /// or a transition into/within download progress mode
  bool _isProgressUpdate(String? oldMessage, String? newMessage) {
    if (oldMessage == null || newMessage == null) return false;

    // Check if both are "Trying" messages (e.g., "1/1 Trying SRA", "2/5 Trying DSRA")
    if (oldMessage.contains('Trying ') && newMessage.contains('Trying ')) {
      return true;
    }

    // Check if transitioning from "Trying..." to "Downloading..."
    if (oldMessage.contains('Trying ') &&
        newMessage.startsWith('Downloading ')) {
      return true;
    }

    // Check if both are download progress messages (e.g., "Downloading 1/5: Song Title")
    if (oldMessage.startsWith('Downloading ') &&
        newMessage.startsWith('Downloading ')) {
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _controller.dispose();
    _widthController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  double _calculateCapsuleWidth(String text, BuildContext context) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: widget.textColor,
        ),
      ),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: MediaQuery.of(context).size.width - 104);

    // Add padding: 16px left + 40px for X button + space + 16px right = 72px total
    final calculatedWidth = textPainter.width + 72;

    // Get screen width and add some margin (16px on each side)
    final screenWidth = MediaQuery.of(context).size.width - 32;

    // Return the smaller of calculated width or max screen width
    return calculatedWidth.clamp(100.0, screenWidth);
  }

  double _calculateCapsuleHeight(String text, BuildContext context) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: widget.textColor,
        ),
      ),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: MediaQuery.of(context).size.width - 104);

    // Add vertical padding: 8px top + 8px bottom = 16px total
    final calculatedHeight = textPainter.height + 16;

    // Return height with min/max constraints
    return calculatedHeight.clamp(44.0, 120.0);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;

    if (message == null || message.isEmpty) {
      return SizedBox(height: widget.bottomPadding);
    }

    // Check if this is a "trying" message that should show loading border
    // Matches "Trying SRA", "2/5 Trying DSRA", etc.
    final isTryingMessage = message.contains('Trying ');
    // Check if this is a downloading/progress message that should show progress bar
    // Matches "Downloading", "Downloading 1/5: Song", or Trying messages (which also have progress)
    final isProgressMessage =
        message == 'Downloading' ||
        message.startsWith('Downloading ') ||
        isTryingMessage;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _controller,
          _widthController,
          _rotationController,
        ]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Loading border (for "Trying to Download" messages)
                    if (isTryingMessage)
                      CustomPaint(
                        size: Size(
                          _widthAnimation.value,
                          _heightAnimation.value,
                        ),
                        painter: LoadingBorderPainter(
                          progress: _rotationAnimation.value,
                          borderColor: widget.textColor.withValues(alpha: 0.3),
                          borderRadius: _heightAnimation.value / 2,
                        ),
                      ),
                    // Main capsule container with progress bar background
                    Container(
                      width: _widthAnimation.value,
                      height: _heightAnimation.value.clamp(44.0, 120.0),
                      constraints: const BoxConstraints(
                        minHeight: 44.0,
                        maxHeight: 120.0,
                      ),
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        borderRadius: BorderRadius.circular(
                          _heightAnimation.value / 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          _heightAnimation.value / 2,
                        ),
                        child: Stack(
                          children: [
                            // Progress bar background fill (for downloading and trying messages)
                            if (isProgressMessage)
                              AnimatedBuilder(
                                animation: StatusMessageController.instance,
                                builder: (context, _) {
                                  final progress =
                                      StatusMessageController.instance.progress;
                                  return Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: _widthAnimation.value * progress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: widget.textColor.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            // Content overlay
                            if (_widthAnimation.value > 100)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: DefaultTextStyle.merge(
                                        style: const TextStyle(
                                          decoration: TextDecoration.none,
                                        ),
                                        child: Text(
                                          message,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: widget.textColor,
                                            decoration: TextDecoration.none,
                                            inherit: false,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    // Larger touch area (40x40) with visual size (24x24)
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        StatusMessageController.instance
                                            .smoothExit();
                                      },
                                      onTapDown: (details) {},
                                      onTapUp: (details) {},
                                      onTapCancel: () {},
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        color: Colors.transparent,
                                        child: Center(
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: widget.textColor
                                                  .withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.close,
                                              size: 16,
                                              color: widget.textColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Custom painter for rotating border animation
class LoadingBorderPainter extends CustomPainter {
  final double progress;
  final Color borderColor;
  final double borderRadius;

  LoadingBorderPainter({
    required this.progress,
    required this.borderColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Create a path for the rounded rectangle border
    final path = Path()..addRRect(rrect);

    // Calculate the path metrics to get the total length
    final pathMetrics = path.computeMetrics().first;
    final totalLength = pathMetrics.length;

    // Draw half the border (50% of total circumference)
    final halfLength = totalLength * 0.5;
    final startDistance = (progress * totalLength) % totalLength;

    // Extract the path segment for the rotating half-border
    final extractedPath = pathMetrics.extractPath(
      startDistance,
      (startDistance + halfLength) % totalLength == (startDistance + halfLength)
          ? startDistance + halfLength
          : totalLength,
    );

    // If the border wraps around, draw the remaining part
    if ((startDistance + halfLength) > totalLength) {
      final remainingLength = (startDistance + halfLength) - totalLength;
      final wrappedPath = pathMetrics.extractPath(0, remainingLength);
      extractedPath.addPath(wrappedPath, Offset.zero);
    }

    canvas.drawPath(extractedPath, paint);
  }

  @override
  bool shouldRepaint(LoadingBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}
