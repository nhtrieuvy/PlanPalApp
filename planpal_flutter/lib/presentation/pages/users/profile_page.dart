import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cá nhân'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: () async {
              try {
                await Provider.of<AuthProvider>(
                  context,
                  listen: false,
                ).logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              } catch (e) {
                // Hiển thị lỗi nếu cần thiết
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đăng xuất thất bại: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  // Vẫn chuyển về trang login nếu có lỗi
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              }
            },
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          final user = auth.user;
          if (user == null) {
            return const Center(child: Text('Chưa đăng nhập'));
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 64,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 16),
                Text(
                  user['username'] ?? 'Không rõ tên',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (user['email'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    user['email'],
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 24),
                const Text('Trang Cá nhân', style: TextStyle(fontSize: 20)),
              ],
            ),
          );
        },
      ),
    );
  }
}
