import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'data.dart';
import 'thermal.dart';
import 'ui_helpers.dart';

class ReceiptData {
  const ReceiptData({
    required this.billNo,
    required this.tokenNo,
    required this.orderType,
    required this.paymentMethod,
    required this.lines,
    required this.summary,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.isPaid,
    required this.mobile,
    required this.createdAt,
  });

  final String billNo;
  final String tokenNo;
  final String orderType;
  final String paymentMethod;
  final List<SaleLine> lines;
  final String summary;
  final double subtotal;
  final double discount;
  final double total;
  final bool isPaid;
  final String mobile;
  final DateTime createdAt;

  factory ReceiptData.fromSale(SaleRecord s) => ReceiptData(
        billNo: s.billNo,
        tokenNo: s.tokenNo,
        orderType: s.orderType,
        paymentMethod: s.paymentMethod,
        lines: s.lines,
        summary: s.itemsSummary,
        subtotal: s.totalAmount + s.discount,
        discount: s.discount,
        total: s.totalAmount,
        isPaid: s.isPaid,
        mobile: s.customerMobile ?? '',
        createdAt: s.createdTime ?? DateTime.now(),
      );
}

class QrItem {
  const QrItem(this.label, this.data, this.imagePath);
  final String label;
  final String data;
  final String imagePath;
}

List<QrItem> qrEntries(Map<String, String> s) {
  if (s['print_qr'] == '0') return const [];
  final out = <QrItem>[];
  void add(String label, String data, String img) {
    final hasImg = img.isNotEmpty && File(img).existsSync();
    if (hasImg || data.trim().isNotEmpty) {
      out.add(QrItem(label, data.trim(), hasImg ? img : ''));
    }
  }

  add(s['qr1_label'] ?? '', s['payment_account_info'] ?? '', s['qr1_image'] ?? '');
  add(s['qr2_label'] ?? '', s['qr2_data'] ?? '', s['qr2_image'] ?? '');
  return out;
}

PdfPageFormat _rollFormat(ReceiptData d, Map<String, String> s) {
  final wMm = (double.tryParse(s['paper_width'] ?? '') ?? 80)
      .clamp(30.0, 300.0)
      .toDouble();
  final hSet = double.tryParse(s['paper_height'] ?? '') ?? 0;
  final margin = (wMm <= 60 ? 5.0 : 4.0) * PdfPageFormat.mm;
  final n = d.lines.isEmpty ? 2 : d.lines.length;
  final auto = 110 +
      n * 7 +
      (d.discount > 0 ? 12 : 0) +
      (d.mobile.isNotEmpty ? 6 : 0) +
      qrEntries(s).length * 42;
  final hMm = hSet >= 50 ? hSet : auto.toDouble();
  return PdfPageFormat(wMm * PdfPageFormat.mm, hMm * PdfPageFormat.mm,
      marginAll: margin);
}

