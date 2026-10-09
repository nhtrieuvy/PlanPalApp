import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/riverpod/repository_providers.dart';
import '../../../core/dtos/user_summary.dart';
import '../../../core/services/error_display_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../widgets/design_system/journey_ui.dart';
import '../../widgets/layout/responsive_content.dart';
import '../../../shared/ui_states/ui_states.dart';
import 'user_profile_page.dart';

class FriendSearchPage extends ConsumerStatefulWidget {
  const FriendSearchPage({super.key});

  @override
  ConsumerState<FriendSearchPage> createState() => _FriendSearchPageState();
}

class _FriendSearchPageState extends ConsumerState<FriendSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  bool _searching = false;
  String? _searchError;
  List<UserSummary> _searchResults = [];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final generation = ++_searchGeneration;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final results = await ref
          .read(friendRepositoryProvider)
          .searchUsers(query.trim());
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _searching = false;
        _searchError = null;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = [];
        _searching = false;
        _searchError = ErrorDisplayService.getUserFriendlyMessage(error);
      });
    }
  }

  void _onUserTap(UserSummary user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UserProfilePage(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('friend_search.title'))),
      body: ResponsiveContent(
        mediumMaxWidth: 760,
        expandedMaxWidth: 920,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.t('friend_search.hint'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          tooltip: context.l10n.t('common.clear'),
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchController.clear();
                            _performSearch('');
                            setState(() {});
                          },
                        )
                      : null,
                ),
                style: theme.textTheme.bodyLarge,
                onChanged: (value) {
                  setState(() {});
                  _searchDebounce?.cancel();
                  final query = value.trim();
                  if (query.length < 2) {
                    _performSearch('');
                  } else {
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 300),
                      () => _performSearch(query),
                    );
                  }
                },
                onSubmitted: (query) {
                  _searchDebounce?.cancel();
                  _performSearch(query);
                },
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return AppLoading(message: context.l10n.t('friend_search.searching'));
    }

    if (_searchController.text.trim().isEmpty) {
      return _buildEmptyState();
    }

    if (_searchError != null) {
      return AppError(
        message: _searchError!,
        onRetry: () => _performSearch(_searchController.text.trim()),
        retryLabel: context.l10n.t('common.retry'),
      );
    }

    if (_searchResults.isEmpty) {
      return _buildNoResults();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _buildUserTile(user);
      },
    );
  }

  Widget _buildEmptyState() {
    return AppEmpty(
      icon: Icons.person_search_rounded,
      title: context.l10n.t('friend_search.empty_title'),
      description: context.l10n.t('friend_search.empty_description'),
    );
  }

  Widget _buildNoResults() {
    return AppEmpty(
      icon: Icons.search_off_rounded,
      title: context.l10n.t('friend_search.no_results'),
      description: context.l10n.t('friend_search.try_another'),
    );
  }

  Widget _buildUserTile(UserSummary user) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: JourneySurface(
        padding: EdgeInsets.zero,
        onTap: () => _onUserTap(user),
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: _buildAvatar(user),
          title: Text(
            user.fullName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@${user.username}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (user.isOnline)
                Text(
                  context.l10n.t('friends.online'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.success),
                ),
            ],
          ),
          trailing: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(UserSummary user) {
    final initials = user.initials;
    final avatarUrl = user.avatarForDisplay;

    if (avatarUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 48,
            height: 48,
            color: AppColors.primary.withValues(alpha: 0.1),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
