import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/experience_models.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/conversation_providers.dart';
import 'package:planpal_flutter/core/riverpod/experience_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/pages/chat/conversation_list_page.dart';
import 'package:planpal_flutter/presentation/pages/chat/chat_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  GlobalSearchResult? _result;
  Object? _error;
  bool _loading = false;
  int _requestVersion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _result = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(experienceRepositoryProvider).search(query);
      if (!mounted || version != _requestVersion) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() => _error = error);
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.t('search.title'))),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _controller,
            hintText: context.l10n.t('search.hint'),
            leading: const Icon(Icons.search),
            trailing: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _controller.clear();
                    _onChanged('');
                  },
                  icon: const Icon(Icons.close),
                ),
            ],
            onChanged: (value) {
              setState(() {});
              _onChanged(value);
            },
            onSubmitted: _search,
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _content()),
      ],
    ),
  );

  Widget _content() {
    if (_error != null) {
      return AppError(
        message: ErrorDisplayService.getUserFriendlyMessage(_error!),
        onRetry: () => _search(_controller.text),
        retryLabel: context.l10n.t('common.retry'),
      );
    }
    if (_controller.text.trim().length < 2) {
      return AppEmpty(
        icon: Icons.manage_search,
        title: context.l10n.t('search.start_title'),
        description: context.l10n.t('search.start_hint'),
      );
    }
    final items = _result?.items ?? const <SearchResultItem>[];
    if (!_loading && items.isEmpty) {
      return AppEmpty(
        icon: Icons.search_off,
        title: context.l10n.t('search.empty_title'),
        description: context.l10n.t('search.empty_hint'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final item = items[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(_icon(item.type))),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.subtitle.isEmpty
                ? Text(context.l10n.t('search.${item.type}'))
                : Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(item),
          ),
        );
      },
    );
  }

  IconData _icon(String type) => switch (type) {
    'plan' => Icons.event_note_outlined,
    'group' => Icons.groups_outlined,
    _ => Icons.chat_bubble_outline,
  };

  Future<void> _open(SearchResultItem item) async {
    if (item.type == 'plan') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PlanDetailsPage(id: item.id)));
      return;
    }
    if (item.type == 'group') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => GroupDetailsPage(id: item.id)));
      return;
    }
    try {
      final conversation = await ref
          .read(conversationRepositoryProvider)
          .getConversation(item.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatPage(conversation: conversation)),
      );
    } catch (_) {
      if (!mounted) return;
      ref.invalidate(conversationListProvider);
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ConversationListPage()));
    }
  }
}
