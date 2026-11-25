import 'package:flutter/services.dart';

/// Input angka dengan pemisah ribuan otomatis: "50000" → "50.000".
/// Kursor tetap di posisi yang wajar saat mengetik/menghapus.
class RupiahInputFormatter extends TextInputFormatter {
  final int maxDigits;
  const RupiahInputFormatter({this.maxDigits = 12});

  static String format(num value) => value
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');

  /// "50.000" → 50000
  static double parse(String text) =>
      double.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.isEmpty) return const TextEditingValue();

    final formatted = format(int.parse(digits));

    // Pertahankan jumlah digit di kanan kursor.
    final digitsRightOfCursor = newValue.text
        .substring(newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    var offset = formatted.length;
    var seen = 0;
    while (offset > 0 && seen < digitsRightOfCursor) {
      offset--;
      if (formatted[offset] != '.') seen++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
