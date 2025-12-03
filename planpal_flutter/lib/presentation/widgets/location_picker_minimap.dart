import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class LocationPickerMinimap extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialLocationName;
  final Function(double lat, double lng, String address) onLocationSelected;
  final double height;

  const LocationPickerMinimap({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialLocationName,
    required this.onLocationSelected,
    this.height = 200,
  });

  @override
  State<LocationPickerMinimap> createState() => _LocationPickerMinimapState();
}

class _LocationPickerMinimapState extends State<LocationPickerMinimap> {
  late GoogleMapController _mapController;
  LatLng _selectedPosition = const LatLng(
    10.762622,
    106.660172,
  ); // Default: Ho Chi Minh City
  Set<Marker> _markers = {};
  bool _isLoading = true;
  String _selectedAddress = '';

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    // Use provided coordinates or get user's current location
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPosition = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
      _selectedAddress = widget.initialLocationName ?? 'Selected Location';
      _updateMarker(_selectedPosition);
    } else {
      await _getCurrentLocation();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are not enabled, use default location
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permissions are denied, use default location
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Permissions are permanently denied, use default location
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _selectedPosition = LatLng(position.latitude, position.longitude);
      _updateMarker(_selectedPosition);
      _reverseGeocode(_selectedPosition);
    } catch (e) {
      // Error getting location, stick with default
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
            title: 'Selected Location',
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
    try {
      // In a real implementation, you would use a geocoding service
      // For now, we'll generate a simple address format
      _selectedAddress =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

      // TODO: Integrate with backend Goong service for reverse geocoding
      // You could call your backend API here to get the actual address

      widget.onLocationSelected(
        position.latitude,
        position.longitude,
        _selectedAddress,
      );

      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('selected_location'),
            position: position,
            draggable: true,
            onDragEnd: _onMarkerDragEnd,
            infoWindow: InfoWindow(
              title: 'Selected Location',
              snippet: _selectedAddress,
            ),
          ),
        };
      });
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  GoogleMap(
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                    },
                    initialCameraPosition: CameraPosition(
                      target: _selectedPosition,
                      zoom: 15.0,
                    ),
                    markers: _markers,
                    onTap: _onMapTap,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                  ),
                  // Custom controls overlay
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: "zoom_in",
                          onPressed: () {
                            _mapController.animateCamera(CameraUpdate.zoomIn());
                          },
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.add, color: Colors.black54),
                        ),
                        const SizedBox(height: 4),
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
                        const SizedBox(height: 4),
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
                  // Address display at bottom
                  if (_selectedAddress.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
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
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 16,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedAddress,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
