import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/sync/app_sync_service.dart';
import '../../categories/providers/category_provider.dart';
import '../../products/models/product_model.dart';
import '../../products/models/variant_group_model.dart';
import '../../products/providers/product_provider.dart';
import '../../products/providers/variant_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/cart_provider.dart';
import 'checkout_sheet.dart';

final _selectedCategoryProvider = StateProvider<String?>((ref) => null);

class CashierScreen extends ConsumerWidget {
  const CashierScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(appSyncServiceProvider).syncAllFromCloud();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryProvider).valueOrNull ?? [];
    final selectedCategory = ref.watch(_selectedCategoryProvider);
    final products = ref.watch(filteredProductProvider(selectedCategory));
    final cartCount = ref.watch(cartCountProvider);
    final cartTotal = ref.watch(cartTotalProvider);
    final cart = ref.watch(cartProvider);
    final storeName = ref.watch(settingsProvider).valueOrNull?['store_name'] ?? 'POSin';
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.gradientPrimary),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('POSin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
            Text(storeName, style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          if (cartCount > 0)
            TextButton.icon(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 18),
              label: const Text('Kosongkan', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          IconButton(
            onPressed: () => _refresh(ref),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          if (categories.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                children: [
                  _CategoryChip(label: 'Semua', selected: selectedCategory == null, color: AppColors.primary,
                      onTap: () => ref.read(_selectedCategoryProvider.notifier).state = null),
                  ...categories.map((c) => _CategoryChip(label: c.name, selected: selectedCategory == c.id,
                      color: Color(c.color), onTap: () => ref.read(_selectedCategoryProvider.notifier).state = c.id)),
                ],
              ),
            ),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.restaurant_menu, size: 64, color: AppColors.border),
                    SizedBox(height: 12),
                    Text('Belum ada menu', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                  ]))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.85),
                    itemCount: products.length,
                    itemBuilder: (_, i) => _ProductCard(product: products[i]),
                  ),
          ),
          if (cart.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, -6)),
                ],
              ),
              child: Column(
                children: [
                  Center(child: Container(width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                  ...cart.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        if (item.variantLabel.isNotEmpty)
                          Text(item.variantLabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ])),
                      Row(children: [
                        _QtyButton(icon: Icons.remove, onTap: () => ref.read(cartProvider.notifier).removeItem(item.cartKey)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('${item.qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        _QtyButton(icon: Icons.add, color: AppColors.primary,
                          onTap: () => ref.read(cartProvider.notifier).addItem(item.product, variants: item.selectedVariants)),
                      ]),
                      const SizedBox(width: 8),
                      SizedBox(width: 88, child: Text(fmt.format(item.subtotal),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                  )),
                  const Divider(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$cartCount item', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ]),
                    Text(fmt.format(cartTotal), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => CheckoutSheet(total: cartTotal, cart: cart)),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Bayar Sekarang'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal, fontSize: 14)),
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final qty = cart.where((i) => i.product.id == product.id).fold(0, (s, i) => s + i.qty);
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final isInCart = qty > 0;
    return GestureDetector(
      onTap: () => _onTap(context, ref),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isInCart ? AppColors.primary : AppColors.border, width: isInCart ? 2 : 1),
          boxShadow: isInCart
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: product.imagePath != null && product.imagePath!.isNotEmpty
                      ? Image.network(product.imagePath!, fit: BoxFit.cover, width: double.infinity,
                          errorBuilder: (_, _, _) => _placeholder())
                      : _placeholder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(fmt.format(product.price),
                style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.bold)),
            ]),
          ),
          if (isInCart)
            Positioned(top: 8, right: 8,
              child: Container(width: 26, height: 26,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Center(child: Text('$qty', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(color: AppColors.background,
    child: const Center(child: Icon(Icons.fastfood, size: 48, color: AppColors.border)));

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final groups = await ref.read(variantGroupProvider(product.id).future);
    if (groups.isEmpty) {
      ref.read(cartProvider.notifier).addItem(product);
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VariantPickerSheet(product: product, groups: groups),
    );
  }
}

class _VariantPickerSheet extends ConsumerStatefulWidget {
  final ProductModel product;
  final List<VariantGroupModel> groups;
  const _VariantPickerSheet({required this.product, required this.groups});

  @override
  ConsumerState<_VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends ConsumerState<_VariantPickerSheet> {
  final Map<String, SelectedVariant> _selected = {};
  final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  double get _extraPrice => _selected.values.fold(0, (s, v) => s + v.option.priceModifier);
  double get _totalPrice => widget.product.price + _extraPrice;

  bool get _canAdd {
    final requiredGroups = widget.groups.where((g) => g.isRequired);
    return requiredGroups.every((g) => _selected.containsKey(g.id));
  }

  void _addToCart() {
    ref.read(cartProvider.notifier).addItem(widget.product, variants: _selected.values.toList());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(widget.product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(fmt.format(widget.product.price), style: const TextStyle(fontSize: 15, color: AppColors.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            ...widget.groups.map((group) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(group.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (group.isRequired)
                  Container(margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Wajib', style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: group.options.map((opt) {
                final isSelected = _selected[group.id]?.option.id == opt.id;
                return GestureDetector(
                  onTap: () => setState(() => _selected[group.id] = SelectedVariant(
                      groupId: group.id, groupName: group.name, option: opt)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 2 : 1),
                    ),
                    child: Text(
                      opt.priceModifier > 0 ? '${opt.name} (+${fmt.format(opt.priceModifier)})' : opt.name,
                      style: TextStyle(fontSize: 14, color: isSelected ? Colors.white : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 16),
            ])),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                Text(fmt.format(_totalPrice), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ]),
              SizedBox(
                width: 160,
                child: ElevatedButton(
                  onPressed: _canAdd ? _addToCart : null,
                  child: const Text('Tambah ke Keranjang'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: (color ?? AppColors.textSecondary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
      ),
    );
  }
}
