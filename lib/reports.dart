import 'package:flutter/material.dart';

import 'data.dart';

class _Agg {
  int qty = 0;
  double amount = 0;
}

class _Period {
  int bills = 0;
  double total = 0;
  double paid = 0;
  double udhar = 0;
  double discount = 0;
  double cash = 0;
  double online = 0;
  final Map<int, double> used = {};
  final Map<String, _Agg> products = {};
}

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key, required this.isUrdu});

  final bool isUrdu;

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  late final Future<List<SaleRecord>> _future = _load();
  Map<int, Map<int, double>> _recipes = {};
  Map<int, InventoryItem> _inv = {};

  Future<List<SaleRecord>> _load() async {
    final db = DatabaseHelper.instance;
    _recipes = await db.getAllRecipes();
    _inv = {for (final i in await db.getInventory()) i.id!: i};
    return db.getAllSales();
  }
  String _mode = 'daily';

  bool get _ur => widget.isUrdu;

  String _key(SaleRecord s) {
    final n = _mode == 'daily' ? 10 : (_mode == 'monthly' ? 7 : 4);
    return s.createdAt.length >= n ? s.createdAt.substring(0, n) : s.createdAt;
  }

  void _add(_Period p, SaleRecord s) {
    p.bills++;
    p.total += s.totalAmount;
    p.discount += s.discount;
    if (s.isPaid) {
      p.paid += s.totalAmount;
      if (s.paymentMethod == 'Online') {
        p.online += s.totalAmount;
      } else {
        p.cash += s.totalAmount;
      }
    } else {
      p.udhar += s.totalAmount;
    }
    final lines = s.lines;
    if (lines.isNotEmpty) {
      for (final l in lines) {
        final a = p.products.putIfAbsent(l.name, _Agg.new);
        a.qty += l.qty;
        a.amount += l.total;
        final rec = _recipes[l.menuId];
        if (rec != null) {
          rec.forEach((inv, q) => p.used[inv] = (p.used[inv] ?? 0) + q * l.qty);
        }
      }
    } else {
      for (final part in s.itemsSummary.split(', ')) {
        final m = RegExp(r'^(\d+)x (.+)$').firstMatch(part);
        if (m == null) continue;
        final a = p.products.putIfAbsent(m.group(2)!, _Agg.new);
        a.qty += int.parse(m.group(1)!);
      }
    }
  }

  Widget _tile(String title, _Period p, {bool open = false}) {
    final rows = p.products.entries.toList()
      ..sort((a, b) => b.value.qty.compareTo(a.value.qty));
    Widget line(String a, String q, String m, {bool bold = false}) {
      final st = TextStyle(fontWeight: bold ? FontWeight.bold : null);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: st)),
          SizedBox(width: 50, child: Text(q, style: st, textAlign: TextAlign.end)),
          SizedBox(width: 90, child: Text(m, style: st, textAlign: TextAlign.end)),
        ]),
      );
    }

    return Card(
      child: ExpansionTile(
        initiallyExpanded: open,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${p.bills} ${tr(_ur, 'bills', 'بل')}  -  ${tr(_ur, 'Total', 'کل')} ${money(p.total)}\n'
          '${tr(_ur, 'Cash', 'نقد')} ${money(p.cash)}  -  ${tr(_ur, 'Online', 'آن لائن')} ${money(p.online)}  -  ${tr(_ur, 'Udhar', 'ادھار')} ${money(p.udhar)}',
        ),
        children: [
          line(tr(_ur, 'Product', 'پروڈکٹ'), tr(_ur, 'Qty', 'تعداد'),
              tr(_ur, 'Amount', 'رقم'), bold: true),
          const Divider(height: 8),
          for (final e in rows)
            line(e.key, '${e.value.qty}',
                e.value.amount > 0 ? money(e.value.amount) : '-'),
          if (p.discount > 0) ...[
            const Divider(height: 8),
            line(tr(_ur, 'Discounts given', 'دی گئی رعایت'), '',
                '- ${money(p.discount)}'),
          ],
          if (p.used.isNotEmpty) ...[
            const Divider(height: 8),
            line(tr(_ur, 'Stock used', 'استعمال شدہ اسٹاک'), tr(_ur, 'Used', 'استعمال'),
                tr(_ur, 'Left now', 'باقی'), bold: true),
            for (final e in p.used.entries)
              if (_inv[e.key] != null)
                line(_inv[e.key]!.name, qtyText(e.value),
                    '${qtyText(_inv[e.key]!.stockQty)} ${_inv[e.key]!.unit}'),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(_ur, 'Sales reports', 'سیلز رپورٹس')),
      ),
      body: FutureBuilder<List<SaleRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final periods = <String, _Period>{};
          final all = _Period();
          for (final s in snap.data!) {
            _add(periods.putIfAbsent(_key(s), _Period.new), s);
            _add(all, s);
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: 'daily',
                          label: Text(tr(_ur, 'Daily', 'روزانہ'))),
                      ButtonSegment(
                          value: 'monthly',
                          label: Text(tr(_ur, 'Monthly', 'ماہانہ'))),
                      ButtonSegment(
                          value: 'yearly',
                          label: Text(tr(_ur, 'Yearly', 'سالانہ'))),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) => setState(() => _mode = v.first),
                  ),
                  const SizedBox(height: 8),
                  _tile(tr(_ur, 'All combined', 'تمام ملا کر'), all, open: true),
                  for (final e in periods.entries) _tile(e.key, e.value),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
