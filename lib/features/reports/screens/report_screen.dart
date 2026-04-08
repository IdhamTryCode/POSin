import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../core/constants/app_colors.dart';
import '../../orders/models/order_model.dart';
import '../../orders/providers/order_provider.dart';
import '../../orders/screens/order_detail_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../services/report_pdf_service.dart';

final _reportRangeProvider = StateProvider<String>((ref) => 'Hari Ini');
final _customRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Aggregates all order_items for given orders into top products by qty + revenue.
final _topProductsProvider = FutureProvider.family<List<_ProductStat>, List<String>>((ref, orderIds) async {
  if (orderIds.isEmpty) return [];
  final notifier = ref.read(orderProvider.notifier);
  final Map<String, _ProductStat> agg = {};
  for (final orderId in orderIds) {
    final items = await notifier.getOrderItems(orderId);
    for (final it in items) {
      final existing = agg[it.productId];
      if (existing == null) {
        agg[it.productId] = _ProductStat(name: it.productName, qty: it.qty, revenue: it.subtotal);
      } else {
        agg[it.productId] = _ProductStat(
          name: existing.name,
          qty: existing.qty + it.qty,
          revenue: existing.revenue + it.subtotal,
        );
      }
    }
  }
  final list = agg.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
  return list.take(5).toList();
});

