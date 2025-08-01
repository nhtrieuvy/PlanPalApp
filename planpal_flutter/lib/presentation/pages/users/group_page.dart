import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class GroupPage extends StatelessWidget {
  const GroupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nhóm'), centerTitle: true),
      body: const Center(
        child: Text(
          'Trang Nhóm',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
