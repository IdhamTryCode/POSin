import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_colors.dart';
import 'core/screens/splash_screen.dart';
import 'core/device/device_settings.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/supabase_auth_provider.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/categories/providers/category_provider.dart';
import 'features/orders/providers/cart_provider.dart';
import 'features/orders/providers/order_provider.dart';
import 'features/products/providers/product_provider.dart';
import 'features/products/providers/variant_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/orders/screens/cashier_screen.dart';
import 'features/products/screens/products_screen.dart';
import 'features/reports/screens/report_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/plan/providers/plan_provider.dart';
import 'features/plan/screens/upgrade_screen.dart';
import 'features/update/app_update.dart';

class POSinApp extends ConsumerWidget {
  const POSinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'POSin',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const AnimatedSplashScreen(child: _AppShell()),
    );
  }
}

class _AppShell extends ConsumerWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(supabaseAuthProvider);

    // Setiap kali user berganti (login akun baru / logout): reset semua data
    // provider supaya tidak ada data bocor antar akun, lalu mulai sinkronisasi.
    ref.listen(supabaseAuthProvider, (prev, next) {
      final prevId = prev?.valueOrNull?.id;
      final nextId = next.valueOrNull?.id;
      if (prevId != nextId) {
        ref.invalidate(orderProvider);
        ref.invalidate(productProvider);
        ref.invalidate(categoryProvider);
        ref.invalidate(variantGroupProvider);
        ref.invalidate(settingsProvider);
        ref.invalidate(cartProvider);
        ref.read(deviceSettingsProvider.notifier).bindUser(nextId);
        final sync = ref.read(syncControllerProvider);
        if (nextId != null) {
          sync.start(nextId);
        } else {
          sync.stop();
        }
      }
    });

    // Versi terlalu lama → wajib update dulu (data lokal tetap aman & tetap sinkron).
    final update = ref.watch(appUpdateProvider).valueOrNull;
    if (update != null && update.isRequired) return ForceUpdateScreen(info: update);

    return authAsync.when(
      loading: () => const _SplashScreen(),
      error: (_, _) => const AuthScreen(),
      data: (user) => user == null ? const AuthScreen() : const _PlanGate(),
    );
  }
}

class _PlanGate extends ConsumerWidget {
  const _PlanGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(supabaseAuthProvider).valueOrNull;
    if (user == null) return const AuthScreen();

    final planAsync = ref.watch(planProvider(user.id));
    return planAsync.when(
      loading: () => const _SplashScreen(),
      error: (_, _) => const _MainNav(),
      data: (plan) => plan.isActive ? const _MainNav() : const UpgradeScreen(),
    );
  }
}

final _navIndexProvider = StateProvider<int>((ref) => 0);

class _MainNav extends ConsumerStatefulWidget {
  const _MainNav();

  @override
  ConsumerState<_MainNav> createState() => _MainNavState();
}

class _MainNavState extends ConsumerState<_MainNav> {
  @override
  void initState() {
    super.initState();
    // Popup "versi baru tersedia" (sekali per versi).
    ref.listenManual(appUpdateProvider, (_, next) {
      final info = next.valueOrNull;
      if (info == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowUpdateDialog(context, ref, info);
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(_navIndexProvider);
    const screens = [
      CashierScreen(),
      ProductsScreen(),
      ReportScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: _BottomNav(index: index),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  final int index;
  const _BottomNav({required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _NavItem(icon: Icons.point_of_sale_outlined, activeIcon: Icons.point_of_sale, label: 'Kasir', index: 0, current: index),
              _NavItem(icon: Icons.restaurant_menu_outlined, activeIcon: Icons.restaurant_menu, label: 'Menu', index: 1, current: index),
              _NavItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Laporan', index: 2, current: index),
              _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Pengaturan', index: 3, current: index),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends ConsumerWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int current;

  const _NavItem({
    required this.icon, required this.activeIcon,
    required this.label, required this.index, required this.current,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(_navIndexProvider.notifier).state = index,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey(isActive),
                color: isActive ? AppColors.primary : AppColors.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            )),
          ]),
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.point_of_sale, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          const Text('POSin', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 32),
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white54)),
        ]),
      ),
    );
  }
}
