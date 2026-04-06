import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Bottom sheet PIN input dengan numpad, mengembalikan PIN 6 digit via Navigator.pop(pin).
/// Gunakan: final pin = await showPinInputSheet(context, title: '...');
Future<String?> showPinInputSheet(BuildContext context, {required String title}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PinInputSheet(title: title),
  );
}

class _PinInputSheet extends StatefulWidget {
  final String title;
  const _PinInputSheet({required this.title});

  @override
  State<_PinInputSheet> createState() => _PinInputSheetState();
}

class _PinInputSheetState extends State<_PinInputSheet> {
  String _entered = '';

  void _onKey(String digit) {
    if (_entered.length >= 6) return;
    setState(() => _entered += digit);
    if (_entered.length == 6) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) Navigator.of(context).pop(_entered);
      });
    }
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Widget _buildDot(int index) {
    final filled = index < _entered.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.primary : AppColors.border,
        border: Border.all(color: AppColors.primary, width: 2),
      ),
    );
  }

  Widget _buildKey(String label, {VoidCallback? onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 22,
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
    return Container(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Masukkan 6 digit PIN',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildDot(i),
              )),
            ),
            const SizedBox(height: 28),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
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
    );
  }
}
