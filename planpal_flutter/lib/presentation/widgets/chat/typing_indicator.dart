import 'dart:math' as math;
import 'package:flutter/material.dart';
// removed color_utils; use withAlpha directly
import 'package:google_fonts/google_fonts.dart';

class TypingIndicator extends StatefulWidget {
  final List<String> typingUsers;
  final bool isVisible;

  const TypingIndicator({
    super.key,
    required this.typingUsers,
    this.isVisible = true,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<double>(begin: -20.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutQuart),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isVisible && widget.typingUsers.isNotEmpty) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  String _getTypingText() {
    if (widget.typingUsers.isEmpty) return '';

    if (widget.typingUsers.length == 1) {
      return '${widget.typingUsers.first} đang nhập...';
    } else if (widget.typingUsers.length == 2) {
      return '${widget.typingUsers.first} và ${widget.typingUsers.last} đang nhập...';
    } else {
      return '${widget.typingUsers.first} và ${widget.typingUsers.length - 1} người khác đang nhập...';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || widget.typingUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Avatar space
                  const SizedBox(width: 40),

                  // Typing bubble
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(13),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getTypingText(),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildTypingAnimation(),
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
    );
  }

  Widget _buildTypingAnimation() {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 24,
      height: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (index) {
          return _buildTypingDot(
            index,
            colorScheme.surfaceContainerHighest.withAlpha(150),
          );
        }),
      ),
    );
  }

  Widget _buildTypingDot(int index, Color color) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        // Create a staggered animation for each dot
        final delay = index * 0.15;
        final animationValue = (_animationController.value + delay) % 1.0;

        // Create a bounce effect
        final scale =
            0.5 + (0.5 * (1 + math.cos(animationValue * 2 * math.pi)) / 2);

        return Transform.scale(
          scale: scale,
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}

// Typing dots animation widget that can be used independently
class TypingDots extends StatefulWidget {
  final Color? color;
  final double size;
  final Duration duration;

  const TypingDots({
    super.key,
    this.color,
    this.size = 4.0,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(150);

    return SizedBox(
      width: widget.size * 6,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (index) {
              final delay = index * 0.15;
              final animationValue = (_controller.value + delay) % 1.0;

              // Smooth bounce animation
              final scale =
                  0.3 +
                  (0.7 * (1 + math.cos(animationValue * 2 * math.pi)) / 2);

              return Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
