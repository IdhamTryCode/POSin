import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../categories/models/category_model.dart';
import '../../categories/providers/category_provider.dart';
import '../models/product_model.dart';
import '../providers/product_provider.dart';
import 'product_form_screen.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productProvider);
    final categories = ref.watch(categoryProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Menu'),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.restaurant_menu, size: 64, color: AppColors.border),
              SizedBox(height: 12),
              Text('Belum ada menu', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            ]));
          }

          // Grouping: per kategori + "Tanpa Kategori"
          final grouped = <_Group>[];

          for (final cat in categories) {
            final items = products.where((p) => p.categoryId == cat.id).toList();
            if (items.isNotEmpty) grouped.add(_Group(category: cat, products: items));
          }
          final uncategorized = products.where((p) => p.categoryId == null || !categories.any((c) => c.id == p.categoryId)).toList();
          if (uncategorized.isNotEmpty) grouped.add(_Group(category: null, products: uncategorized));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: grouped.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _CategorySection(group: grouped[i]),
          );
        },
      ),
    );
  }
}

class _Group {
  final CategoryModel? category;
  final List<ProductModel> products;
  const _Group({required this.category, required this.products});
}

// ── Collapsible section per kategori ─────────────────────────────────────────

class _CategorySection extends ConsumerStatefulWidget {
  final _Group group;
  const _CategorySection({required this.group});

  @override
  ConsumerState<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends ConsumerState<_CategorySection>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _ctrl;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _rotate = Tween(begin: 0.0, end: 0.5).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.value = 1; // mulai expanded
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.group.category;
    final color = cat != null ? Color(cat.color) : AppColors.textSecondary;
    final count = widget.group.products.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        // Header
        InkWell(
          onTap: _toggle,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cat?.name ?? 'Tanpa Kategori',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$count item',
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              RotationTransition(
                turns: _rotate,
                child: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
              ),
            ]),
          ),
        ),
        // Items
        AnimatedCrossFade(
          firstChild: Column(children: [
            const Divider(height: 1),
            ...widget.group.products.asMap().entries.map((e) {
              final isLast = e.key == widget.group.products.length - 1;
              return _ProductTile(product: e.value, isLast: isLast);
            }),
          ]),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ]),
    );
  }
}

// ── Product tile ──────────────────────────────────────────────────────────────

class _ProductTile extends ConsumerWidget {
  final ProductModel product;
  final bool isLast;
  const _ProductTile({required this.product, required this.isLast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52, height: 52,
              child: p.imagePath != null && p.imagePath!.isNotEmpty
                  ? Image.network(p.imagePath!, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.background,
                          child: Icon(Icons.fastfood, color: AppColors.border, size: 26)))
                  : const ColoredBox(color: AppColors.background,
                      child: Icon(Icons.fastfood, color: AppColors.border, size: 26)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600,
              color: p.isActive ? AppColors.textPrimary : AppColors.textSecondary,
            )),
            const SizedBox(height: 2),
            Text(fmt.format(p.price),
              style: const TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.bold)),
          ])),
          if (!p.isActive)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(6)),
              child: const Text('Nonaktif', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'edit') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
              } else if (val == 'toggle') {
                ref.read(productProvider.notifier).updateProduct(p.copyWith(isActive: !p.isActive));
              } else if (val == 'delete') {
                _confirmDelete(context, ref, p);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit',
                child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), dense: true)),
              PopupMenuItem(value: 'toggle',
                child: ListTile(
                  leading: Icon(p.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  title: Text(p.isActive ? 'Nonaktifkan' : 'Aktifkan'), dense: true)),
              const PopupMenuItem(value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text('Hapus', style: TextStyle(color: AppColors.error)), dense: true)),
            ],
          ),
        ]),
      ),
      if (!isLast) const Divider(height: 1, indent: 80),
    ]);
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ProductModel p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Menu?'),
        content: Text('"${p.name}" akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              ref.read(productProvider.notifier).delete(p.id);
              Navigator.pop(context);
            },
            child: const Text('Hapus', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
