import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/database_helper.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String _entered = '';
  bool _error = false;

  void _onKey(String digit) {
    if (_entered.length >= 6) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    if (_entered.length == 6) _verify();
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _verify() async {
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    final storedPin = settings['pin'] ?? '';
    final success = await ref.read(authProvider.notifier).login(_entered, storedPin);
    if (!success) {
      setState(() {
        _entered = '';
        _error = true;
      });
    }
  }

  Widget _buildDot(int index) {
    final filled = index < _entered.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _error
            ? AppColors.error
            : filled
                ? AppColors.primary
                : AppColors.border,
        border: Border.all(
          color: _error ? AppColors.error : AppColors.primary,
          width: 2,
        ),
      ),
    );
  }

  Widget _buildKey(String label, {VoidCallback? onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.point_of_sale, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 24),
                const Text(
                  'POSin',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Masukkan PIN untuk melanjutkan',
                  style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _buildDot(i),
                    );
                  }),
                ),
                if (_error) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'PIN salah. Coba lagi.',
                    style: TextStyle(color: AppColors.error, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () async {
                    DatabaseHelper.clearUser();
                    await Supabase.instance.client.auth.signOut();
                  },
                  icon: const Icon(Icons.logout, size: 16, color: AppColors.textSecondary),
                  label: const Text('Keluar Akun', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map(
                      (d) => _buildKey(d, onTap: () => _onKey(d)),
                    ),
                    const SizedBox.shrink(),
                    _buildKey('0', onTap: () => _onKey('0')),
                    _buildKey('⌫', onTap: _onDelete, color: AppColors.error),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
