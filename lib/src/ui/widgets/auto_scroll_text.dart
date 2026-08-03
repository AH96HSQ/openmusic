import 'package:flutter/material.dart';

/// A text widget that automatically scrolls back and forth horizontally
/// when the text is longer than the available width.
/// User can grab and manually scroll, which pauses auto-scroll temporarily.
class AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration scrollDuration;
  final Duration pauseDuration;

  const AutoScrollText({
    super.key,
    required this.text,
    this.style,
    this.scrollDuration = const Duration(seconds: 3),
    this.pauseDuration = const Duration(seconds: 1),
  });

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animationController;
  bool _isUserScrolling = false;
  bool _needsScrolling = false;
  double _maxScrollExtent = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.scrollDuration,
    );

    // Wait for first frame to measure if scrolling is needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfScrollingNeeded();
    });

    // Listen to scroll events to detect user interaction
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _animationController.stop();
      _animationController.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkIfScrollingNeeded();
      });
    }
  }

  void _checkIfScrollingNeeded() {
    if (!mounted) return;

    if (_scrollController.hasClients) {
      _maxScrollExtent = _scrollController.position.maxScrollExtent;
      _needsScrolling = _maxScrollExtent > 0;

      if (_needsScrolling && !_isUserScrolling) {
        _startAutoScroll();
      }
    }
  }

  void _onScroll() {
    // This listener is primarily for detecting manual scroll changes
    // User interaction is mainly detected via GestureDetector
  }

  void _startAutoScroll() async {
    if (!mounted || !_needsScrolling || _isUserScrolling) return;

    await Future.delayed(widget.pauseDuration);
    if (!mounted || _isUserScrolling) return;

    while (mounted && !_isUserScrolling && _needsScrolling) {
      // Scroll to end
      _animationController.reset();
      _animationController.duration = widget.scrollDuration;
      final animation = Tween<double>(begin: 0.0, end: _maxScrollExtent)
          .animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeInOut,
            ),
          );

      animation.addListener(() {
        if (_scrollController.hasClients && !_isUserScrolling) {
          _scrollController.jumpTo(animation.value);
        }
      });

      await _animationController.forward();
      if (!mounted || _isUserScrolling) break;

      await Future.delayed(widget.pauseDuration);
      if (!mounted || _isUserScrolling) break;

      // Scroll back to start
      _animationController.reset();
      final reverseAnimation = Tween<double>(begin: _maxScrollExtent, end: 0.0)
          .animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeInOut,
            ),
          );

      reverseAnimation.addListener(() {
        if (_scrollController.hasClients && !_isUserScrolling) {
          _scrollController.jumpTo(reverseAnimation.value);
        }
      });

      await _animationController.forward();
      if (!mounted || _isUserScrolling) break;

      await Future.delayed(widget.pauseDuration);
    }
  }

  void _onUserInteractionEnd() {
    // Resume auto-scroll after user stops interacting
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isUserScrolling = false;
        });
        _startAutoScroll();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (_) {
        if (!_isUserScrolling) {
          setState(() {
            _isUserScrolling = true;
          });
          _animationController.stop();
        }
      },
      onPanEnd: (_) => _onUserInteractionEnd(),
      onPanCancel: () => _onUserInteractionEnd(),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Text(widget.text, style: widget.style, maxLines: 1),
      ),
    );
  }
}
