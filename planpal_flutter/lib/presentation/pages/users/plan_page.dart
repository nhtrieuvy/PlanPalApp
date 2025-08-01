import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kế hoạch'), centerTitle: true),
      body: const Center(
        child: Text(
          'Trang Kế hoạch',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
