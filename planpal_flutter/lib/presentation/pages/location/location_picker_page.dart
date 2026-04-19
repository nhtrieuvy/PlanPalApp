import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:planpal_flutter/core/repositories/location_repository.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class LocationPickerPage extends ConsumerStatefulWidget {
  const LocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialLocationName,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialLocationName;

  @override
  ConsumerState<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends ConsumerState<LocationPickerPage> {
  static const LatLng _defaultPosition = LatLng(10.762622, 106.660172);
  static const String _defaultLocationName = 'Vị trí đã chọn';

  late final LocationRepository _locationRepository;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  GoogleMapController? _mapController;
  Timer? _searchDebounce;

  late LatLng _selectedPosition;
  String _selectedAddress = '';
  String _locationName = '';
  bool _isInitializing = true;
  bool _isResolvingLocation = false;
  bool _isSearching = false;
  bool _showSuggestions = false;
  List<Map<String, dynamic>> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _locationRepository = ref.read(locationRepositoryProvider);
    _selectedPosition = _initialPositionFromWidget();
    _locationName = widget.initialLocationName?.trim() ?? '';
    _selectedAddress = _locationName;
    _searchFocusNode.addListener(_handleSearchFocusChange);
    unawaited(_initializeLocation());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocusNode
      ..removeListener(_handleSearchFocusChange)
      ..dispose();
    super.dispose();
  }

  LatLng _initialPositionFromWidget() {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      return LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
    return _defaultPosition;
  }

  Future<void> _initializeLocation() async {
    _setMarkerOnly();
    await _resolveSelectedAddress();
    if (!mounted) {
      return;
    }
    setState(() {
      _isInitializing = false;
    });
  }

  void _handleSearchFocusChange() {
    if (!_searchFocusNode.hasFocus && mounted) {
      setState(() {
        _showSuggestions = false;
      });
    }
  }

  Future<void> _resolveSelectedAddress() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isResolvingLocation = true;
    });

    final result = await _locationRepository.reverseGeocode(
      _selectedPosition.latitude,
      _selectedPosition.longitude,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedAddress =
          result?['formatted_address']?.toString() ??
          _formatCoordinates(_selectedPosition);
      _locationName =
          result?['location_name']?.toString().trim().isNotEmpty == true
          ? result!['location_name'].toString()
          : (_selectedAddress.isNotEmpty ? _selectedAddress : _defaultLocationName);
      _isResolvingLocation = false;
    });

    _setMarkerOnly();
  }

  void _setMarkerOnly() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Set<Marker> get _markers => {
    Marker(
      markerId: const MarkerId('selected_location'),
      position: _selectedPosition,
      draggable: true,
      onDragEnd: _handleMapSelection,
      infoWindow: InfoWindow(
        title: _locationName.isNotEmpty ? _locationName : _defaultLocationName,
        snippet: _selectedAddress,
      ),
    ),
  };

  Future<void> _handleMapSelection(LatLng position) async {
    setState(() {
      _selectedPosition = position;
      _locationName = _defaultLocationName;
      _selectedAddress = _formatCoordinates(position);
      _showSuggestions = false;
      _suggestions = const [];
    });
    await _animateTo(position, zoom: 16);
    await _resolveSelectedAddress();
  }

  Future<void> _animateTo(LatLng position, {double? zoom}) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    await controller.animateCamera(
      zoom == null
          ? CameraUpdate.newLatLng(position)
          : CameraUpdate.newLatLngZoom(position, zoom),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _isSearching = false;
        _showSuggestions = false;
        _suggestions = const [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final suggestions = await _locationRepository.getAutocompleteSuggestions(
        query,
      );
      if (!mounted || _searchController.text.trim() != query) {
        return;
      }

      setState(() {
        _isSearching = false;
        _suggestions = suggestions;
        _showSuggestions = suggestions.isNotEmpty && _searchFocusNode.hasFocus;
      });
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    _searchFocusNode.unfocus();

    final directLatitude = (suggestion['latitude'] as num?)?.toDouble();
    final directLongitude = (suggestion['longitude'] as num?)?.toDouble();
    final description =
        suggestion['description']?.toString().trim().isNotEmpty == true
        ? suggestion['description'].toString()
        : _defaultLocationName;

    setState(() {
      _showSuggestions = false;
      _suggestions = const [];
      _searchController.text = description;
    });

    if (directLatitude != null && directLongitude != null) {
      _selectedPosition = LatLng(directLatitude, directLongitude);
      _locationName = description;
      _selectedAddress = description;
      _setMarkerOnly();
      await _animateTo(_selectedPosition, zoom: 16);
      await _resolveSelectedAddress();
      return;
    }

    final placeId = suggestion['place_id']?.toString();
    if (placeId == null || placeId.isEmpty) {
      return;
    }

    setState(() {
      _isResolvingLocation = true;
    });

    final details = await _locationRepository.getPlaceDetails(placeId);
    if (!mounted) {
      return;
    }

    final latitude = (details?['latitude'] as num?)?.toDouble();
    final longitude = (details?['longitude'] as num?)?.toDouble();

    if (latitude == null || longitude == null) {
      setState(() {
        _isResolvingLocation = false;
      });
      return;
    }

    _selectedPosition = LatLng(latitude, longitude);
    _locationName = details?['name']?.toString().trim().isNotEmpty == true
        ? details!['name'].toString()
        : description;
    _selectedAddress =
        details?['formatted_address']?.toString() ??
        details?['address']?.toString() ??
        description;

    _setMarkerOnly();
    await _animateTo(_selectedPosition, zoom: 16);

    if (!mounted) {
      return;
    }
    setState(() {
      _isResolvingLocation = false;
    });
  }

  Future<void> _goToCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Dịch vụ vị trí đang tắt.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showSnackBar('Ứng dụng chưa có quyền truy cập vị trí.');
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _handleMapSelection(LatLng(position.latitude, position.longitude));
    } catch (_) {
      _showSnackBar('Không thể lấy vị trí hiện tại.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _confirmSelection() {
    final normalizedLatitude = double.parse(
      _selectedPosition.latitude.toStringAsFixed(6),
    );
    final normalizedLongitude = double.parse(
      _selectedPosition.longitude.toStringAsFixed(6),
    );
    Navigator.of(context).pop({
      'latitude': normalizedLatitude,
      'longitude': normalizedLongitude,
      'location_name': _locationName.isNotEmpty ? _locationName : _defaultLocationName,
      'location_address': _selectedAddress.isNotEmpty
          ? _selectedAddress
          : _formatCoordinates(_selectedPosition),
      'address': _selectedAddress.isNotEmpty
          ? _selectedAddress
          : _formatCoordinates(_selectedPosition),
    });
  }

  String _formatCoordinates(LatLng position) =>
      '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chọn vị trí'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: _confirmSelection,
              child: const Text(
                'Xác nhận',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                onMapCreated: (controller) async {
                  _mapController = controller;
                  await _animateTo(_selectedPosition, zoom: 15);
                },
                initialCameraPosition: CameraPosition(
                  target: _selectedPosition,
                  zoom: 15,
                ),
                markers: _markers,
                onTap: _handleMapSelection,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: true,
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _buildSearchPanel(theme),
            ),
            Positioned(
              right: 16,
              bottom: 220,
              child: FloatingActionButton.small(
                heroTag: 'current_location_button',
                onPressed: _goToCurrentLocation,
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                child: const Icon(Icons.my_location),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomSheet(theme),
            ),
            if (_isInitializing)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x55000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPanel(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm địa điểm...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _showSuggestions = false;
                                  _suggestions = const [];
                                  _isSearching = false;
                                });
                              },
                              icon: const Icon(Icons.close),
                            )
                          : null),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
              onChanged: _onSearchChanged,
              onTap: () {
                if (_suggestions.isNotEmpty) {
                  setState(() {
                    _showSuggestions = true;
                  });
                }
              },
            ),
          ),
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  final mainText =
                      suggestion['structured_formatting']?['main_text']
                          ?.toString() ??
                      suggestion['description']?.toString() ??
                      '';
                  final secondaryText =
                      suggestion['structured_formatting']?['secondary_text']
                          ?.toString() ??
                      '';
                  return ListTile(
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(mainText),
                    subtitle: secondaryText.isEmpty ? null : Text(secondaryText),
                    onTap: () => _selectSuggestion(suggestion),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _suggestions.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet(ThemeData theme) {
    final displayTitle = _locationName.isNotEmpty ? _locationName : _defaultLocationName;
    final displayAddress = _selectedAddress.isNotEmpty
        ? _selectedAddress
        : _formatCoordinates(_selectedPosition);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.place, color: Colors.redAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        displayAddress,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isResolvingLocation)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tọa độ: ${_formatCoordinates(_selectedPosition)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirmSelection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Chọn vị trí này',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
