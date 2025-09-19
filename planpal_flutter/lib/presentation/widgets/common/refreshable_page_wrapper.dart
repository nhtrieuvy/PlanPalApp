import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Reusable wrapper widget that provides pull-to-refresh functionality
/// for any page content. Follows clean architecture principles and
/// maintains consistent UX across the app.
class RefreshablePageWrapper extends StatelessWidget {
  /// The child widget to be wrapped with refresh functionality
  final Widget child;

  /// Callback function to execute when user pulls to refresh
  final Future<void> Function() onRefresh;

  /// Optional background color for the page
  final Color? backgroundColor;

  /// Whether to show refresh indicator (default: true)
  final bool enableRefresh;

  /// Custom refresh indicator displacement from top
  final double displacement;

  /// Custom stroke width for the refresh indicator
  final double strokeWidth;

  const RefreshablePageWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
    this.backgroundColor,
    this.enableRefresh = true,
    this.displacement = 40.0,
    this.strokeWidth = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content = Container(
      color: backgroundColor ?? theme.scaffoldBackgroundColor,
      child: child,
    );

    // Only wrap with RefreshIndicator if refresh is enabled
    if (!enableRefresh) {
      return content;
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: displacement,
      strokeWidth: strokeWidth,
      backgroundColor: theme.cardColor,
      color: AppColors.primary,
      // Use a more subtle refresh indicator style
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      edgeOffset: 0.0,
      child: content,
    );
  }
}

/// Enhanced version with scroll controller and loading state management
class RefreshableScrollView extends StatefulWidget {
  /// The scrollable child widget
  final Widget child;

  /// Callback function to execute when user pulls to refresh
  final Future<void> Function() onRefresh;

  /// Optional scroll controller
  final ScrollController? controller;

  /// Physics for the scroll view
  final ScrollPhysics? physics;

  /// Whether to show refresh indicator
  final bool enableRefresh;

  /// Background color
  final Color? backgroundColor;

  const RefreshableScrollView({
    super.key,
    required this.child,
    required this.onRefresh,
    this.controller,
    this.physics,
    this.enableRefresh = true,
    this.backgroundColor,
  });

  @override
  State<RefreshableScrollView> createState() => _RefreshableScrollViewState();
}

class _RefreshableScrollViewState extends State<RefreshableScrollView> {
  late ScrollController _scrollController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
  }

  @override
  void dispose() {
    // Only dispose if we created the controller
    if (widget.controller == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content = Container(
      color: widget.backgroundColor ?? theme.scaffoldBackgroundColor,
      child: widget.child,
    );

    if (!widget.enableRefresh) {
      return content;
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      displacement: 40.0,
      strokeWidth: 2.0,
      backgroundColor: theme.cardColor,
      color: AppColors.primary,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      child: content,
    );
  }
}

/// Mixin for pages that need refresh functionality
/// Provides common refresh patterns and error handling
mixin RefreshablePage<T extends StatefulWidget> on State<T> {
  /// Whether the page is currently refreshing
  bool get isRefreshing => _isRefreshing;
  bool _isRefreshing = false;

  /// Set refresh state
  @protected
  void setRefreshing(bool refreshing) {
    if (_isRefreshing != refreshing && mounted) {
      setState(() {
        _isRefreshing = refreshing;
      });
    }
  }

  /// Execute refresh with error handling
  @protected
  Future<void> executeRefresh(Future<void> Function() refreshFunction) async {
    if (_isRefreshing) return;

    setRefreshing(true);

    try {
      await refreshFunction();
    } catch (e) {
      // Handle refresh errors gracefully
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể làm mới: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      setRefreshing(false);
    }
  }

  /// Common refresh callback pattern
  Future<void> onRefresh();
}
