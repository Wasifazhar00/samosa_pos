import 'dart:io';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'data.dart';
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
    final accountInfo = _s['payment_account_info'] ?? '';
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
                            if (!d.isPaid && accountInfo.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Center(
                                child: QrImageView(
                                  data: accountInfo,
                                  version: QrVersions.auto,
                                  size: 100,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                              Text(accountInfo,
                                  style: const TextStyle(fontSize: 10),
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: _busy ? null : _shareImage,
                  icon: Icon(isDesktop ? Icons.save_alt : Icons.share,
                      size: 18),
                  label: Text(
                    isDesktop
                        ? tr(ur, 'Save image', 'تصویر محفوظ کریں')
                        : tr(ur, 'Share image', 'تصویر شیئر کریں'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(tr(ur, 'Done', 'مکمل')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