/// Builds a receipt PDF with a fixed page height, so thermal printers feed
/// exactly one receipt and stop.
Future<Uint8List> buildReceiptPdf(ReceiptData d, Map<String, String> s) async {
  final doc = pw.Document();
  final qrs = qrEntries(s);
  final qrImgs = <pw.MemoryImage?>[
    for (final q in qrs)
      q.imagePath.isEmpty
          ? null
          : pw.MemoryImage(await File(q.imagePath).readAsBytes()),
  ];
  pw.Widget row(String a, String b, {bool bold = false}) {
    final st = pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Expanded(child: pw.Text(a, style: st)), pw.Text(b, style: st)],
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: _rollFormat(d, s),
      build: (_) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(s['shop_name'] ?? '',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text(s['shop_address'] ?? '',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Ph: ${s['shop_phone'] ?? ''}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(),
          row('Token ${d.tokenNo}', d.billNo, bold: true),
          row(fmtDateTime(d.createdAt), d.orderType),
          if (d.mobile.isNotEmpty) row('Customer', d.mobile),
          pw.Divider(),
          if (d.lines.isNotEmpty)
            ...d.lines.map((l) => row('${l.name} x${l.qty}', money(l.total)))
          else
            pw.Text(d.summary, style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
          if (d.discount > 0) ...[
            row('Subtotal', money(d.subtotal)),
            row('Discount', '- ${money(d.discount)}'),
          ],
          row('TOTAL', money(d.total), bold: true),
          pw.SizedBox(height: 4),
          pw.Text(
            d.isPaid ? 'PAID (${d.paymentMethod})' : 'UNPAID / UDHAR',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          for (var i = 0; i < qrs.length; i++) ...[
            pw.SizedBox(height: 6),
            if (qrs[i].label.isNotEmpty)
              pw.Text(qrs[i].label,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Center(
              child: qrImgs[i] != null
                  ? pw.Image(qrImgs[i]!,
                      width: 90, height: 90, fit: pw.BoxFit.contain)
                  : pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrs[i].data,
                      width: 80,
                      height: 80,
                    ),
            ),
            if (qrImgs[i] == null)
              pw.Text(qrs[i].data,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 7)),
          ],
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: d.billNo,
              width: 130,
              height: 30,
              drawText: true,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Thank you! Visit again.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Sends the receipt to the system print dialog (thermal printer friendly).
Future<void> printReceipt(ReceiptData d) async {
  final s = await DatabaseHelper.instance.getSettings();
  if ((s['printer_mode'] ?? 'system') != 'system') {
    await ThermalPrinter.printReceipt(d, s);
    return;
  }
  final bytes = await buildReceiptPdf(d, s);
  await Printing.layoutPdf(
    name: d.billNo,
    format: _rollFormat(d, s),
    dynamicLayout: false,
    onLayout: (_) async => bytes,
  );
}

Future<void> showReceiptSheet(
  BuildContext context, {
  required ReceiptData data,
  required bool isUrdu,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReceiptPreviewModal(data: data, isUrdu: isUrdu),
  );
}

class ReceiptPreviewModal extends StatefulWidget {
  const ReceiptPreviewModal({
    super.key,
    required this.data,
    required this.isUrdu,
  });

  final ReceiptData data;
  final bool isUrdu;

  @override
  State<ReceiptPreviewModal> createState() => _ReceiptPreviewModalState();
}

class _ReceiptPreviewModalState extends State<ReceiptPreviewModal> {
  final GlobalKey _receiptKey = GlobalKey();
  Map<String, String> _s = kDefaultSettings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await DatabaseHelper.instance.getSettings();
    if (!mounted) return;
    setState(() => _s = s);
  }

  Future<void> _printNow() async {
    try {
      await printReceipt(widget.data);
    } catch (e) {
      if (mounted) toast(context, 'Could not print: $e', error: true);
    }
  }

  Future<void> _savePdf() async {
    try {
      final bytes = await buildReceiptPdf(widget.data, _s);
      final name = 'receipt_${widget.data.billNo}.pdf';
      if (isDesktop) {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory(p.join(docs.path, 'SamosaPOS', 'Receipts'));
        await dir.create(recursive: true);
        final file = File(p.join(dir.path, name));
        await file.writeAsBytes(bytes);
        if (!mounted) return;
        toast(context, 'PDF saved: ${file.path}');
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not save PDF: $e', error: true);
    }
  }

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Receipt is not ready yet');
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Could not render the receipt');
      final png = bytes.buffer.asUint8List();
      final fileName = 'receipt_${widget.data.billNo}.png';

      if (isDesktop) {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory(p.join(docs.path, 'SamosaPOS', 'Receipts'));
        await dir.create(recursive: true);
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(png);
        if (!mounted) return;
        toast(context, 'Receipt saved: ${file.path}');
      } else {
        final tmp = await getTemporaryDirectory();
        final file = File(p.join(tmp.path, fileName));
        await file.writeAsBytes(png);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          text: 'Receipt from ${_s['shop_name']}',
        );
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not share receipt: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    final d = widget.data;
    final qrs = qrEntries(_s);
    const black = TextStyle(color: Colors.black);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            tr(ur, 'Receipt preview', 'رسید کا پیش منظر'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: RepaintBoundary(
                    key: _receiptKey,
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(12),
                      color: Colors.white,
                      child: DefaultTextStyle(
                        style: black.copyWith(fontSize: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _s['shop_name'] ?? '',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            Text(_s['shop_address'] ?? '',
                                textAlign: TextAlign.center),
                            Text('Ph: ${_s['shop_phone'] ?? ''}',
                                textAlign: TextAlign.center),
                            const Divider(thickness: 2, color: Colors.black54),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Token: ${d.tokenNo}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                Text(d.billNo),
                              ],
                            ),
                            Text(fmtDateTime(d.createdAt)),
                            Text('Type: ${d.orderType}'),
                            if (d.mobile.isNotEmpty)
                              Text('Customer: ${d.mobile}'),
                            const Divider(color: Colors.black54),
                            if (d.lines.isNotEmpty)
                              ...d.lines.map(
                                (l) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: Text('${l.name} x${l.qty}')),
                                      Text(money(l.total)),
                                    ],
                                  ),
                                ),
                              )
                            else
                              Text(d.summary),
                            const Divider(thickness: 2, color: Colors.black54),
                            if (d.discount > 0) ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Subtotal'),
                                  Text(money(d.subtotal)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Discount'),
                                  Text('- ${money(d.discount)}'),
                                ],
                              ),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                Text(money(d.total),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 3),
                                color: d.isPaid
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                child: Text(
                                  d.isPaid
                                      ? 'PAID (${d.paymentMethod})'
                                      : 'UNPAID / UDHAR',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            for (final q in qrs) ...[
                              const SizedBox(height: 8),
                              if (q.label.isNotEmpty)
                                Text(q.label,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center),
                              Center(
                                child: q.imagePath.isNotEmpty
                                    ? Image.file(File(q.imagePath),
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.contain)
                                    : QrImageView(
                                        data: q.data,
                                        version: QrVersions.auto,
                                        size: 90,
                                        backgroundColor: Colors.white,
                                      ),
                              ),
                              if (q.imagePath.isEmpty)
                                Text(q.data,
                                    style: const TextStyle(fontSize: 9),
                                    textAlign: TextAlign.center),
                            ],
                            const SizedBox(height: 8),
                            Center(
                              child: BarcodeWidget(
                                barcode: Barcode.code128(),
                                data: d.billNo,
                                height: 44,
                                width: 200,
                                color: Colors.black,
                                backgroundColor: Colors.white,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Thank you! Visit again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700),
                onPressed: _printNow,
                icon: const Icon(Icons.print, size: 18),
                label: Text(tr(ur, 'Print', 'پرنٹ')),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: _savePdf,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(tr(ur, 'Save PDF', 'پی ڈی ایف')),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: _busy ? null : _shareImage,
                icon: Icon(isDesktop ? Icons.save_alt : Icons.share, size: 18),
                label: Text(tr(ur, 'Image', 'تصویر')),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check, size: 18),
                label: Text(tr(ur, 'Done', 'مکمل')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