class _ProductStat {
  final String name;
  final int qty;
  final double revenue;
  const _ProductStat({required this.name, required this.qty, required this.revenue});
}

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(_reportRangeProvider);
    final customRange = ref.watch(_customRangeProvider);
    final orders = ref.watch(orderProvider).valueOrNull ?? [];
    final filtered = _filterOrders(orders, range, customRange);
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final total = filtered.fold<double>(0, (s, o) => s + o.total);
    final cashTotal = filtered.where((o) => o.paymentMethod == 'Tunai').fold<double>(0, (s, o) => s + o.total);
    final qrisTotal = filtered.where((o) => o.paymentMethod == 'QRIS').fold<double>(0, (s, o) => s + o.total);
    final cashCount = filtered.where((o) => o.paymentMethod == 'Tunai').length;
    final qrisCount = filtered.where((o) => o.paymentMethod == 'QRIS').length;

    final chartInfo = _buildChartInfo(filtered, range);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.gradientPrimary),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Laporan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            Text('Ringkasan penjualan', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            onPressed: () => _exportPdf(context, ref, filtered, range, customRange),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Range selector
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: ['Hari Ini', '7 Hari', '30 Hari', 'Custom'].map((r) {
                        final selected = range == r;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (r == 'Custom') {
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  initialDateRange: customRange ?? DateTimeRange(
                                    start: DateTime.now().subtract(const Duration(days: 7)),
                                    end: DateTime.now(),
                                  ),
                                );
                                if (picked != null) {
                                  ref.read(_customRangeProvider.notifier).state = picked;
                                  ref.read(_reportRangeProvider.notifier).state = 'Custom';
                                }
                              } else {
                                ref.read(_reportRangeProvider.notifier).state = r;
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                r,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
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
                  if (range == 'Custom' && customRange != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${DateFormat('d MMM yyyy', 'id_ID').format(customRange.start)}  →  ${DateFormat('d MMM yyyy', 'id_ID').format(customRange.end)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Summary cards
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                Expanded(child: _SummaryCard(
                  label: 'Total Transaksi',
                  value: '${filtered.length}',
                  sub: 'order',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary,
                )),
                const SizedBox(width: 10),
                Expanded(child: _SummaryCard(
                  label: 'Total Pendapatan',
                  value: fmt.format(total),
                  sub: 'total',
                  icon: Icons.payments_outlined,
                  color: AppColors.success,
                )),
              ]),
            ),
          ),

          // Revenue line chart
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _ChartCard(
                title: 'Tren Pendapatan',
                subtitle: _chartSubtitle(range),
                child: filtered.isEmpty
                    ? _EmptyChart()
                    : SizedBox(
                        height: 190,
                        child: LineChart(
                          LineChartData(
                            minX: 0,
                            maxX: chartInfo.maxX,
                            minY: 0,
                            maxY: chartInfo.maxY * 1.3,
                            clipData: const FlClipData.all(),
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: chartInfo.maxY > 0 ? chartInfo.maxY / 4 : 1,
                              getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 52,
                                  getTitlesWidget: (val, _) {
                                    if (val == 0) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Text(_shortCurrency(val),
                                        style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 26,
                                  interval: 1,
                                  getTitlesWidget: (val, _) => _bottomLabel(val.toInt(), range, chartInfo.labels),
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: chartInfo.spots,
                                isCurved: false,
                                color: AppColors.primary,
                                barWidth: 2,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                                    radius: 4,
                                    color: Colors.white,
                                    strokeWidth: 2,
                                    strokeColor: AppColors.primary,
                                  ),
                                ),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) => AppColors.textPrimary,
                                tooltipRoundedRadius: 8,
                                getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                                  fmt.format(s.y),
                                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                )).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // Top products
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _TopProductsCard(orderIds: filtered.map((o) => o.id).toList()),
            ),
          ),

          // Best weekday
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _WeekdayCard(orders: filtered),
            ),
          ),

          // Payment method donut chart
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _ChartCard(
                title: 'Metode Pembayaran',
                subtitle: '${filtered.length} transaksi',
                child: filtered.isEmpty
                    ? _EmptyChart()
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                          SizedBox(
                            width: 130,
                            height: 130,
                            child: PieChart(
                              PieChartData(
                                sections: _buildPieSections(cashTotal, qrisTotal),
                                centerSpaceRadius: 40,
                                sectionsSpace: 3,
                                startDegreeOffset: -90,
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _PaymentLegend(
                                  color: AppColors.primary,
                                  label: 'Tunai',
                                  amount: fmt.format(cashTotal),
                                  amountValue: cashTotal,
                                  count: cashCount,
                                  total: total,
                                ),
                                const SizedBox(height: 14),
                                _PaymentLegend(
                                  color: AppColors.secondary,
                                  label: 'QRIS',
                                  amount: fmt.format(qrisTotal),
                                  amountValue: qrisTotal,
                                  count: qrisCount,
                                  total: total,
                                ),
                              ],
                            ),
                            ),
                          ),
                        ],
                      ),
                      ),
              ),
            ),
          ),

          // Transaction list header
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text('Riwayat Transaksi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),

          // Transaction list
          filtered.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: const Column(children: [
                      Icon(Icons.bar_chart, size: 64, color: AppColors.border),
                      SizedBox(height: 12),
                      Text('Belum ada transaksi', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                    ]),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final o = filtered[i];
                      final isCash = o.paymentMethod == 'Tunai';
                      final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
                      return Dismissible(
                        key: ValueKey(o.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.delete_outline, color: Colors.white),
                              SizedBox(width: 6),
                              Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              title: const Text('Hapus Pesanan?'),
                              content: Text('Pesanan #${o.orderNumber} akan dihapus permanen dari riwayat dan cloud.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                                  child: const Text('Hapus'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (_) async {
                          final ok = await ref.read(orderProvider.notifier).deleteOrder(o.id);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(ok ? 'Pesanan dihapus' : 'Gagal menghapus pesanan'),
                                backgroundColor: ok ? AppColors.success : AppColors.error,
                              ),
                            );
                          }
                        },
                        child: GestureDetector(
                        onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => OrderDetailScreen(order: o))),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(children: [
                            Container(
                              width: 42, height: 42,
                              decoration: BoxDecoration(
                                color: (isCash ? AppColors.primary : AppColors.secondary).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isCash ? Icons.payments_outlined : Icons.qr_code_rounded,
                                color: isCash ? AppColors.primary : AppColors.secondary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                (o.dailyNumber ?? '').isNotEmpty ? '#${o.dailyNumber}' : '#${o.orderNumber}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '${dateFmt.format(DateTime.parse(o.createdAt))} • ${o.orderNumber}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(fmt.format(o.total),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                              Container(
                                margin: const EdgeInsets.only(top: 3),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isCash ? AppColors.primary : AppColors.secondary).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(o.paymentMethod,
                                  style: TextStyle(fontSize: 11, color: isCash ? AppColors.primary : AppColors.secondary, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ]),
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

  // ── Helpers ──────────────────────────────────────────────────────────────────

  List<OrderModel> _filterOrders(List<OrderModel> orders, String range, DateTimeRange? custom) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return orders.where((o) {
      final date = DateTime.parse(o.createdAt);
      switch (range) {
        case 'Hari Ini':
          return date.year == now.year && date.month == now.month && date.day == now.day;
        case '7 Hari':
          return !date.isBefore(today.subtract(const Duration(days: 6)));
        case '30 Hari':
          return !date.isBefore(today.subtract(const Duration(days: 29)));
        case 'Custom':
          if (custom == null) return false;
          final s = DateTime(custom.start.year, custom.start.month, custom.start.day);
          final e = DateTime(custom.end.year, custom.end.month, custom.end.day, 23, 59, 59);
          return !date.isBefore(s) && !date.isAfter(e);
        default:
          return true;
      }
    }).toList();
  }

  (DateTime, DateTime) _resolveRangeDates(String range, DateTimeRange? custom) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (range) {
      case 'Hari Ini':
        return (today, today);
      case '7 Hari':
        return (today.subtract(const Duration(days: 6)), today);
      case '30 Hari':
        return (today.subtract(const Duration(days: 29)), today);
      case 'Custom':
        if (custom != null) return (custom.start, custom.end);
        return (today, today);
      default:
        return (today, today);
    }
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref, List<OrderModel> orders, String range, DateTimeRange? custom) async {
    if (orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada transaksi untuk diekspor')),
      );
      return;
    }
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    final (start, end) = _resolveRangeDates(range, custom);
    final pdf = await ReportPdfService.build(
      orders: orders,
      start: start,
      end: end,
      storeName: settings['store_name'] ?? 'Toko Saya',
      storeAddress: settings['store_address'],
      storePhone: settings['store_phone'],
    );
    final filename = 'laporan_${DateFormat('yyyyMMdd').format(start)}_${DateFormat('yyyyMMdd').format(end)}.pdf';
    await Printing.sharePdf(bytes: await pdf.save(), filename: filename);
  }

  _ChartInfo _buildChartInfo(List<OrderModel> orders, String range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final Map<int, double> totals = {};
    final Map<int, String> labels = {};

    if (range == 'Hari Ini') {
      for (final o in orders) {
        final h = DateTime.parse(o.createdAt).hour;
        totals[h] = (totals[h] ?? 0) + o.total;
        labels[h] = h.toString().padLeft(2, '0');
      }
    } else {
      // Index 0 = hari terlama, index (days-1) = hari ini
      final int days = range == '7 Hari' ? 7 : 30;
      const dayNames = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];

      for (int i = 0; i < days; i++) {
        totals[i] = 0;
        final date = today.subtract(Duration(days: days - 1 - i));
        labels[i] = range == '7 Hari'
            ? dayNames[date.weekday % 7]
            : '${date.day}/${date.month}';
      }

      for (final o in orders) {
        final d = DateTime.parse(o.createdAt);
        final orderDay = DateTime(d.year, d.month, d.day);
        final daysAgo = today.difference(orderDay).inDays;
        final index = (days - 1) - daysAgo;
        if (index >= 0 && index < days) {
          totals[index] = (totals[index] ?? 0) + o.total;
        }
      }
    }

    final sortedKeys = totals.keys.toList()..sort();
    final maxY = totals.values.isEmpty ? 0.0 : totals.values.reduce((a, b) => a > b ? a : b);
    final spots = sortedKeys.map((k) => FlSpot(k.toDouble(), totals[k]!)).toList();
    final maxX = range == 'Hari Ini'
        ? (sortedKeys.isEmpty ? 23.0 : sortedKeys.last.toDouble())
        : range == '7 Hari' ? 6.0 : 29.0;

    return _ChartInfo(spots: spots, labels: labels, maxY: maxY, maxX: maxX);
  }

  List<PieChartSectionData> _buildPieSections(double cash, double qris) {
    final total = cash + qris;
    if (total == 0) {
      return [PieChartSectionData(value: 1, color: AppColors.border, radius: 36, showTitle: false)];
    }
    return [
      PieChartSectionData(
        value: cash,
        color: AppColors.primary,
        radius: 44,
        showTitle: false,
      ),
      PieChartSectionData(
        value: qris,
        color: AppColors.secondary,
        radius: 44,
        showTitle: false,
      ),
    ];
  }

  String _chartSubtitle(String range) => switch (range) {
    'Hari Ini' => 'Per jam',
    '7 Hari' => '7 hari terakhir',
    _ => '30 hari terakhir',
  };

  static String _shortCurrency(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}jt';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}rb';
    return val.toStringAsFixed(0);
  }

  static Widget _bottomLabel(int val, String range, Map<int, String> labels) {
    final label = labels[val];
    if (label == null) return const SizedBox.shrink();

    // 30 Hari: tampilkan setiap 7 indeks agar tidak crowded
    if (range == '30 Hari' && val % 7 != 0 && val != 29) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class _ChartInfo {
  final List<FlSpot> spots;
  final Map<int, String> labels;
  final double maxY;
  final double maxX;
  const _ChartInfo({required this.spots, required this.labels, required this.maxY, required this.maxX});
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _ChartCard({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 100,
      child: Center(child: Text('Belum ada data', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  const _SummaryCard({required this.label, required this.value, required this.sub, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ]),
    );
  }
}

// ── Top Products Card ────────────────────────────────────────────────────────

class _TopProductsCard extends ConsumerWidget {
  final List<String> orderIds;
  const _TopProductsCard({required this.orderIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return _ChartCard(
      title: 'Produk Terlaris',
      subtitle: 'Top 5',
      child: orderIds.isEmpty
          ? _EmptyChart()
          : ref.watch(_topProductsProvider(orderIds)).when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
              error: (_, _) => _EmptyChart(),
              data: (stats) {
                if (stats.isEmpty) return _EmptyChart();
                final maxRev = stats.map((s) => s.revenue).reduce((a, b) => a > b ? a : b);
                return Column(
                  children: List.generate(stats.length, (i) {
                    final s = stats[i];
                    final ratio = maxRev > 0 ? s.revenue / maxRev : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(s.name,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            ),
                            Text('${s.qty}x', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            const SizedBox(width: 8),
                            Text(fmt.format(s.revenue),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                          ]),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio,
                              backgroundColor: AppColors.border,
                              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                              minHeight: 5,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                );
              },
            ),
    );
  }
}

// ── Weekday Card ─────────────────────────────────────────────────────────────

class _WeekdayCard extends StatelessWidget {
  final List<OrderModel> orders;
  const _WeekdayCard({required this.orders});

  static const _names = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    if (orders.isEmpty) {
      return _ChartCard(title: 'Performa Hari', subtitle: 'Per hari', child: _EmptyChart());
    }
    final Map<int, double> dayRevenue = {for (var i = 1; i <= 7; i++) i: 0};
    final Map<int, int> dayCount = {for (var i = 1; i <= 7; i++) i: 0};
    for (final o in orders) {
      final d = DateTime.parse(o.createdAt).weekday;
      dayRevenue[d] = (dayRevenue[d] ?? 0) + o.total;
      dayCount[d] = (dayCount[d] ?? 0) + 1;
    }
    final maxVal = dayRevenue.values.reduce((a, b) => a > b ? a : b);
    final bestDay = dayRevenue.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    return _ChartCard(
      title: 'Performa Hari',
      subtitle: 'Hari terbaik: ${_names[bestDay - 1]}',
      child: Column(
        children: List.generate(7, (i) {
          final dayIdx = i + 1;
          final v = dayRevenue[dayIdx] ?? 0;
          final c = dayCount[dayIdx] ?? 0;
          final ratio = maxVal > 0 ? v / maxVal : 0.0;
          final isBest = dayIdx == bestDay;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(_names[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isBest ? FontWeight.w800 : FontWeight.w500,
                      color: isBest ? AppColors.warning : AppColors.textPrimary,
                    )),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(isBest ? AppColors.warning : AppColors.primary),
                      minHeight: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: Text(
                    v > 0 ? fmt.format(v) : '-',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 28,
                  child: Text(
                    c > 0 ? '${c}x' : '',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _PaymentLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String amount;
  final double amountValue;
  final int count;
  final double total;
  const _PaymentLegend({
    required this.color,
    required this.label,
    required this.amount,
    required this.amountValue,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (amountValue / total).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
          child: Text('$count transaksi', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Text(amount, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: ratio,
          backgroundColor: AppColors.border,
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 5,
        ),
      ),
    ]);
  }
}
