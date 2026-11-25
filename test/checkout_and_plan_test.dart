import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posin/core/utils/rupiah_input_formatter.dart';
import 'package:posin/features/orders/models/order_totals.dart';
import 'package:posin/features/orders/screens/checkout_sheet.dart';
import 'package:posin/features/plan/models/plan_model.dart';
import 'package:posin/features/printer/models/receipt_data.dart';
import 'package:posin/features/printer/services/printer_service.dart';

void main() {
  group('OrderTotals (diskon & pajak)', () {
    test('tanpa diskon & pajak: total = subtotal, struk bersih', () {
      final t = OrderTotals.compute(subtotal: 23500);
      expect(t.total, 23500);
      expect(t.hasAdjustments, isFalse);
    });

    test('diskon nominal lalu pajak dihitung setelah diskon', () {
      final t = OrderTotals.compute(subtotal: 30000, discountValue: 3000, taxPercent: 10);
      expect(t.discount, 3000);
      expect(t.tax, 2700);
      expect(t.total, 29700);
    });

    test('diskon persen & pembulatan ke rupiah', () {
      final t = OrderTotals.compute(subtotal: 23500, discountValue: 15, discountIsPercent: true, taxPercent: 11);
      expect(t.discount, 3525);
      expect(t.tax, 2197); // 19975 x 11% = 2197,25 -> dibulatkan ke rupiah terdekat
      expect(t.total, 22172);
    });

    test('diskon tidak bisa melebihi subtotal / negatif', () {
      expect(OrderTotals.compute(subtotal: 10000, discountValue: 50000).total, 0);
      expect(OrderTotals.compute(subtotal: 10000, discountValue: 150, discountIsPercent: true).total, 0);
      expect(OrderTotals.compute(subtotal: 10000, discountValue: -5000).total, 10000);
    });

    test('setting pajak nonaktif = 0% walau persen tersimpan', () {
      final s = TaxDiscountSettings.fromSettings({'tax_enabled': '0', 'tax_percent': '10'});
      expect(s.activeTaxPercent, 0);
      final on = TaxDiscountSettings.fromSettings({'tax_enabled': '1', 'tax_percent': '10', 'tax_name': 'PB1'});
      expect(on.activeTaxPercent, 10);
      expect(on.taxName, 'PB1');
    });
  });

  group('Uang tunai', () {
    test('tombol cepat: pecahan di atas total, tanpa duplikat', () {
      expect(quickCashAmounts(23500), [25000, 30000, 40000, 50000]);
      expect(quickCashAmounts(50000), [60000, 100000]); // 50.000 pas = tombol "Uang Pas"
    });

    test('format ribuan saat mengetik', () {
      const f = RupiahInputFormatter();
      TextEditingValue type(String text) => f.formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
          );
      expect(type('50000').text, '50.000');
      expect(type('1234567').text, '1.234.567');
      expect(type('007').text, '7');
      expect(type('abc').text, '');
      expect(RupiahInputFormatter.parse('1.234.567'), 1234567);
    });
  });

  group('Status langganan', () {
    final serverNow = DateTime.utc(2026, 11, 25, 8);
    PlanModel plan(PlanType t, DateTime exp) => PlanModel(userId: 'u', planType: t, trialExpiresAt: exp);

    test('premium yang sudah lewat masa aktif = terkunci', () {
      final s = evaluatePlan(
        plan: plan(PlanType.premium, DateTime.utc(2026, 11, 1)),
        serverNow: serverNow, deviceNowAtFetch: serverNow, deviceNow: serverNow, fromCache: false,
      );
      expect(s.isActive, isFalse);
      expect(s.lockReason, PlanLockReason.expired);
    });

    test('memundurkan jam HP tidak membuka kunci', () {
      final s = evaluatePlan(
        plan: plan(PlanType.free, DateTime.utc(2026, 11, 24)),
        serverNow: serverNow,
        deviceNowAtFetch: serverNow,
        deviceNow: DateTime.utc(2026, 1, 1), // jam HP dimundurkan
        fromCache: true,
      );
      expect(s.isActive, isFalse);
    });

    test('jam HP salah (selisih dengan server) dikoreksi', () {
      // HP 2 hari lebih lambat dari server; masa aktif habis besok (waktu server).
      final s = evaluatePlan(
        plan: plan(PlanType.free, serverNow.add(const Duration(days: 1))),
        serverNow: serverNow,
        deviceNowAtFetch: serverNow.subtract(const Duration(days: 2)),
        deviceNow: serverNow.subtract(const Duration(days: 2)).add(const Duration(days: 3)),
        fromCache: true,
      );
      expect(s.isActive, isFalse, reason: 'jam efektif = jam server + 3 hari');
    });

    test('offline terlalu lama (> 14 hari) perlu verifikasi', () {
      final s = evaluatePlan(
        plan: plan(PlanType.premium, DateTime.utc(2030)),
        serverNow: serverNow,
        deviceNowAtFetch: serverNow,
        deviceNow: serverNow.add(const Duration(days: 15)),
        fromCache: true,
      );
      expect(s.lockReason, PlanLockReason.needsVerification);
    });

    test('pengingat muncul 3 hari sebelum habis', () {
      final s = evaluatePlan(
        plan: plan(PlanType.premium, serverNow.add(const Duration(days: 2, hours: 5))),
        serverNow: serverNow, deviceNowAtFetch: serverNow, deviceNow: serverNow, fromCache: false,
      );
      expect(s.isActive, isTrue);
      expect(s.daysLeft, 3);
      expect(s.expiresSoon, isTrue);
    });
  });

  group('Struk', () {
    ReceiptData receipt({double discount = 0, double tax = 0}) => ReceiptData(
          storeName: 'Toko A',
          orderNumber: '20261125-120000',
          dailyNumber: 'A-001',
          dateTime: '25/11/2026 12:00',
          items: const [ReceiptLine(name: 'Kopi', qty: 2, price: 15000, subtotal: 30000, note: 'less sugar')],
          subtotal: 30000,
          discount: discount,
          taxName: 'PB1',
          taxPercent: 10,
          tax: tax,
          total: 30000 - discount + tax,
          paymentMethod: 'Tunai',
          amountPaid: 50000,
          change: 50000 - (30000 - discount + tax),
          footer: 'Terima kasih!',
        );

    test('tanpa diskon/pajak: tidak ada baris Subtotal/Diskon/Pajak', () {
      final text = PrinterService.instance.generateReceiptText(receipt());
      expect(text, isNot(contains('Subtotal')));
      expect(text, isNot(contains('Diskon')));
      expect(text, isNot(contains('PB1')));
      expect(text, contains('#A-001'));
      expect(text, contains('* less sugar'));
    });

    test('dengan diskon & pajak: baris muncul lengkap', () {
      final text = PrinterService.instance.generateReceiptText(receipt(discount: 3000, tax: 2700));
      expect(text, contains('Subtotal'));
      expect(text, contains('Diskon'));
      expect(text, contains('-Rp3.000'));
      expect(text, contains('PB1 10%'));
      expect(text, contains('Rp29.700'));
    });

    test('setiap baris muat di kertas 58mm (32 kolom)', () {
      final text = PrinterService.instance.generateReceiptText(receipt(discount: 3000, tax: 2700));
      for (final line in text.split('\n')) {
        expect(line.length, lessThanOrEqualTo(32), reason: '"$line"');
      }
    });
  });
}
