import 'package:flutter/material.dart';

class AppLoading extends StatelessWidget {
  final String? message;
  final bool inline;
  final EdgeInsetsGeometry padding;
  final double size;

  const AppLoading({
    super.key,
    this.message,
    this.inline = false,
    this.padding = const EdgeInsets.all(16),
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2.5),
    );

    if (inline) {
      return Padding(
        padding: padding,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            spinner,
            if (message != null) ...[
              const SizedBox(width: 10),
              Flexible(child: Text(message!)),
            ],
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            spinner,
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
