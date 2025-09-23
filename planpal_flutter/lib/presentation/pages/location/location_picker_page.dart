import 'package:flutter/material.dart';
// removed color_utils; use withAlpha directly
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/location_repository.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class LocationPickerPage extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialLocationName;

  const LocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialLocationName,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  late GoogleMapController _mapController;
  late LocationRepository _locationService;
  LatLng _selectedPosition = const LatLng(
    10.762622,
    106.660172,
  ); // Default: HCM
  Set<Marker> _markers = {};
  bool _isLoading = true;
  bool _isReverseGeocoding = false;
  String _selectedAddress = '';
  String _locationName = '';
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchSuggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _locationService = LocationRepository(context.read<AuthProvider>());
    _initializeLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    debugPrint('🔄 Starting location initialization...');
    setState(() => _isLoading = true);

    // Use provided coordinates or default to HCMC
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPosition = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
      _locationName = widget.initialLocationName ?? 'Vị trí đã chọn';
      _selectedAddress = _locationName;
      debugPrint(
        '📍 Using initial coordinates: ${_selectedPosition.latitude}, ${_selectedPosition.longitude}',
      );
    } else {
      debugPrint('📍 Using default HCMC coordinates');
      // Keep default HCMC position, don't try to get current location to avoid complications
    }

    // Always ensure we have a marker
    _updateMarker(_selectedPosition);

    debugPrint('✅ Location initialization complete');
    setState(() => _isLoading = false);
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _selectedPosition = LatLng(position.latitude, position.longitude);
      _updateMarker(_selectedPosition);
      await _reverseGeocode(_selectedPosition);
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  void _updateMarker(LatLng position) {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          draggable: true,
          onDragEnd: _onMarkerDragEnd,
          infoWindow: InfoWindow(
            title: _locationName.isNotEmpty ? _locationName : 'Vị trí đã chọn',
            snippet: _selectedAddress,
          ),
        ),
      };
    });
  }

  void _onMarkerDragEnd(LatLng newPosition) {
    _selectedPosition = newPosition;
    _updateMarker(newPosition);
    _reverseGeocode(newPosition);
  }

  void _onMapTap(LatLng position) {
    _selectedPosition = position;
    _updateMarker(position);
    _reverseGeocode(position);
  }

  Future<void> _reverseGeocode(LatLng position) async {
    setState(() => _isReverseGeocoding = true);

    try {
      final result = await _locationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (result != null) {
        _selectedAddress =
            result['formatted_address'] ??
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        _locationName = result['location_name'] ?? 'Vị trí đã chọn';
      } else {
        _selectedAddress =
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        _locationName = 'Vị trí đã chọn';
      }

      _updateMarker(position);
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      _selectedAddress =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      _locationName = 'Vị trí đã chọn';
      _updateMarker(position);
    } finally {
      setState(() => _isReverseGeocoding = false);
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    try {
      final suggestions = await _locationService.getAutocompleteSuggestions(
        query,
      );
      setState(() {
        _searchSuggestions = suggestions;
        _showSuggestions = suggestions.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Error searching places: $e');
    }
  }

  void _selectSuggestion(Map<String, dynamic> suggestion) async {
    debugPrint('🔍 Selected suggestion: ${suggestion['description']}');

    // First check if coordinates are available
    final lat = suggestion['latitude']?.toDouble();
    final lng = suggestion['longitude']?.toDouble();

    if (lat != null && lng != null) {
      // Direct coordinates available
      final position = LatLng(lat, lng);
      _selectedPosition = position;
      _locationName = suggestion['description'] ?? 'Vị trí đã chọn';
      _selectedAddress = suggestion['description'] ?? '';
      _updateMarker(position);

      _mapController.animateCamera(CameraUpdate.newLatLngZoom(position, 16.0));
      debugPrint('📍 Moving map to: $lat, $lng');
    } else {
      // Need to get place details first
      final placeId = suggestion['place_id'];
      if (placeId != null && placeId.isNotEmpty) {
        debugPrint('🔍 Getting place details for: $placeId');
        await _getPlaceDetails(placeId, suggestion['description'] ?? '');
      } else {
        debugPrint('❌ No coordinates or place_id available');
        // Just update the name without moving map
        _locationName = suggestion['description'] ?? 'Vị trí đã chọn';
        _selectedAddress = suggestion['description'] ?? '';
        setState(() {});
      }
    }

    _searchController.clear();
    setState(() {
      _showSuggestions = false;
      _searchSuggestions = [];
    });
  }

  Future<void> _getPlaceDetails(String placeId, String description) async {
    try {
      setState(() => _isReverseGeocoding = true);

      final placeDetails = await _locationService.getPlaceDetails(placeId);

      if (placeDetails != null) {
        debugPrint('🔍 Place details response: $placeDetails');

        // Try to extract coordinates from different possible structures
        double? lat, lng;

        // Method 1: Direct latitude/longitude (if backend formats it this way)
        lat = placeDetails['latitude']?.toDouble();
        lng = placeDetails['longitude']?.toDouble();

        // Method 2: From geometry.location (Goong API structure)
        if (lat == null || lng == null) {
          final geometry = placeDetails['geometry'] as Map<String, dynamic>?;
          if (geometry != null) {
            final location = geometry['location'] as Map<String, dynamic>?;
            if (location != null) {
              lat = location['lat']?.toDouble();
              lng = location['lng']?.toDouble();
            }
          }
        }

        if (lat != null && lng != null) {
          final position = LatLng(lat, lng);
          _selectedPosition = position;
          _locationName = description;
          _selectedAddress =
              placeDetails['address'] ??
              placeDetails['formatted_address'] ??
              description;
          _updateMarker(position);

          _mapController.animateCamera(
            CameraUpdate.newLatLngZoom(position, 16.0),
          );
          debugPrint('📍 Place details - Moving map to: $lat, $lng');
        } else {
          debugPrint('❌ Place details API did not return coordinates');
          debugPrint('Available keys: ${placeDetails.keys.toList()}');
          _locationName = description;
          _selectedAddress = description;
        }
      } else {
        debugPrint('❌ Failed to get place details');
        _locationName = description;
        _selectedAddress = description;
      }
    } catch (e) {
      debugPrint('❌ Error getting place details: $e');
      _locationName = description;
      _selectedAddress = description;
    } finally {
      setState(() => _isReverseGeocoding = false);
    }
  }

  void _confirmSelection() {
    Navigator.of(context).pop({
      'latitude': _selectedPosition.latitude,
      'longitude': _selectedPosition.longitude,
      'location_name': _locationName,
      'location_address': _selectedAddress,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: Column(
        children: [
          // Debug info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.blue.shade50,
            child: Text(
              'Loading: $_isLoading | Position: ${_selectedPosition.latitude.toStringAsFixed(4)}, ${_selectedPosition.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),

          // Map container
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang tải bản đồ...'),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      GoogleMap(
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
                          debugPrint('✅ GoogleMap initialized successfully');
                          debugPrint(
                            '📍 Camera position: ${_selectedPosition.latitude}, ${_selectedPosition.longitude}',
                          );

                          // Ensure camera moves to correct position after map is ready
                          Future.delayed(const Duration(milliseconds: 500), () {
                            _mapController.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: _selectedPosition,
                                  zoom: 15.0,
                                ),
                              ),
                            );
                          });
                        },
                        initialCameraPosition: CameraPosition(
                          target: _selectedPosition,
                          zoom: 15.0,
                        ),
                        markers: _markers,
                        onTap: _onMapTap,
                        myLocationEnabled:
                            false, // Disable to avoid permission conflicts
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapType: MapType.normal,
                        // Essential for Android - ensure map renders properly
                        gestureRecognizers:
                            const <Factory<OneSequenceGestureRecognizer>>{},
                      ),

                      // Search bar
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(25),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                decoration: const InputDecoration(
                                  hintText: 'Tìm kiếm địa điểm...',
                                  prefixIcon: Icon(Icons.search),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                onChanged: _searchPlaces,
                                onTap: () {
                                  if (_searchSuggestions.isNotEmpty) {
                                    setState(() => _showSuggestions = true);
                                  }
                                },
                              ),
                            ),

                            // Search suggestions
                            if (_showSuggestions &&
                                _searchSuggestions.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(25),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _searchSuggestions.length,
                                  itemBuilder: (context, index) {
                                    final suggestion =
                                        _searchSuggestions[index];
                                    return ListTile(
                                      leading: const Icon(
                                        Icons.location_on,
                                        size: 20,
                                      ),
                                      title: Text(
                                        suggestion['description'] ?? '',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      onTap: () =>
                                          _selectSuggestion(suggestion),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Map controls
                      Positioned(
                        bottom: 120,
                        right: 16,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: "zoom_in",
                              onPressed: () {
                                _mapController.animateCamera(
                                  CameraUpdate.zoomIn(),
                                );
                              },
                              backgroundColor: Colors.white,
                              child: const Icon(
                                Icons.add,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: "zoom_out",
                              onPressed: () {
                                _mapController.animateCamera(
                                  CameraUpdate.zoomOut(),
                                );
                              },
                              backgroundColor: Colors.white,
                              child: const Icon(
                                Icons.remove,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: "my_location",
                              onPressed: _getCurrentLocation,
                              backgroundColor: Colors.white,
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Selected location info
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _locationName.isNotEmpty
                                          ? _locationName
                                          : 'Vị trí đã chọn',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (_isReverseGeocoding)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedAddress,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tọa độ: ${_selectedPosition.latitude.toStringAsFixed(6)}, ${_selectedPosition.longitude.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Confirm selection button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    // Return selected location data to parent
                                    Navigator.pop(context, {
                                      'latitude': _selectedPosition.latitude,
                                      'longitude': _selectedPosition.longitude,
                                      'location_name': _locationName.isNotEmpty
                                          ? _locationName
                                          : 'Vị trí đã chọn',
                                      'location_address':
                                          _selectedAddress.isNotEmpty
                                          ? _selectedAddress
                                          : null,
                                      'address': _selectedAddress.isNotEmpty
                                          ? _selectedAddress
                                          : 'Địa chỉ không xác định',
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'Chọn vị trí này',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
