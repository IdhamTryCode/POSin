import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../orders/models/order_model.dart';
import '../../orders/providers/order_provider.dart';
import '../../orders/screens/order_detail_screen.dart';

final _reportRangeProvider = StateProvider<String>((ref) => 'Hari Ini');

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(_reportRangeProvider);
    final ordersAsync = ref.watch(orderProvider);
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    final orders = ordersAsync.valueOrNull ?? [];
    final filtered = _filterOrders(orders, range);
    final total = filtered.fold<double>(0, (s, o) => s + o.total);

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: Column(
        children: [
          // Range selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: ['Hari Ini', 'Minggu Ini', 'Bulan Ini'].map((r) {
                final selected = range == r;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => ref.read(_reportRangeProvider.notifier).state = r,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                      ),
                      child: Text(
                        r,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          color: selected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Summary cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _SummaryCard(label: 'Total Transaksi', value: '${filtered.length}', icon: Icons.receipt_long_outlined, color: AppColors.primary)),
                const SizedBox(width: 12),
                Expanded(child: _SummaryCard(label: 'Total Pendapatan', value: fmt.format(total), icon: Icons.payments_outlined, color: AppColors.success)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Riwayat Transaksi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart, size: 64, color: AppColors.border),
                        SizedBox(height: 12),
                        Text('Belum ada transaksi', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final o = filtered[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(builder: (_) => OrderDetailScreen(order: o)),
                        ),
                        child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.check_circle_outline, color: AppColors.success),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('#${o.orderNumber}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text(dateFmt.format(DateTime.parse(o.createdAt)),
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(fmt.format(o.total),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.border,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(o.paymentMethod, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<OrderModel> _filterOrders(List<OrderModel> orders, String range) {
    final now = DateTime.now();
    return orders.where((o) {
      final date = DateTime.parse(o.createdAt);
      switch (range) {
        case 'Hari Ini':
          return date.year == now.year && date.month == now.month && date.day == now.day;
        case 'Minggu Ini':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return date.isAfter(DateTime(weekStart.year, weekStart.month, weekStart.day).subtract(const Duration(seconds: 1)));
        case 'Bulan Ini':
          return date.year == now.year && date.month == now.month;
        default:
          return true;
      }
    }).toList();
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
