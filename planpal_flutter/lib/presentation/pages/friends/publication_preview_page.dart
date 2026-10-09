import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

class PublicationPreviewPage extends ConsumerStatefulWidget {
  const PublicationPreviewPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PublicationPreviewPage> createState() =>
      _PublicationPreviewPageState();
}

class _PublicationPreviewPageState
    extends ConsumerState<PublicationPreviewPage> {
  late Future<Map<String, dynamic>> _publication;

  @override
  void initState() {
    super.initState();
    _publication = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      ref.read(friendRepositoryProvider).getPublicationPreview(widget.id);

  void _retry() => setState(() => _publication = _load());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('published.journey'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _publication,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.t('common.retry')),
              ),
            );
          }
          final data = snapshot.data!;
          final highlights = data['highlights'] as List? ?? const [];
          return ResponsiveContent(
            mediumMaxWidth: 720,
            expandedMaxWidth: 800,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  JourneySurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['destination']?.toString() ?? '',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          data['title']?.toString() ?? '',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(data['summary']?.toString() ?? ''),
                      ],
                    ),
                  ),
                  if (highlights.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      l10n.t('published.highlights'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...highlights.map((item) {
                      final highlight = Map<String, dynamic>.from(item as Map);
                      return ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(highlight['title']?.toString() ?? ''),
                        subtitle: (highlight['place']?.toString() ?? '').isEmpty
                            ? null
                            : Text(highlight['place'].toString()),
                      );
                    }),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlanFormPage(
                          initial: {
                            'title': data['title'],
                            'description': data['summary'],
                            'plan_type': 'personal',
                            'is_public': false,
                            'source_publication_id': data['id'],
                          },
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l10n.t('published.use_inspiration')),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.t('published.inspiration_hint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
