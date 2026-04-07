import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../auth/providers/supabase_auth_provider.dart';
import '../../categories/screens/categories_screen.dart';
import '../../plan/models/plan_model.dart';
import '../../plan/providers/plan_provider.dart';
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
          _SectionHeader(title: 'Langganan'),
          const _PlanCard(),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Akun'),
          _AccountInfoTile(),
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

// ── Plan / Subscription card ─────────────────────────────────────────────────

class _PlanCard extends ConsumerWidget {
  const _PlanCard();

  static const _waNumber = '6281329064923';
  static const _waMessage =
      'Halo, saya mau berlangganan POSin Premium. Mohon informasi lebih lanjut. 🙏';

  Future<void> _openWhatsApp(BuildContext context) async {
    final encoded = Uri.encodeComponent(_waMessage);
    final uri = Uri.parse('https://wa.me/$_waNumber?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(supabaseAuthProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final planAsync = ref.watch(planProvider(user.id));
    return planAsync.when(
      loading: () => _shell(child: const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      )),
      error: (_, _) => _shell(child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Gagal memuat info langganan'),
      )),
      data: (plan) => _buildCard(context, ref, plan),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, PlanModel plan) {
    final df = DateFormat('d MMMM yyyy', 'id_ID');
    final isPremium = plan.isPremium;
    final isActive = plan.isActive;

    final accent = isPremium
        ? const Color(0xFFF59E0B)
        : (isActive ? AppColors.primary : AppColors.error);

    final badgeText = isPremium
        ? 'PREMIUM'
        : (isActive ? 'FREE TRIAL' : 'EXPIRED');

    final statusText = isPremium
        ? 'Berlaku hingga ${df.format(plan.trialExpiresAt)}'
        : (isActive
            ? 'Sisa ${plan.daysLeft} hari • berakhir ${df.format(plan.trialExpiresAt)}'
            : 'Masa trial sudah berakhir');

    return _shell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPremium ? Icons.workspace_premium_rounded : Icons.schedule_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isPremium) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openWhatsApp(context),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text(
                    'Upgrade ke Premium via WhatsApp',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Account info tile (email) ────────────────────────────────────────────────

class _AccountInfoTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(supabaseAuthProvider).valueOrNull;
    final email = user?.email ?? '-';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.person_outline, color: AppColors.primary, size: 20),
        ),
        title: const Text('Email Akun',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text(email,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
