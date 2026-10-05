import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/maps/planpal_map.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';

/// Read-only location viewer backed by the shared Goong/MapLibre map adapter.
class LocationViewPage extends StatelessWidget {
  const LocationViewPage({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String title;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = MapCoordinate(latitude, longitude);
    final displayAddress = address?.trim().isNotEmpty == true
        ? address!.trim()
        : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('map.title'))),
      body: Stack(
        children: [
          Positioned.fill(
            child: PlanPalMap(
              initialCameraPosition: MapCameraPosition(
                target: position,
                zoom: 16,
              ),
              pins: {
                MapPin(
                  id: 'location',
                  position: position,
                  title: title,
                  subtitle: displayAddress,
                ),
              },
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: SafeArea(
              top: false,
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              displayAddress,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
