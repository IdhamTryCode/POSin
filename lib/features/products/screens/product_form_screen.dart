import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../categories/providers/category_provider.dart';
import '../models/product_model.dart';
import '../models/variant_group_model.dart';
import '../providers/product_provider.dart';
import '../providers/variant_provider.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final ProductModel? product;
  const ProductFormScreen({super.key, this.product});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  String? _selectedCategoryId;
  String? _imageUrl;
  File? _imageFile;
  bool _loading = false;
  final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool get _isEdit => widget.product != null;
  String? get _productId => widget.product?.id ?? const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _priceController = TextEditingController(
      text: widget.product != null ? widget.product!.price.toInt().toString() : '',
    );
    _selectedCategoryId = widget.product?.categoryId;
    _imageUrl = widget.product?.imagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _imageFile = File(picked.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.replaceAll('.', '')) ?? 0;

    // Upload gambar jika ada yang baru dipilih
    String? finalImageUrl = _imageUrl;
    if (_imageFile != null) {
      final pid = _isEdit ? widget.product!.id : _productId!;
      finalImageUrl = await SupabaseService.instance.uploadProductImage(pid, _imageFile!);
    }

    if (_isEdit) {
      await ref.read(productProvider.notifier).updateProduct(
        widget.product!.copyWith(name: name, price: price, categoryId: _selectedCategoryId, imagePath: finalImageUrl),
      );
    } else {
      await ref.read(productProvider.notifier).add(
        name: name, price: price, categoryId: _selectedCategoryId, imagePath: finalImageUrl,
      );
    }

    setState(() => _loading = false);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryProvider).valueOrNull ?? [];
    // Guard: jika category dari produk sudah tidak ada di list, fallback ke null
    final validCategoryId = categories.any((c) => c.id == _selectedCategoryId)
        ? _selectedCategoryId
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Menu' : 'Tambah Menu')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Foto
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _imageFile != null
                        ? Image.file(_imageFile!, fit: BoxFit.cover)
                        : (_imageUrl != null && _imageUrl!.isNotEmpty
                            ? Image.network(_imageUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _photoPlaceholder())
                            : _photoPlaceholder()),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(child: Text('Tap untuk ganti foto', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nama Menu'),
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 16),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Harga', prefixText: 'Rp '),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Harga tidak boleh kosong';
                final p = double.tryParse(v.replaceAll('.', ''));
                if (p == null || p <= 0) return 'Harga tidak valid';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: validCategoryId,
              decoration: const InputDecoration(labelText: 'Kategori (opsional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tanpa Kategori')),
                ...categories.map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Row(children: [
                    Container(width: 14, height: 14, decoration: BoxDecoration(color: Color(c.color), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(c.name),
                  ]),
                )),
              ],
              onChanged: (val) => setState(() => _selectedCategoryId = val),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Menu'),
            ),
            // Varian — hanya tampil jika edit
            if (_isEdit) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 8),
              _VariantSection(productId: widget.product!.id),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.camera_alt_outlined, color: AppColors.textSecondary, size: 32),
    const SizedBox(height: 4),
    Text('Foto', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
  ]);
}

// ── Variant Section ──────────────────────────────────────────────────────────

class _VariantSection extends ConsumerWidget {
  final String productId;
  const _VariantSection({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(variantGroupProvider(productId));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Varian', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        TextButton.icon(
          onPressed: () => _showGroupForm(context, ref, null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Tambah Grup'),
        ),
      ]),
      const Text('Contoh: Ukuran, Rasa, Tingkat Kepedasan',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Error: $e'),
        data: (groups) => groups.isEmpty
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('Belum ada varian', style: TextStyle(color: AppColors.textSecondary))),
              )
            : Column(children: groups.map((g) => _VariantGroupTile(
                group: g,
                onEditGroup: () => _showGroupForm(context, ref, g),
                onDeleteGroup: () => ref.read(variantGroupProvider(productId).notifier).deleteGroup(g.id),
                onAddOption: () => _showOptionForm(context, ref, g.id),
                onDeleteOption: (optId) => ref.read(variantGroupProvider(productId).notifier).deleteOption(optId),
              )).toList()),
      ),
    ]);
  }

  void _showGroupForm(BuildContext context, WidgetRef ref, VariantGroupModel? group) {
    final nameCtrl = TextEditingController(text: group?.name ?? '');
    bool isRequired = group?.isRequired ?? true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(group == null ? 'Tambah Grup Varian' : 'Edit Grup'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Grup'), autofocus: true),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Wajib dipilih'),
              const Spacer(),
              Switch(value: isRequired, onChanged: (v) => setState(() => isRequired = v)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (group == null) {
                  _addGroup(ref, name, isRequired);
                } else {
                  ref.read(variantGroupProvider(group.productId).notifier).updateGroup(group.copyWith(name: name, isRequired: isRequired));
                }
                Navigator.pop(ctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _addGroup(WidgetRef ref, String name, bool isRequired) {
    ref.read(variantGroupProvider(productId).notifier).addGroup(name, isRequired);
  }

  void _showOptionForm(BuildContext context, WidgetRef ref, String groupId) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Pilihan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama (contoh: Large)'), autofocus: true),
          const SizedBox(height: 12),
          TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Tambah Harga', prefixText: 'Rp '),
            keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final price = double.tryParse(priceCtrl.text.replaceAll('.', '')) ?? 0;
              ref.read(variantGroupProvider(productId).notifier).addOption(groupId, name, price);
              Navigator.pop(ctx);
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }
}

class _VariantGroupTile extends StatelessWidget {
  final VariantGroupModel group;
  final VoidCallback onEditGroup;
  final VoidCallback onDeleteGroup;
  final VoidCallback onAddOption;
  final void Function(String) onDeleteOption;

  const _VariantGroupTile({
    required this.group, required this.onEditGroup, required this.onDeleteGroup,
    required this.onAddOption, required this.onDeleteOption,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(child: Row(children: [
              Text(group.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              if (group.isRequired)
                Container(margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Wajib', style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600))),
            ])),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary), onPressed: onEditGroup),
            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error), onPressed: onDeleteGroup),
          ]),
        ),
        ...group.options.map((opt) => ListTile(
          dense: true,
          title: Text(opt.name),
          subtitle: opt.priceModifier > 0 ? Text('+${fmt.format(opt.priceModifier)}',
            style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)) : null,
          trailing: IconButton(icon: const Icon(Icons.close, size: 18, color: AppColors.error),
            onPressed: () => onDeleteOption(opt.id)),
        )),
        TextButton.icon(
          onPressed: onAddOption,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Tambah Pilihan'),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ),
      ]),
    );
  }
}
