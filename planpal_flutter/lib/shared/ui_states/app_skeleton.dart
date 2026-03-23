import 'package:flutter/material.dart';

enum AppSkeletonType { list, card, chat }

class AppSkeleton extends StatelessWidget {
  final AppSkeletonType type;
  final int itemCount;

  const AppSkeleton({
    super.key,
    this.type = AppSkeletonType.list,
    this.itemCount = 6,
  });

  const AppSkeleton.list({super.key, this.itemCount = 6})
    : type = AppSkeletonType.list;

  const AppSkeleton.card({super.key, this.itemCount = 1})
    : type = AppSkeletonType.card;

  const AppSkeleton.chat({super.key, this.itemCount = 8})
    : type = AppSkeletonType.chat;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case AppSkeletonType.card:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: const [_SkeletonCard()],
        );
      case AppSkeletonType.chat:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: itemCount,
          itemBuilder: (context, index) =>
              _SkeletonChatBubble(alignRight: index % 2 == 0),
        );
      case AppSkeletonType.list:
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => const _SkeletonCard(),
        );
    }
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withAlpha(70),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonLine(widthFactor: 0.55, height: 16),
          SizedBox(height: 10),
          _SkeletonLine(widthFactor: 0.9),
          SizedBox(height: 8),
          _SkeletonLine(widthFactor: 0.7),
        ],
      ),
    );
  }
}

class _SkeletonChatBubble extends StatelessWidget {
  final bool alignRight;

  const _SkeletonChatBubble({required this.alignRight});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        width: MediaQuery.of(context).size.width * (alignRight ? 0.5 : 0.65),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withAlpha(70),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const _SkeletonLine(widthFactor: 0.9),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _SkeletonLine({required this.widthFactor, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
