import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:planpal_flutter/core/localization/app_localizations.dart';

/// Provider-neutral coordinate used by PlanPal presentation code.
class MapCoordinate {
  const MapCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  maplibre.LatLng get native => maplibre.LatLng(latitude, longitude);
}

class MapPin {
  const MapPin({
    required this.id,
    required this.position,
    this.title,
    this.subtitle,
    this.draggable = false,
    this.onDragEnd,
  });

  final String id;
  final MapCoordinate position;
  final String? title;
  final String? subtitle;
  final bool draggable;
  final ValueChanged<MapCoordinate>? onDragEnd;

  @override
  bool operator ==(Object other) => other is MapPin && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MapCameraPosition {
  const MapCameraPosition({required this.target, required this.zoom});

  final MapCoordinate target;
  final double zoom;
}

enum _MapCameraUpdateType { coordinate, coordinateZoom, zoomIn, zoomOut }

class MapCameraUpdate {
  const MapCameraUpdate._(this._type, {this.coordinate, this.zoom});

  final _MapCameraUpdateType _type;
  final MapCoordinate? coordinate;
  final double? zoom;

  factory MapCameraUpdate.newCoordinate(MapCoordinate coordinate) =>
      MapCameraUpdate._(
        _MapCameraUpdateType.coordinate,
        coordinate: coordinate,
      );

  factory MapCameraUpdate.newCoordinateZoom(
    MapCoordinate coordinate,
    double zoom,
  ) => MapCameraUpdate._(
    _MapCameraUpdateType.coordinateZoom,
    coordinate: coordinate,
    zoom: zoom,
  );

  factory MapCameraUpdate.zoomIn() =>
      const MapCameraUpdate._(_MapCameraUpdateType.zoomIn);

  factory MapCameraUpdate.zoomOut() =>
      const MapCameraUpdate._(_MapCameraUpdateType.zoomOut);
}

class PlanPalMapController {
  PlanPalMapController._(this._native);

  final maplibre.MapLibreMapController _native;

  Future<void> animateCamera(MapCameraUpdate update) {
    final nativeUpdate = switch (update._type) {
      _MapCameraUpdateType.coordinate => maplibre.CameraUpdate.newLatLng(
        update.coordinate!.native,
      ),
      _MapCameraUpdateType.coordinateZoom =>
        maplibre.CameraUpdate.newLatLngZoom(
          update.coordinate!.native,
          update.zoom!,
        ),
      _MapCameraUpdateType.zoomIn => maplibre.CameraUpdate.zoomIn(),
      _MapCameraUpdateType.zoomOut => maplibre.CameraUpdate.zoomOut(),
    };
    return _native.animateCamera(nativeUpdate);
  }

  // The native controller is owned and disposed by MapLibreMap.
  void dispose() {}
}

class PlanPalMap extends StatefulWidget {
  const PlanPalMap({
    super.key,
    required this.initialCameraPosition,
    this.pins = const <MapPin>{},
    this.onMapCreated,
    this.onTap,
    this.myLocationEnabled = false,
    this.compassEnabled = true,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.rotateGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
  });

  final MapCameraPosition initialCameraPosition;
  final Set<MapPin> pins;
  final ValueChanged<PlanPalMapController>? onMapCreated;
  final ValueChanged<MapCoordinate>? onTap;
  final bool myLocationEnabled;
  final bool compassEnabled;
  final bool scrollGesturesEnabled;
  final bool zoomGesturesEnabled;
  final bool rotateGesturesEnabled;
  final bool tiltGesturesEnabled;

  @override
  State<PlanPalMap> createState() => _PlanPalMapState();
}

class _PlanPalMapState extends State<PlanPalMap> {
  static const _markerImage = 'planpal-map-pin';

  maplibre.MapLibreMapController? _native;
  bool _styleLoaded = false;
  bool _loadFailed = false;
  bool _markerInstalled = false;
  int _renderVersion = 0;
  int _mapRevision = 0;
  Timer? _loadWatchdog;
  final Map<String, MapPin> _pinBySymbolId = {};

  String get _mapTilesKey => dotenv.env['GOONG_MAPTILES_KEY']?.trim() ?? '';

  String get _styleUrl =>
      // Goong's documented mobile/reference street style is the most reliable
      // option across physical Android devices and emulators. PlanPal layers
      // its own theme-aware controls above it instead of relying on a native
      // dark style that may not load on older renderer builds.
      'https://tiles.goong.io/assets/goong_map_web.json?api_key=$_mapTilesKey';

  @override
  void initState() {
    super.initState();
    _armLoadWatchdog();
  }

  @override
  void dispose() {
    _loadWatchdog?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlanPalMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A Set compares by identity, so checking it directly caused a second
    // annotation render after every parent rebuild, including style loading.
    // Compare stable pin data instead to avoid racing clear/add operations.
    if (_styleLoaded && _pinsSignature(oldWidget.pins) != _pinsSignature(widget.pins)) {
      unawaited(_renderPins());
    }
  }

  String _pinsSignature(Set<MapPin> pins) {
    final entries = pins
        .map(
          (pin) =>
              '${pin.id}:${pin.position.latitude}:${pin.position.longitude}:'
              '${pin.title ?? ''}:${pin.subtitle ?? ''}:${pin.draggable}',
        )
        .toList()
      ..sort();
    return entries.join('|');
  }

