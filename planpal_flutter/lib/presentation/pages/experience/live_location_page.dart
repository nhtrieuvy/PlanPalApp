import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:planpal_flutter/core/dtos/experience_models.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/maps/planpal_map.dart';
import 'package:planpal_flutter/core/platform/platform_capabilities.dart';
import 'package:planpal_flutter/core/riverpod/experience_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/widgets/forms/app_select_field.dart';

class LiveLocationPage extends ConsumerStatefulWidget {
  const LiveLocationPage({
    super.key,
    required this.conversationId,
    required this.conversationName,
  });

  final String conversationId;
  final String conversationName;

  @override
  ConsumerState<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends ConsumerState<LiveLocationPage> {
  static const _fallback = MapCoordinate(10.762622, 106.660172);
  PlanPalMapController? _map;
  StreamSubscription<Position>? _positions;
  Timer? _refreshTimer;
  String? _myShareId;
  DateTime? _lastSentAt;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.invalidate(liveLocationsProvider(widget.conversationId));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _positions?.cancel();
    final shareId = _myShareId;
    if (shareId != null) {
      unawaited(
        ref.read(experienceRepositoryProvider).stopLiveLocation(shareId),
      );
    }
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(liveLocationsProvider(widget.conversationId));
    final items = locations.valueOrNull ?? const <LiveLocationModel>[];
    final markers = {
      for (final item in items)
        MapPin(
          id: item.id,
          position: MapCoordinate(item.latitude, item.longitude),
          title: item.userName,
          subtitle: context.l10n.t('live_location.active'),
        ),
    };
    final initial = items.isEmpty
        ? _fallback
        : MapCoordinate(items.first.latitude, items.first.longitude);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.t('live_location.title')),
        actions: [
          IconButton(
            onPressed: () =>
                ref.invalidate(liveLocationsProvider(widget.conversationId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          PlanPalMap(
            initialCameraPosition: MapCameraPosition(target: initial, zoom: 14),
            pins: markers,
            myLocationEnabled: _myShareId != null,
            onMapCreated: (controller) => _map = controller,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _myShareId == null
                            ? context.l10n.t('live_location.privacy_hint')
                            : context.l10n.t('live_location.sharing_hint'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (locations.isLoading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _starting
            ? null
            : (_myShareId == null ? _requestStart : _stop),
        backgroundColor: _myShareId == null
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
        foregroundColor: _myShareId == null
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onError,
        icon: Icon(_myShareId == null ? Icons.location_on : Icons.stop_circle),
        label: Text(
          context.l10n.t(
            _myShareId == null ? 'live_location.start' : 'live_location.stop',
          ),
        ),
      ),
    );
  }

  Future<void> _requestStart() async {
    final serviceDisabledMessage = context.l10n.t(
      'live_location.service_disabled',
    );
    final permissionDeniedMessage = context.l10n.t(
      'live_location.permission_denied',
    );
    final duration = await showDialog<int>(
      context: context,
      builder: (context) => const _LiveLocationConsentDialog(),
    );
    if (duration == null || !mounted) return;
    setState(() => _starting = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(serviceDisabledMessage);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(permissionDeniedMessage);
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      final share = await ref
          .read(experienceRepositoryProvider)
          .startLiveLocation(widget.conversationId, {
            'latitude': position.latitude.toStringAsFixed(6),
            'longitude': position.longitude.toStringAsFixed(6),
            'accuracy_meters': position.accuracy.toStringAsFixed(2),
            'duration_minutes': duration,
            'consent': true,
          });
      if (!mounted) return;
      if (share == null) {
        ErrorDisplayService.showWarningSnackbar(
          context,
          context.l10n.t('offline.queued'),
        );
        return;
      }
      setState(() => _myShareId = share.id);
      _map?.animateCamera(
        MapCameraUpdate.newCoordinateZoom(
          MapCoordinate(position.latitude, position.longitude),
          16,
        ),
      );
      _positions = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen(_updatePosition);
      ref.invalidate(liveLocationsProvider(widget.conversationId));
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          PlatformCapabilities.locationRequiresSecureContext
              ? context.l10n.t('map.web_location_requirements')
              : ErrorDisplayService.getUserFriendlyMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _updatePosition(Position position) async {
    final shareId = _myShareId;
    if (shareId == null) return;
    final now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!).inSeconds < 8) {
      return;
    }
    _lastSentAt = now;
    try {
      await ref.read(experienceRepositoryProvider).updateLiveLocation(shareId, {
        'latitude': position.latitude.toStringAsFixed(6),
        'longitude': position.longitude.toStringAsFixed(6),
        'accuracy_meters': position.accuracy.toStringAsFixed(2),
      });
      ref.invalidate(liveLocationsProvider(widget.conversationId));
    } catch (_) {
      // The repository queues transport failures; the next position retries.
    }
  }

  Future<void> _stop() async {
    final shareId = _myShareId;
    if (shareId == null) return;
    await _positions?.cancel();
    _positions = null;
    try {
      await ref.read(experienceRepositoryProvider).stopLiveLocation(shareId);
      if (!mounted) return;
      setState(() => _myShareId = null);
      ref.invalidate(liveLocationsProvider(widget.conversationId));
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          ErrorDisplayService.getUserFriendlyMessage(error),
        );
      }
    }
  }
}

class _LiveLocationConsentDialog extends StatefulWidget {
  const _LiveLocationConsentDialog();

  @override
  State<_LiveLocationConsentDialog> createState() =>
      _LiveLocationConsentDialogState();
}

class _LiveLocationConsentDialogState
    extends State<_LiveLocationConsentDialog> {
  int _duration = 60;
  bool _consent = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.t('live_location.consent_title')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.t('live_location.consent_body')),
        const SizedBox(height: 12),
        AppSelectField<int>(
          label: context.l10n.t('live_location.duration'),
          value: _duration,
          options: const [15, 30, 60, 120, 480]
              .map(
                (value) => AppSelectOption(
                  value: value,
                  label: context.l10n.t(
                    'live_location.minutes',
                    params: {'count': '$value'},
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _duration = value),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _consent,
          onChanged: (value) => setState(() => _consent = value == true),
          title: Text(context.l10n.t('live_location.consent_checkbox')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.t('common.cancel')),
      ),
      FilledButton(
        onPressed: _consent ? () => Navigator.pop(context, _duration) : null,
        child: Text(context.l10n.t('live_location.start')),
      ),
    ],
  );
}
