import 'package:flutter/material.dart';

class AppSliverHeader extends StatelessWidget {
  final String title;
  final double expandedHeight;
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget? background;
  final List<Widget>? actions;

  const AppSliverHeader({
    super.key,
    required this.title,
    this.expandedHeight = 200,
    this.backgroundColor = Colors.blue,
    this.foregroundColor = Colors.white,
    this.background,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      actions: actions,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        background: background,
      ),
    );
  }
}
