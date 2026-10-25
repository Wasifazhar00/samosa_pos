import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'data.dart';
import 'receipt.dart';

List<int> _ascii(String t) =>
    t.runes.map((r) => (r >= 32 && r < 127) ? r : 0x3F).toList();

class _Esc {
  final List<int> b = [];
  void raw(List<int> x) => b.addAll(x);
  void init() => raw([0x1B, 0x40]);
  void align(int n) => raw([0x1B, 0x61, n]);
  void bold(bool on) => raw([0x1B, 0x45, on ? 1 : 0]);
  void size(int n) => raw([0x1D, 0x21, n]);
  void text(String t) {
    b.addAll(_ascii(t));
    b.add(0x0A);
  }

  void feed(int n) => raw([0x1B, 0x64, n]);
  void cut() => raw([0x1D, 0x56, 0x42, 0x00]);

  void qr(String data, int module) {
    final bytes = _ascii(data);
    final len = bytes.length + 3;
    raw([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
    raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, module]);
    raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);
    raw([0x1D, 0x28, 0x6B, len & 0xFF, len >> 8, 0x31, 0x50, 0x30, ...bytes]);
    raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
  }

  void image(Uint8List data, int targetW) {
    final im = img.decodeImage(data);
    if (im == null) return;
    final r = img.copyResize(im, width: targetW);
    final w = r.width;
    final h = r.height;
    final bpr = (w + 7) ~/ 8;
    final out = <int>[0x1D, 0x76, 0x30, 0x00, bpr & 0xFF, bpr >> 8, h & 0xFF, h >> 8];
    for (var y = 0; y < h; y++) {
      for (var xb = 0; xb < bpr; xb++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = xb * 8 + bit;
          if (x >= w) continue;
          final p = r.getPixel(x, y);
          final a = p.aNormalized;
          final l = p.luminanceNormalized * a + (1 - a);
          if (l < 0.5) byte |= 0x80 >> bit;
        }
        out.add(byte);
      }
    }
    raw(out);
  }
}

class ThermalPrinter {
  static int _cols(Map<String, String> s) {
    final c = int.tryParse(s['thermal_cols'] ?? '');
    if (c != null && c >= 20 && c <= 80) return c;
    final w = double.tryParse(s['paper_width'] ?? '') ?? 80;
    return w >= 70 ? 48 : 32;
  }

  static String _lr(String l, String r, int cols) {
    var left = l;
    final room = cols - r.length - 1;
    if (left.length > room) left = left.substring(0, room < 1 ? 1 : room);
    return left + ' ' * (cols - left.length - r.length).clamp(1, cols).toInt() + r;
  }

  static Future<List<int>> _build(ReceiptData d, Map<String, String> s) async {
    final cols = _cols(s);
    final wide = cols >= 40;
    final line = '-' * cols;
    final e = _Esc()
      ..init()
      ..align(1)
      ..bold(true)
      ..text(s['shop_name'] ?? '')
      ..bold(false)
      ..text(s['shop_address'] ?? '')
      ..text('Ph: ${s['shop_phone'] ?? ''}')
      ..text(line)
      ..size(0x11)
      ..bold(true)
      ..text('Token ${d.tokenNo}')
      ..bold(false)
      ..size(0)
      ..align(0)
      ..text(_lr(d.billNo, fmtTime(d.createdAt), cols))
      ..text(fmtDateTime(d.createdAt))
      ..text('Type: ${d.orderType}');
    if (d.mobile.isNotEmpty) e.text('Customer: ${d.mobile}');
    e.text(line);
    if (d.lines.isNotEmpty) {
      for (final l in d.lines) {
        e.text(_lr('${l.name} x${l.qty}', money(l.total), cols));
      }
    } else {
      e.text(d.summary);
    }
    e.text(line);
    if (d.discount > 0) {
      e.text(_lr('Subtotal', money(d.subtotal), cols));
      e.text(_lr('Discount', '- ${money(d.discount)}', cols));
    }
    e
      ..bold(true)
      ..size(0x01)
      ..text(_lr('TOTAL', money(d.total), wide ? cols : cols))
      ..size(0)
      ..align(1)
      ..text(d.isPaid ? 'PAID (${d.paymentMethod})' : 'UNPAID / UDHAR')
      ..bold(false);
    for (final q in qrEntries(s)) {
      e.text('');
      if (q.label.isNotEmpty) e.text(q.label);
      if (q.imagePath.isNotEmpty) {
        e.image(await File(q.imagePath).readAsBytes(), wide ? 240 : 200);
      } else {
        e.qr(q.data, wide ? 6 : 5);
        e.text(q.data);
      }
    }
    e
      ..text('')
      ..text(d.billNo)
      ..text('Thank you! Visit again.')
      ..feed(4)
      ..cut();
    return e.b;
  }

  static Future<void> printReceipt(ReceiptData d, Map<String, String> s) async =>
      _send(s, await _build(d, s));

  static Future<void> test(Map<String, String> s) async {
    final cols = _cols(s);
    final e = _Esc()
      ..init()
      ..align(1)
      ..bold(true)
      ..text('PRINTER TEST')
      ..bold(false)
      ..text('Samosa POS')
      ..text('-' * cols)
      ..text('$cols characters per line')
      ..feed(4)
      ..cut();
    await _send(s, e.b);
  }

  static Future<void> _send(Map<String, String> s, List<int> bytes) async {
    final mode = s['printer_mode'] ?? 'system';
    if (mode == 'network') {
      final ip = (s['printer_ip'] ?? '').trim();
      if (ip.isEmpty) throw Exception('Enter the printer IP address in Settings');
      final sock = await Socket.connect(ip, 9100,
          timeout: const Duration(seconds: 6));
      sock.add(bytes);
      await sock.flush();
      await sock.close();
      return;
    }
    if (!Platform.isAndroid) {
      throw Exception('Bluetooth printing works on Android only');
    }
    final mac = (s['printer_bt_mac'] ?? '').trim();
    if (mac.isEmpty) throw Exception('Choose a Bluetooth printer in Settings');
    await ensureBluetoothPermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw Exception('Turn Bluetooth on');
    }
    if (!await PrintBluetoothThermal.connectionStatus) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!ok) {
        throw Exception('Could not connect. Switch the printer on and pair it first.');
      }
    }
    for (var i = 0; i < bytes.length; i += 1024) {
      final end = i + 1024 > bytes.length ? bytes.length : i + 1024;
      final ok = await PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
      if (!ok) throw Exception('The printer stopped responding');
    }
  }

  static Future<void> ensureBluetoothPermission() async {
    if (!Platform.isAndroid) return;
    await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
  }
}
