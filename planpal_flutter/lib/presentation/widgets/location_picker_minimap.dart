import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/maps/planpal_map.dart';
import 'package:planpal_flutter/core/repositories/location_repository.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';

class LocationPickerMinimap extends ConsumerStatefulWidget {
  const LocationPickerMinimap({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialLocationName,
    required this.onLocationSelected,
    this.height = 220,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialLocationName;
  final void Function(double lat, double lng, String address)
  onLocationSelected;
  final double height;

  @override
  ConsumerState<LocationPickerMinimap> createState() =>
      _LocationPickerMinimapState();
}

class _LocationPickerMinimapState extends ConsumerState<LocationPickerMinimap> {
  static const _fallback = MapCoordinate(10.762622, 106.660172);

  late final LocationRepository _locationRepository;
  PlanPalMapController? _mapController;
  MapCoordinate _selectedPosition = _fallback;
  String _selectedAddress = '';
  bool _isLoading = true;
  bool _isResolving = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _locationRepository = ref.read(locationRepositoryProvider);
    unawaited(_initializeLocation());
  }

  Future<void> _initializeLocation() async {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPosition = MapCoordinate(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
      _selectedAddress = widget.initialLocationName?.trim() ?? '';
      if (_selectedAddress.isEmpty) await _reverseGeocode(_selectedPosition);
    } else {
      await _getCurrentLocation();
      await _reverseGeocode(_selectedPosition);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      _selectedPosition = MapCoordinate(position.latitude, position.longitude);
      await _mapController?.animateCamera(
        MapCameraUpdate.newCoordinateZoom(_selectedPosition, 16),
      );
    } catch (_) {
      // The map stays usable at the fallback location when GPS is unavailable.
    }
  }

  Future<void> _selectPosition(MapCoordinate position) async {
    if (!mounted) return;
    setState(() {
      _selectedPosition = position;
      _selectedAddress = _formatCoordinates(position);
    });
    await _reverseGeocode(position);
  }

  Future<void> _reverseGeocode(MapCoordinate position) async {
    final requestId = ++_requestId;
    if (mounted) setState(() => _isResolving = true);
    try {
      final result = await _locationRepository.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (!mounted || requestId != _requestId) return;
      final address =
          result?['formatted_address']?.toString().trim() ??
          _formatCoordinates(position);
      setState(() => _selectedAddress = address);
      widget.onLocationSelected(position.latitude, position.longitude, address);
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _isResolving = false);
      }
    }
  }

  String _formatCoordinates(MapCoordinate position) =>
      '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: _isLoading
          ? ColoredBox(
              color: colors.surfaceContainerLow,
              child: const Center(child: CircularProgressIndicator()),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: PlanPalMap(
                    initialCameraPosition: MapCameraPosition(
                      target: _selectedPosition,
                      zoom: 15,
                    ),
                    pins: {
                      MapPin(
                        id: 'selected_location',
                        position: _selectedPosition,
                        draggable: true,
                        onDragEnd: _selectPosition,
                      ),
                    },
                    onMapCreated: (controller) => _mapController = controller,
                    onTap: _selectPosition,
                    myLocationEnabled: true,
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _MapControl(
                    tooltip: context.l10n.t('map.current_location'),
                    icon: Icons.my_location_rounded,
                    onPressed: () async {
                      await _getCurrentLocation();
                      await _reverseGeocode(_selectedPosition);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                if (_selectedAddress.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.place_rounded,
                              size: 20,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedAddress,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                            if (_isResolving) ...[
                              const SizedBox(width: 8),
                              const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon)),
  );
}
