import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../orders/models/order_model.dart';

class ReportPdfService {
  static Future<pw.Document> build({
    required List<OrderModel> orders,
    required DateTime start,
    required DateTime end,
    required String storeName,
    String? storeAddress,
    String? storePhone,
  }) async {
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM yyyy', 'id_ID');
    final timeFmt = DateFormat('dd/MM/yy HH:mm');

    final total = orders.fold<double>(0, (s, o) => s + o.total);
    final cashTotal = orders.where((o) => o.paymentMethod == 'Tunai').fold<double>(0, (s, o) => s + o.total);
    final qrisTotal = orders.where((o) => o.paymentMethod == 'QRIS').fold<double>(0, (s, o) => s + o.total);
    final cashCount = orders.where((o) => o.paymentMethod == 'Tunai').length;
    final qrisCount = orders.where((o) => o.paymentMethod == 'QRIS').length;
    final avg = orders.isEmpty ? 0.0 : total / orders.length;

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();

    pw.Widget header() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(storeName, style: pw.TextStyle(font: fontBold, fontSize: 20)),
                if ((storeAddress ?? '').isNotEmpty)
                  pw.Text(storeAddress!, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                if ((storePhone ?? '').isNotEmpty)
                  pw.Text(storePhone!, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('LAPORAN PENJUALAN', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                pw.SizedBox(height: 2),
                pw.Text('${dateFmt.format(start)}  -  ${dateFmt.format(end)}',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                pw.Text('Dicetak: ${DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(DateTime.now())}',
                  style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
      ],
    );

    pw.Widget summaryBox(String label, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(color.toInt()).shade(0.05),
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: color, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 13, color: color)),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          header(),
          pw.SizedBox(height: 14),

          // Summary cards
          pw.Row(children: [
            pw.Expanded(child: summaryBox('Total Transaksi', '${orders.length} order', PdfColors.blue700)),
            pw.SizedBox(width: 8),
            pw.Expanded(child: summaryBox('Total Pendapatan', fmt.format(total), PdfColors.green700)),
            pw.SizedBox(width: 8),
            pw.Expanded(child: summaryBox('Rata-rata / Order', fmt.format(avg), PdfColors.orange700)),
          ]),
          pw.SizedBox(height: 14),

          // Payment method breakdown
          pw.Text('Metode Pembayaran', style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('Metode', fontBold, header: true),
                  _cell('Transaksi', fontBold, header: true),
                  _cell('Total', fontBold, header: true, align: pw.Alignment.centerRight),
                ],
              ),
              pw.TableRow(children: [
                _cell('Tunai', font),
                _cell('$cashCount', font),
                _cell(fmt.format(cashTotal), font, align: pw.Alignment.centerRight),
              ]),
              pw.TableRow(children: [
                _cell('QRIS', font),
                _cell('$qrisCount', font),
                _cell(fmt.format(qrisTotal), font, align: pw.Alignment.centerRight),
              ]),
            ],
          ),
          pw.SizedBox(height: 14),

          // Transaction list
          pw.Text('Daftar Transaksi (${orders.length})',
            style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 6),
          if (orders.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 20),
              child: pw.Center(
                child: pw.Text('Tidak ada transaksi pada rentang ini',
                  style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey600)),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(1),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(1.6),
                4: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('No', fontBold, header: true),
                    _cell('Order #', fontBold, header: true),
                    _cell('Tanggal', fontBold, header: true),
                    _cell('Bayar', fontBold, header: true),
                    _cell('Total', fontBold, header: true, align: pw.Alignment.centerRight),
                  ],
                ),
                for (var i = 0; i < orders.length; i++)
                  pw.TableRow(children: [
                    _cell('${i + 1}', font),
                    _cell(orders[i].orderNumber, font),
                    _cell(timeFmt.format(DateTime.parse(orders[i].createdAt)), font),
                    _cell(orders[i].paymentMethod, font),
                    _cell(fmt.format(orders[i].total), font, align: pw.Alignment.centerRight),
                  ]),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _cell('', fontBold),
                    _cell('', fontBold),
                    _cell('', fontBold),
                    _cell('TOTAL', fontBold, header: true, align: pw.Alignment.centerRight),
                    _cell(fmt.format(total), fontBold, header: true, align: pw.Alignment.centerRight),
                  ],
                ),
              ],
            ),
        ],
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}  •  POSin',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    return pdf;
  }

  static pw.Widget _cell(
    String text,
    pw.Font font, {
    bool header = false,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: header ? 9.5 : 9,
          color: header ? PdfColors.grey900 : PdfColors.grey800,
        ),
      ),
    );
  }
}
