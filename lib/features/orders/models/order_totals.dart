/// Perhitungan total pesanan: subtotal → diskon → pajak → total.
/// Semua dibulatkan ke rupiah penuh.
class OrderTotals {
  final double subtotal;
  final double discount;
  final double taxPercent;
  final double tax;
  final double total;

  const OrderTotals._({
    required this.subtotal,
    required this.discount,
    required this.taxPercent,
    required this.tax,
    required this.total,
  });

  /// [discountValue]: nominal rupiah, atau persen kalau [discountIsPercent].
  /// [taxPercent]: 0 kalau pajak tidak aktif. Pajak dihitung SETELAH diskon.
  factory OrderTotals.compute({
    required double subtotal,
    double discountValue = 0,
    bool discountIsPercent = false,
    double taxPercent = 0,
  }) {
    final rawDiscount = discountIsPercent
        ? subtotal * discountValue.clamp(0, 100) / 100
        : discountValue;
    final discount = rawDiscount.clamp(0, subtotal).roundToDouble();
    final base = subtotal - discount;
    final tax = (base * taxPercent.clamp(0, 100) / 100).roundToDouble();
    return OrderTotals._(
      subtotal: subtotal,
      discount: discount,
      taxPercent: taxPercent,
      tax: tax,
      total: base + tax,
    );
  }

  /// Ada baris tambahan di struk? Kalau tidak, struk tampil bersih seperti biasa.
  bool get hasAdjustments => discount > 0 || tax > 0;
}

/// Pengaturan diskon & pajak toko (dari tabel settings, ikut sinkron).
class TaxDiscountSettings {
  final bool discountEnabled;
  final bool taxEnabled;
  final String taxName;
  final double taxPercent;

  const TaxDiscountSettings({
    this.discountEnabled = false,
    this.taxEnabled = false,
    this.taxName = 'Pajak',
    this.taxPercent = 0,
  });

  static const kDiscountEnabled = 'discount_enabled';
  static const kTaxEnabled = 'tax_enabled';
  static const kTaxName = 'tax_name';
  static const kTaxPercent = 'tax_percent';

  factory TaxDiscountSettings.fromSettings(Map<String, String> s) => TaxDiscountSettings(
        discountEnabled: s[kDiscountEnabled] == '1',
        taxEnabled: s[kTaxEnabled] == '1',
        taxName: (s[kTaxName] ?? '').trim().isEmpty ? 'Pajak' : s[kTaxName]!.trim(),
        taxPercent: double.tryParse((s[kTaxPercent] ?? '').replaceAll(',', '.')) ?? 0,
      );

  /// Persen pajak efektif (0 kalau pajak dimatikan).
  double get activeTaxPercent => taxEnabled ? taxPercent : 0;
}
