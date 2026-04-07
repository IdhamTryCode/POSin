import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../products/models/product_model.dart';
import '../../products/models/variant_option_model.dart';

class SelectedVariant {
  final String groupId;
  final String groupName;
  final VariantOptionModel option;

  const SelectedVariant({
    required this.groupId,
    required this.groupName,
    required this.option,
  });

  String get label => '$groupName: ${option.name}';
}

class CartItem {
  final ProductModel product;
  final int qty;
  final List<SelectedVariant> selectedVariants;
  final String? note;

  const CartItem({
    required this.product,
    required this.qty,
    this.selectedVariants = const [],
    this.note,
  });

  double get extraPrice =>
      selectedVariants.fold(0, (s, v) => s + v.option.priceModifier);

  double get effectivePrice => product.price + extraPrice;

  double get subtotal => effectivePrice * qty;

  String get variantLabel => selectedVariants.map((v) => v.label).join(', ');

  // Cart key includes note hash so items with different notes are kept separate
  String get cartKey =>
      '${product.id}_${selectedVariants.map((v) => v.option.id).join('_')}_${note ?? ''}';

  CartItem copyWith({int? qty, String? note, bool clearNote = false}) => CartItem(
        product: product,
        qty: qty ?? this.qty,
        selectedVariants: selectedVariants,
        note: clearNote ? null : (note ?? this.note),
      );
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0, (s, i) => s + i.subtotal);
});

final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold(0, (s, i) => s + i.qty);
});

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addItem(ProductModel product, {List<SelectedVariant> variants = const []}) {
    final newItem = CartItem(product: product, qty: 1, selectedVariants: variants);
    final index = state.indexWhere((i) => i.cartKey == newItem.cartKey);
    if (index >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index) state[i].copyWith(qty: state[i].qty + 1) else state[i],
      ];
    } else {
      state = [...state, newItem];
    }
  }

  void removeItem(String cartKey) {
    final index = state.indexWhere((i) => i.cartKey == cartKey);
    if (index < 0) return;
    if (state[index].qty > 1) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index) state[i].copyWith(qty: state[i].qty - 1) else state[i],
      ];
    } else {
      state = state.where((i) => i.cartKey != cartKey).toList();
    }
  }

  void deleteItem(String cartKey) {
    state = state.where((i) => i.cartKey != cartKey).toList();
  }

  void setItemNote(String cartKey, String? note) {
    final trimmed = (note ?? '').trim();
    final normalized = trimmed.isEmpty ? null : trimmed;
    state = [
      for (final item in state)
        if (item.cartKey == cartKey)
          item.copyWith(note: normalized, clearNote: normalized == null)
        else
          item,
    ];
  }

  void clear() => state = [];
}
