import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:planpal_flutter/core/dtos/conversation.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/repositories/location_repository.dart';
import 'package:planpal_flutter/core/riverpod/conversation_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class CurrentLocationMapPage extends ConsumerStatefulWidget {
  const CurrentLocationMapPage({super.key});

  @override
  ConsumerState<CurrentLocationMapPage> createState() =>
      _CurrentLocationMapPageState();
}

class _CurrentLocationMapPageState
    extends ConsumerState<CurrentLocationMapPage> {
  static const LatLng _defaultPosition = LatLng(10.762622, 106.660172);
  static const Duration _locationServiceTimeout = Duration(seconds: 2);
  static const Duration _permissionTimeout = Duration(seconds: 5);
  static const Duration _gpsTimeout = Duration(seconds: 8);
  static const Duration _lastKnownTimeout = Duration(seconds: 2);

  late final LocationRepository _locationRepository;
  GoogleMapController? _mapController;

  LatLng _selectedPosition = _defaultPosition;
  String _locationName = '';
  String _address = '';
  bool _isLoadingLocation = false;
  bool _isResolvingAddress = false;
  bool _hasLocationPermission = false;
  int _addressRequestId = 0;

  @override
  void initState() {
    super.initState();
    _locationRepository = ref.read(locationRepositoryProvider);
    _address = _formatCoordinates(_selectedPosition);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadCurrentLocation());
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Set<Marker> get _markers {
    final title = _locationName.isNotEmpty
        ? _locationName
        : context.l10n.t('map.selected_location');
    final snippet = _address.isNotEmpty
        ? _address
        : _formatCoordinates(_selectedPosition);

    return {
      Marker(
        markerId: const MarkerId('current_location'),
        position: _selectedPosition,
        infoWindow: InfoWindow(title: title, snippet: snippet),
      ),
    };
  }

  Future<void> _loadCurrentLocation() async {
    final serviceDisabledMessage = context.l10n.t(
      'location_picker.location_service_disabled',
    );
    final permissionDeniedMessage = context.l10n.t(
      'location_picker.permission_denied',
    );
    final currentLocationErrorMessage = context.l10n.t(
      'location_picker.current_location_error',
    );

    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
      });
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(_locationServiceTimeout, onTimeout: () => false);
      if (!serviceEnabled) {
        _showSnackBar(serviceDisabledMessage);
        _applyLoadedPosition(_selectedPosition, hasPermission: false);
        return;
      }

      var permission = await Geolocator.checkPermission().timeout(
        _permissionTimeout,
        onTimeout: () => LocationPermission.denied,
      );
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          _permissionTimeout,
          onTimeout: () => LocationPermission.denied,
        );
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _hasLocationPermission = false;
          });
        }
        _showSnackBar(permissionDeniedMessage);
        _applyLoadedPosition(_selectedPosition, hasPermission: false);
        return;
      }

      final position = await _getBestAvailablePosition();
      final nextPosition = position == null
          ? _selectedPosition
          : LatLng(position.latitude, position.longitude);

      _applyLoadedPosition(nextPosition, hasPermission: true);
    } catch (_) {
      _showSnackBar(currentLocationErrorMessage);
      _applyLoadedPosition(
        _selectedPosition,
        hasPermission: _hasLocationPermission,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<Position?> _getBestAvailablePosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: _gpsTimeout,
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition().timeout(
          _lastKnownTimeout,
          onTimeout: () => null,
        );
      } catch (_) {
        return null;
      }
    }
  }

  void _applyLoadedPosition(LatLng position, {required bool hasPermission}) {
    if (!mounted) return;
    setState(() {
      _selectedPosition = position;
      _hasLocationPermission = hasPermission;
      _isLoadingLocation = false;
    });

    unawaited(_animateTo(position, zoom: 16));
    unawaited(_resolveAddress(position));
  }

  Future<void> _resolveAddress(LatLng position) async {
    final selectedLocationName = context.l10n.t('map.selected_location');
    final requestId = ++_addressRequestId;

    if (!mounted) return;
    setState(() {
      _isResolvingAddress = true;
    });

    try {
      final result = await _locationRepository.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (!mounted || requestId != _addressRequestId) return;
      setState(() {
        _address =
            result?['formatted_address']?.toString() ??
            _formatCoordinates(position);
        _locationName =
            result?['location_name']?.toString().trim().isNotEmpty == true
            ? result!['location_name'].toString()
            : selectedLocationName;
      });
    } finally {
      if (mounted && requestId == _addressRequestId) {
        setState(() {
          _isResolvingAddress = false;
        });
      }
    }
  }

  Future<void> _animateTo(LatLng position, {double? zoom}) async {
    final controller = _mapController;
    if (controller == null) return;

    await controller.animateCamera(
      zoom == null
          ? CameraUpdate.newLatLng(position)
          : CameraUpdate.newLatLngZoom(position, zoom),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatCoordinates(LatLng position) =>
      '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

  Future<void> _showConversationPicker() async {
    String? sendingConversationId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Consumer(
              builder: (sheetContext, ref, _) {
                final conversationsAsync = ref.watch(conversationListProvider);
                final theme = Theme.of(sheetContext);

                return SafeArea(
                  child: SizedBox(
                    height: MediaQuery.of(sheetContext).size.height * 0.72,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.t('map.choose_conversation'),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.l10n.t('map.choose_conversation_hint'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: conversationsAsync.when(
                              loading: () =>
                                  const AppSkeleton.list(itemCount: 5),
                              error: (error, _) => AppError(
                                message:
                                    '${context.l10n.t('map.load_conversations_failed')}\n$error',
                                onRetry: () => ref
                                    .read(conversationListProvider.notifier)
                                    .refresh(),
                                retryLabel: context.l10n.t('common.retry'),
                              ),
                              data: (conversations) {
                                if (conversations.isEmpty) {
                                  return AppEmpty(
                                    icon: Icons.chat_bubble_outline,
                                    title: context.l10n.t(
                                      'map.no_conversations_title',
                                    ),
                                    description: context.l10n.t(
                                      'map.no_conversations_description',
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  itemCount: conversations.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final conversation = conversations[index];
                                    final isSending =
                                        sendingConversationId ==
                                        conversation.id;
                                    return _ConversationLocationTile(
                                      conversation: conversation,
                                      isSending: isSending,
                                      onTap: sendingConversationId == null
                                          ? () async {
                                              setSheetState(() {
                                                sendingConversationId =
                                                    conversation.id;
                                              });
                                              await _sendLocationToConversation(
                                                conversation,
                                                sheetContext,
                                              );
                                              if (!sheetContext.mounted) {
                                                return;
                                              }
                                              setSheetState(() {
                                                sendingConversationId = null;
                                              });
                                            }
                                          : null,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _sendLocationToConversation(
    Conversation conversation,
    BuildContext sheetContext,
  ) async {
    final locationName = _locationName.isNotEmpty
        ? _locationName
        : context.l10n.t('map.selected_location');

    try {
      await ref
          .read(conversationRepositoryProvider)
          .sendLocationMessage(
            conversation.id,
            _selectedPosition.latitude,
            _selectedPosition.longitude,
            locationName,
          );

      ref.invalidate(conversationListProvider);
      ref.invalidate(messagesProvider(conversation.id));

      if (!mounted) return;
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t(
          'map.sent_success',
          params: {'conversation': conversation.displayName},
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('map.send_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.t('map.title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _defaultPosition,
                zoom: 14,
              ),
              onMapCreated: (controller) async {
                _mapController = controller;
                await _animateTo(_selectedPosition, zoom: 16);
              },
              markers: _markers,
              myLocationEnabled: _hasLocationPermission,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
            ),
          ),
          if (_isLoadingLocation)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withAlpha(35),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 210,
            child: FloatingActionButton.small(
              heroTag: 'current_location_map_button',
              onPressed: _loadCurrentLocation,
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: AppColors.primary,
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildLocationCard(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(ThemeData theme) {
    final displayName = _locationName.isNotEmpty
        ? _locationName
        : context.l10n.t('map.selected_location');
    final displayAddress = _address.isNotEmpty
        ? _address
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
                  child: Icon(Icons.my_location, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
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
                if (_isResolvingAddress)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.t(
                'location_picker.coordinates',
                params: {'value': _formatCoordinates(_selectedPosition)},
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showConversationPicker,
                icon: const Icon(Icons.send_rounded),
                label: Text(context.l10n.t('map.send_location')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationLocationTile extends StatelessWidget {
  const _ConversationLocationTile({
    required this.conversation,
    required this.isSending,
    required this.onTap,
  });

  final Conversation conversation;
  final bool isSending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withAlpha(35),
        foregroundColor: AppColors.primary,
        backgroundImage: conversation.avatarUrl.isNotEmpty
            ? NetworkImage(conversation.avatarUrl)
            : null,
        child: conversation.avatarUrl.isEmpty
            ? Text(_avatarText(conversation.displayName, conversation.isGroup))
            : null,
      ),
      title: Text(
        conversation.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        conversation.isGroup
            ? context.l10n.t(
                'map.group_conversation',
                params: {'count': '${conversation.participants.length}'},
              )
            : context.l10n.t('map.direct_conversation'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isSending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right_rounded),
    );
  }

  String _avatarText(String displayName, bool isGroup) {
    if (displayName.trim().isEmpty) return isGroup ? 'G' : 'U';
    return displayName.trim().characters.first.toUpperCase();
  }
}
