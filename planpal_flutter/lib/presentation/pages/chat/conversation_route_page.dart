import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/conversation.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/presentation/pages/chat/chat_page.dart';

class ConversationRoutePage extends ConsumerStatefulWidget {
  const ConversationRoutePage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationRoutePage> createState() =>
      _ConversationRoutePageState();
}

class _ConversationRoutePageState extends ConsumerState<ConversationRoutePage> {
  late Future<Conversation> _conversation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _conversation = ref
        .read(conversationRepositoryProvider)
        .getConversation(widget.conversationId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Conversation>(
      future: _conversation,
      builder: (context, snapshot) {
        if (snapshot.hasData) return ChatPage(conversation: snapshot.data!);
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: FilledButton.icon(
                onPressed: () => setState(_load),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.t('common.retry')),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
