import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../categories/screens/categories_screen.dart';
import '../../printer/screens/printer_settings_screen.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Informasi Toko'),
          _LogoTile(logoUrl: settings['logo_url'] ?? ''),
          _SettingTile(icon: Icons.store_outlined, title: 'Nama Toko',
            subtitle: settings['store_name'] ?? 'Toko Saya',
            onTap: () => _editSetting(context, ref, 'store_name', 'Nama Toko', settings['store_name'] ?? '')),
          _SettingTile(icon: Icons.location_on_outlined, title: 'Alamat',
            subtitle: settings['store_address']?.isNotEmpty == true ? settings['store_address']! : 'Belum diisi',
            onTap: () => _editSetting(context, ref, 'store_address', 'Alamat Toko', settings['store_address'] ?? '')),
          _SettingTile(icon: Icons.phone_outlined, title: 'Nomor Telepon',
            subtitle: settings['store_phone']?.isNotEmpty == true ? settings['store_phone']! : 'Belum diisi',
            onTap: () => _editSetting(context, ref, 'store_phone', 'Nomor Telepon', settings['store_phone'] ?? '')),
          _SettingTile(icon: Icons.description_outlined, title: 'Deskripsi Toko',
            subtitle: settings['store_description']?.isNotEmpty == true ? settings['store_description']! : 'Belum diisi',
            onTap: () => _editSetting(context, ref, 'store_description', 'Deskripsi Toko', settings['store_description'] ?? '')),
          _SettingTile(icon: Icons.receipt_outlined, title: 'Pesan Footer Struk',
            subtitle: settings['receipt_footer'] ?? 'Terima kasih!',
            onTap: () => _editSetting(context, ref, 'receipt_footer', 'Pesan Footer', settings['receipt_footer'] ?? '')),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Manajemen'),
          _SettingTile(icon: Icons.category_outlined, title: 'Kategori Menu', subtitle: 'Kelola kategori produk',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())), showArrow: true),
          _SettingTile(icon: Icons.print_outlined, title: 'Printer Bluetooth',
            subtitle: settings['printer_name']?.isNotEmpty == true ? settings['printer_name']! : 'Belum dipilih',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())), showArrow: true),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Keamanan'),
          _PinToggleTile(settings: settings),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Akun'),
          _SettingTile(icon: Icons.lock_outline, title: 'Kunci Layar', subtitle: 'Kunci aplikasi dengan PIN',
            color: AppColors.warning, onTap: () => _confirmLogout(context, ref)),
          _SettingTile(icon: Icons.logout, title: 'Keluar Akun', subtitle: 'Sign out dari akun',
            color: AppColors.error, onTap: () => _confirmSignOut(context, ref)),
        ],
      ),
    );
  }

  void _editSetting(BuildContext context, WidgetRef ref, String key, String label, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).setSetting(key, controller.text.trim());
              Navigator.of(ctx).pop();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kunci Layar?'),
        content: const Text('Aplikasi akan dikunci. Kamu perlu PIN untuk masuk kembali.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
            },
            child: const Text('Kunci', style: TextStyle(color: AppColors.warning)),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Keluar Akun?'),
        content: const Text('Kamu akan keluar dari akun. Data lokal tetap tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
              await Supabase.instance.client.auth.signOut();
            },
            child: const Text('Keluar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ── Logo Tile ─────────────────────────────────────────────────────────────────

class _LogoTile extends ConsumerStatefulWidget {
  final String logoUrl;
  const _LogoTile({required this.logoUrl});

  @override
  ConsumerState<_LogoTile> createState() => _LogoTileState();
}

class _LogoTileState extends ConsumerState<_LogoTile> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _uploading = true);
    final url = await SupabaseService.instance.uploadStoreLogo(File(picked.path));
    if (url != null) {
      await ref.read(settingsProvider.notifier).setSetting('logo_url', url);
    }
    setState(() => _uploading = false);
    if (mounted && url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal upload logo'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _removeLogo() async {
    await ref.read(settingsProvider.notifier).setSetting('logo_url', '');
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = widget.logoUrl.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.background, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : (hasLogo
                    ? Image.network(widget.logoUrl, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.image_outlined, color: AppColors.border))
                    : const Icon(Icons.store, color: AppColors.border, size: 32)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Logo Toko', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(hasLogo ? 'Logo terpasang' : 'Belum ada logo',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const Text('Ditampilkan di struk', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ])),
        Column(children: [
          TextButton(onPressed: _uploading ? null : _pickAndUpload,
            child: Text(hasLogo ? 'Ganti' : 'Upload')),
          if (hasLogo)
            TextButton(onPressed: _removeLogo,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Hapus')),
        ]),
      ]),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showArrow;
  final Color? color;

  const _SettingTile({
    required this.icon, required this.title, required this.subtitle,
    required this.onTap, this.showArrow = false, this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: ListTile(
        onTap: onTap,
        leading: Container(width: 40, height: 40,
          decoration: BoxDecoration(color: (color ?? AppColors.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color ?? AppColors.primary, size: 20)),
        title: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color ?? AppColors.textPrimary)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        trailing: showArrow ? const Icon(Icons.chevron_right, color: AppColors.textSecondary) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

class _PinToggleTile extends ConsumerWidget {
  final Map<String, String> settings;
  const _PinToggleTile({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinEnabled = settings['pin_enabled'] == '1';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        ListTile(
          leading: Container(width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.lock_outline, color: AppColors.primary, size: 20)),
          title: const Text('PIN Login', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          subtitle: Text(pinEnabled ? 'Aktif' : 'Nonaktif', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          trailing: Switch(
            value: pinEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).setSetting('pin_enabled', val ? '1' : '0');
              if (val) _setPinDialog(context, ref);
            },
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        if (pinEnabled)
          ListTile(
            onTap: () => _setPinDialog(context, ref),
            leading: const SizedBox(width: 40),
            title: const Text('Ubah PIN', style: TextStyle(fontSize: 14, color: AppColors.primary)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
      ]),
    );
  }

  void _setPinDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set PIN'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'PIN (4-6 digit)'),
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              if (controller.text.length >= 4) {
                ref.read(settingsProvider.notifier).setSetting('pin', controller.text);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }
}
