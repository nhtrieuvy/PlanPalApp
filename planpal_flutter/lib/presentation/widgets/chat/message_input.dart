import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../pages/location/location_picker_page.dart';

class MessageInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final Function(File) onSendImage;
  final Function(double lat, double lng, String? locationName) onSendLocation;
  final Function(File file, String fileName) onSendFile;
  final VoidCallback? onStartTyping;
  final VoidCallback? onStopTyping;
  final bool isEnabled;
  final String? placeholder;

  const MessageInput({
    super.key,
    required this.onSendMessage,
    required this.onSendImage,
    required this.onSendLocation,
    required this.onSendFile,
    this.onStartTyping,
    this.onStopTyping,
    this.isEnabled = true,
    this.placeholder = 'Nhap tin nhan...',
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  bool _showAttachmentOptions = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;

    if (hasText && !_isTyping) {
      setState(() => _isTyping = true);
      widget.onStartTyping?.call();
    } else if (!hasText && _isTyping) {
      setState(() => _isTyping = false);
      widget.onStopTyping?.call();
    }
  }

  void _onFocusChanged() {
    setState(() {
      if (_focusNode.hasFocus) {
        _showAttachmentOptions = false;
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isNotEmpty && widget.isEnabled) {
      widget.onSendMessage(text);
      _textController.clear();
      setState(() {
        _isTyping = false;
        _showAttachmentOptions = false;
      });
      widget.onStopTyping?.call();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) {
        return;
      }

      widget.onSendImage(File(image.path));
      if (mounted) {
        setState(() => _showAttachmentOptions = false);
      }
    } catch (e) {
      _showError('Khong the chon anh: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      final pickedFile = result?.files.singleOrNull;
      final path = pickedFile?.path;

      if (pickedFile == null || path == null || path.isEmpty) {
        return;
      }

      widget.onSendFile(File(path), pickedFile.name);
      if (mounted) {
        setState(() => _showAttachmentOptions = false);
      }
    } catch (e) {
      _showError('Khong the chon file: $e');
    }
  }

  Future<void> _shareLocation() async {
    try {
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => const LocationPickerPage()),
      );

      if (result == null) {
        return;
      }

      final lat = (result['latitude'] as num?)?.toDouble();
      final lng = (result['longitude'] as num?)?.toDouble();
      final locationName =
          result['location_name']?.toString() ??
          result['address']?.toString() ??
          result['location_address']?.toString();

      if (lat == null || lng == null) {
        _showError('Khong lay duoc toa do hop le.');
        return;
      }

      widget.onSendLocation(lat, lng, locationName);
      if (mounted) {
        setState(() => _showAttachmentOptions = false);
      }
    } catch (e) {
      _showError('Khong the chia se vi tri: $e');
    }
  }

  void _toggleAttachmentOptions() {
    if (!widget.isEnabled) return;
    _focusNode.unfocus();
    setState(() {
      _showAttachmentOptions = !_showAttachmentOptions;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildImagePickerSheet(),
    );
  }

  Widget _buildImagePickerSheet() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withAlpha(75),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Chon anh',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPickerOption(
                icon: PhosphorIcons.camera(),
                label: 'Camera',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              _buildPickerOption(
                icon: PhosphorIcons.images(),
                label: 'Thu vien',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withAlpha(25),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(icon, size: 28, color: const Color(0xFF6366F1)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasText = _textController.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(125),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showAttachmentOptions && !hasText) _buildAttachmentOptions(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!hasText) _buildAttachmentButton(),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(left: hasText ? 0 : 8, right: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(125),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? const Color(0xFF6366F1)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      enabled: widget.isEnabled,
                      maxLines: 6,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        height: 1.4,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.placeholder,
                        hintStyle: GoogleFonts.inter(
                          fontSize: 16,
                          color: colorScheme.onSurfaceVariant.withAlpha(175),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                _buildSendButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _toggleAttachmentOptions,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withAlpha(25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          PhosphorIcons.plus(),
          size: 20,
          color: widget.isEnabled
              ? const Color(0xFF6366F1)
              : colorScheme.onSurfaceVariant.withAlpha(125),
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasText = _textController.text.trim().isNotEmpty;
    final canSend = hasText && widget.isEnabled;

    return GestureDetector(
      onTap: canSend ? _sendMessage : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: canSend
              ? const Color(0xFF6366F1)
              : colorScheme.onSurfaceVariant.withAlpha(75),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          PhosphorIcons.paperPlaneTilt(),
          size: 20,
          color: canSend ? Colors.white : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildAttachmentOptions() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          _buildAttachmentOption(
            icon: PhosphorIcons.camera(),
            label: 'Camera',
            onTap: () => _pickImage(ImageSource.camera),
          ),
          const SizedBox(width: 16),
          _buildAttachmentOption(
            icon: PhosphorIcons.images(),
            label: 'Anh',
            onTap: _showImagePicker,
          ),
          const SizedBox(width: 16),
          _buildAttachmentOption(
            icon: PhosphorIcons.mapPin(),
            label: 'Vi tri',
            onTap: _shareLocation,
          ),
          const SizedBox(width: 16),
          _buildAttachmentOption(
            icon: PhosphorIcons.file(),
            label: 'File',
            onTap: _pickFile,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: widget.isEnabled ? onTap : null,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withAlpha(25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 20,
              color: widget.isEnabled
                  ? const Color(0xFF6366F1)
                  : colorScheme.onSurfaceVariant.withAlpha(125),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: widget.isEnabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant.withAlpha(125),
            ),
          ),
        ],
      ),
    );
  }
}