  @override
  Widget build(BuildContext context) {
    if (_mapTilesKey.isEmpty) {
      return _MapConfigurationState(
        title: context.l10n.t('map.configuration_title'),
        message: context.l10n.t('map.configuration_message'),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: maplibre.MapLibreMap(
            key: ValueKey(_mapRevision),
            styleString: _styleUrl,
            initialCameraPosition: maplibre.CameraPosition(
              target: widget.initialCameraPosition.target.native,
              zoom: widget.initialCameraPosition.zoom,
            ),
            onMapCreated: _handleMapCreated,
            onStyleLoadedCallback: _handleStyleLoaded,
            onMapClick: (_, coordinate) => widget.onTap?.call(
              MapCoordinate(coordinate.latitude, coordinate.longitude),
            ),
            myLocationEnabled: widget.myLocationEnabled,
            compassEnabled: widget.compassEnabled,
            scrollGesturesEnabled: widget.scrollGesturesEnabled,
            zoomGesturesEnabled: widget.zoomGesturesEnabled,
            rotateGesturesEnabled: widget.rotateGesturesEnabled,
            tiltGesturesEnabled: widget.tiltGesturesEnabled,
            foregroundLoadColor: Theme.of(context).colorScheme.surface,
            attributionButtonColor: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant,
          ),
        ),
        if (!_styleLoaded)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (_loadFailed)
          Positioned.fill(
            child: _MapLoadErrorState(
              title: context.l10n.t('map.load_failed_title'),
              message: context.l10n.t('map.load_failed_message'),
              retryLabel: context.l10n.t('map.retry_load'),
              onRetry: _retryLoad,
            ),
          ),
        Positioned(
          left: 10,
          bottom: 10,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  'GOONG  •  PlanPal',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleMapCreated(maplibre.MapLibreMapController controller) {
    _native = controller;
    controller.onFeatureDrag.add((
      _,
      __,
      current,
      ___,
      id,
      annotation,
      eventType,
    ) {
      if (eventType != maplibre.DragEventType.end) return;
      final pin = _pinBySymbolId[id];
      if (pin == null || !pin.draggable) return;
      pin.onDragEnd?.call(MapCoordinate(current.latitude, current.longitude));
    });
    widget.onMapCreated?.call(PlanPalMapController._(controller));
  }

  Future<void> _handleStyleLoaded() async {
    _loadWatchdog?.cancel();
    if (mounted) {
      setState(() {
        _styleLoaded = true;
        _loadFailed = false;
      });
    } else {
      _styleLoaded = true;
    }
    _markerInstalled = false;
    await _renderPins();
  }

  void _armLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 12), () {
      if (!mounted || _styleLoaded) return;
      setState(() => _loadFailed = true);
    });
  }

  void _retryLoad() {
    setState(() {
      _styleLoaded = false;
      _loadFailed = false;
      _markerInstalled = false;
      _native = null;
      _mapRevision++;
    });
    _armLoadWatchdog();
  }

  Future<void> _renderPins() async {
    final controller = _native;
    if (controller == null || !_styleLoaded) return;
    final version = ++_renderVersion;

    await controller.clearSymbols();
    _pinBySymbolId.clear();
    if (!_markerInstalled) {
      await controller.addImage(_markerImage, await _createMarkerImage());
      _markerInstalled = true;
    }
    if (version != _renderVersion) return;

    final dark = mounted && Theme.of(context).brightness == Brightness.dark;

    for (final pin in widget.pins) {
      final symbol = await controller.addSymbol(
        maplibre.SymbolOptions(
          geometry: pin.position.native,
          iconImage: _markerImage,
          iconSize: 0.72,
          iconAnchor: 'bottom',
          draggable: pin.draggable,
          textField: pin.title,
          textSize: 12,
          textOffset: const Offset(0, 1.3),
          textColor: dark ? '#F8FAFC' : '#172033',
          textHaloColor: dark ? '#0F172A' : '#FFFFFF',
          textHaloWidth: 1.5,
        ),
      );
      _pinBySymbolId[symbol.id] = pin;
    }
  }

  Future<Uint8List> _createMarkerImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final path = Path()
      ..moveTo(36, 68)
      ..cubicTo(28, 52, 13, 41, 13, 27)
      ..cubicTo(13, 11, 24, 3, 36, 3)
      ..cubicTo(48, 3, 59, 11, 59, 27)
      ..cubicTo(59, 41, 44, 52, 36, 68)
      ..close();
    canvas.drawShadow(path, const Color(0x55000000), 5, true);
    canvas.drawPath(path, Paint()..color = const Color(0xFF4F46E5));
    canvas.drawCircle(
      const Offset(36, 27),
      12,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      const Offset(36, 27),
      6,
      Paint()..color = const Color(0xFF06B6D4),
    );
    final image = await recorder.endRecording().toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }
}

class _MapConfigurationState extends StatelessWidget {
  const _MapConfigurationState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.map_outlined,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapLoadErrorState extends StatelessWidget {
  const _MapLoadErrorState({
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface.withValues(alpha: 0.97),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 44, color: colors.primary),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
