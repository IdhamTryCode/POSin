import 'package:fl_chart/fl_chart.dart';
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
    final orders = ref.watch(orderProvider).valueOrNull ?? [];
    final filtered = _filterOrders(orders, range);
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final total = filtered.fold<double>(0, (s, o) => s + o.total);
    final cashTotal = filtered.where((o) => o.paymentMethod == 'Tunai').fold<double>(0, (s, o) => s + o.total);
    final qrisTotal = filtered.where((o) => o.paymentMethod == 'QRIS').fold<double>(0, (s, o) => s + o.total);
    final cashCount = filtered.where((o) => o.paymentMethod == 'Tunai').length;
    final qrisCount = filtered.where((o) => o.paymentMethod == 'QRIS').length;
    final avgOrder = filtered.isEmpty ? 0.0 : total / filtered.length;

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
      ),
      body: CustomScrollView(
        slivers: [
          // Range selector
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: ['Hari Ini', 'Minggu Ini', 'Bulan Ini'].map((r) {
                    final selected = range == r;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => ref.read(_reportRangeProvider.notifier).state = r,
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
                const SizedBox(width: 10),
                Expanded(child: _SummaryCard(
                  label: 'Rata-rata',
                  value: fmt.format(avgOrder),
                  sub: 'per order',
                  icon: Icons.trending_up_rounded,
                  color: AppColors.secondary,
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
                      return GestureDetector(
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
                              Text('#${o.orderNumber}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(dateFmt.format(DateTime.parse(o.createdAt)),
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  List<OrderModel> _filterOrders(List<OrderModel> orders, String range) {
    final now = DateTime.now();
    return orders.where((o) {
      final date = DateTime.parse(o.createdAt);
      switch (range) {
        case 'Hari Ini':
          return date.year == now.year && date.month == now.month && date.day == now.day;
        case 'Minggu Ini':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return !date.isBefore(DateTime(weekStart.year, weekStart.month, weekStart.day));
        case 'Bulan Ini':
          return date.year == now.year && date.month == now.month;
        default:
          return true;
      }
    }).toList();
  }

  _ChartInfo _buildChartInfo(List<OrderModel> orders, String range) {
    final Map<int, double> totals = {};
    final Map<int, String> labels = {};

    if (range == 'Minggu Ini') {
      const days = ['', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
      for (int i = 1; i <= 7; i++) { totals[i] = 0; labels[i] = days[i]; }
    } else if (range == 'Bulan Ini') {
      final now = DateTime.now();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      for (int i = 1; i <= daysInMonth; i++) { totals[i] = 0; labels[i] = '$i'; }
    }

    for (final o in orders) {
      final d = DateTime.parse(o.createdAt);
      final int key;
      final String label;
      if (range == 'Hari Ini') {
        key = d.hour;
        label = d.hour.toString().padLeft(2, '0');
      } else if (range == 'Minggu Ini') {
        key = d.weekday;
        label = labels[d.weekday]!;
      } else {
        key = d.day;
        label = d.day.toString();
      }
      totals[key] = (totals[key] ?? 0) + o.total;
      labels[key] = label;
    }

    final sortedKeys = totals.keys.toList()..sort();
    final maxY = totals.values.isEmpty ? 0.0 : totals.values.reduce((a, b) => a > b ? a : b);

    final spots = sortedKeys.map((k) => FlSpot(k.toDouble(), totals[k]!)).toList();

    return _ChartInfo(spots: spots, labels: labels, maxY: maxY);
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
    'Minggu Ini' => 'Per hari',
    _ => 'Per tanggal',
  };

  static String _shortCurrency(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}jt';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}rb';
    return val.toStringAsFixed(0);
  }

  static Widget _bottomLabel(int val, String range, Map<int, String> labels) {
    final label = labels[val];
    if (label == null) return const SizedBox.shrink();

    // Bulan Ini: only show every 5th day
    if (range == 'Bulan Ini' && val % 5 != 0 && val != 1) return const SizedBox.shrink();

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
  const _ChartInfo({required this.spots, required this.labels, required this.maxY});
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
