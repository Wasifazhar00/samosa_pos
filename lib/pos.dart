import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'receipt.dart';
import 'ui_helpers.dart';

String typeLabel(bool ur, String type) {
  switch (type) {
    case 'Dine-In':
      return tr(ur, 'Dine-In', 'ڈائن ان');
    case 'Takeaway':
      return tr(ur, 'Takeaway', 'ٹیک اوے');
    case 'Delivery':
      return tr(ur, 'Delivery', 'ڈیلیوری');
    default:
      return type;
  }
}

/* ============================================================================
 * CART STATE
 * ========================================================================= */

class OrderToken {
  OrderToken({
    required this.id,
    required this.label,
    required this.tableName,
    required this.items,
    required this.orderType,
    required this.discountText,
    required this.mobile,
    required this.address,
    required this.timeSeated,
  });

  final String id;
  final String label;
  final String tableName;
  final List<CartItem> items;
  final String orderType;
  final String discountText;
  final String mobile;
  final String address;
  final DateTime timeSeated;

  double get total => items.fold(0.0, (sum, c) => sum + c.total);
  int get units => items.fold(0, (sum, c) => sum + c.quantity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'table': tableName,
        'type': orderType,
        'disc': discountText,
        'mobile': mobile,
        'address': address,
        'time': timeSeated.toIso8601String(),
        'items': items
            .map((c) => {'m': c.item.toMap(), 'q': c.quantity, 'p': c.customPrice})
            .toList(),
      };

  factory OrderToken.fromJson(Map<String, dynamic> j) => OrderToken(
        id: j['id'] as String,
        label: j['label'] as String,
        tableName: j['table'] as String,
        orderType: j['type'] as String,
        discountText: (j['disc'] as String?) ?? '',
        mobile: (j['mobile'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        timeSeated: DateTime.tryParse((j['time'] as String?) ?? '') ??
            DateTime.now(),
        items: (j['items'] as List<dynamic>).map((e) {
          final m = e as Map<String, dynamic>;
          return CartItem(
            item: MenuItem.fromMap(Map<String, dynamic>.from(m['m'] as Map)),
            quantity: (m['q'] as num).toInt(),
            customPrice: (m['p'] as num).toDouble(),
          );
        }).toList(),
      );
}

class CartController extends ChangeNotifier {
  CartController() {
    discountCtrl.addListener(notifyListeners);
    mobileCtrl.addListener(notifyListeners);
    addressCtrl.addListener(notifyListeners);
  }

  final List<CartItem> items = [];
  final TextEditingController discountCtrl = TextEditingController();
  final TextEditingController mobileCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();

  String orderType = 'Dine-In';
  String? table;

  bool get isEmpty => items.isEmpty;
  int get units => items.fold(0, (sum, c) => sum + c.quantity);
  double get subTotal => items.fold(0.0, (sum, c) => sum + c.total);

  double get discount {
    final v = double.tryParse(discountCtrl.text.trim()) ?? 0;
    if (v < 0) return 0;
    return v > subTotal ? subTotal : v;
  }

  double get grandTotal => subTotal - discount;

  void add(MenuItem m) {
    final i = items.indexWhere((c) => c.item.id == m.id);
    if (i >= 0) {
      items[i].quantity++;
    } else {
      items.add(CartItem(item: m));
    }
    notifyListeners();
  }

  void setQty(CartItem c, int q) {
    if (q <= 0) {
      items.remove(c);
    } else {
      c.quantity = q;
    }
    notifyListeners();
  }

  void addMany(MenuItem m, int q) {
    final i = items.indexWhere((c) => c.item.id == m.id);
    if (i >= 0) {
      items[i].quantity += q;
    } else {
      items.add(CartItem(item: m, quantity: q));
    }
    notifyListeners();
  }

  void increment(CartItem c) {
    c.quantity++;
    notifyListeners();
  }

  void decrement(CartItem c) {
    if (c.quantity > 1) {
      c.quantity--;
    } else {
      items.remove(c);
    }
    notifyListeners();
  }

  void setPrice(CartItem c, double price) {
    c.customPrice = price;
    notifyListeners();
  }

  void setOrderType(String type) {
    orderType = type;
    if (type != 'Dine-In') table = null;
    notifyListeners();
  }

  void setTable(String? value) {
    table = value;
    notifyListeners();
  }

  void clear() {
    items.clear();
    discountCtrl.clear();
    mobileCtrl.clear();
    addressCtrl.clear();
    table = null;
    notifyListeners();
  }

  OrderToken toToken(String label) => OrderToken(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: label,
        tableName: table ?? kNoTable,
        items: items.map((c) => c.copy()).toList(),
        orderType: orderType,
        discountText: discountCtrl.text,
        mobile: mobileCtrl.text,
        address: addressCtrl.text,
        timeSeated: DateTime.now(),
      );

  void loadToken(OrderToken t) {
    items
      ..clear()
      ..addAll(t.items.map((c) => c.copy()));
    orderType = t.orderType;
    table = t.tableName == kNoTable ? null : t.tableName;
    discountCtrl.text = t.discountText;
    mobileCtrl.text = t.mobile;
    addressCtrl.text = t.address;
    notifyListeners();
  }

  @override
  void dispose() {
    discountCtrl.dispose();
    mobileCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }
}

/* ============================================================================
 * POS TERMINAL
 * ========================================================================= */

class PosTerminalView extends StatefulWidget {
  const PosTerminalView({
    super.key,
    required this.isUrdu,
    required this.cart,
    required this.onHold,
  });

  final bool isUrdu;
  final CartController cart;
  final VoidCallback onHold;

  @override
  State<PosTerminalView> createState() => _PosTerminalViewState();
}

class _PayChoice {
  const _PayChoice(this.method, this.isPaid, this.after);
  final String method;
  final bool isPaid;
  final String after;
}

class _PosTerminalViewState extends State<PosTerminalView> {
  late Future<List<MenuItem>> _menuFuture;
  List<String> _types = const ['Dine-In', 'Takeaway', 'Delivery'];
  BuildContext? _sheetCtx;
  bool _saving = false;

  bool get _ur => widget.isUrdu;

  @override
  void initState() {
    super.initState();
    _menuFuture = DatabaseHelper.instance.getMenuItems();
    _loadTypes();
    DatabaseHelper.revision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    DatabaseHelper.revision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    setState(() {
      _menuFuture = DatabaseHelper.instance.getMenuItems();
    });
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final s = await DatabaseHelper.instance.getSettings();
    if (!mounted) return;
    final types = <String>[
      if (s['enable_dine_in'] == '1') 'Dine-In',
      if (s['enable_takeaway'] == '1') 'Takeaway',
      if (s['enable_delivery'] == '1') 'Delivery',
    ];
    if (types.isEmpty) types.add('Takeaway');
    setState(() {
      _types = types;
    });
    if (!types.contains(widget.cart.orderType)) {
      widget.cart.setOrderType(types.first);
    }
  }

  Future<void> _askQty(MenuItem item) async {
    final v = await promptNumber(
      context,
      title: _ur ? item.nameUr : item.nameEn,
      label: tr(_ur, 'Quantity to add', 'شامل کرنے کی مقدار'),
      allowZero: false,
      ok: tr(_ur, 'Add', 'شامل کریں'),
      cancel: tr(_ur, 'Cancel', 'منسوخ'),
    );
    if (v != null && v >= 1) widget.cart.addMany(item, v.floor());
  }

  void _closeSheet() {
    final ctx = _sheetCtx;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx).pop();
    }
  }

  void _openCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        _sheetCtx = ctx;
        final h = MediaQuery.sizeOf(ctx).height;
        final inset = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: SizedBox(height: h * 0.88, child: _cartPanel()),
        );
      },
    ).whenComplete(() {
      _sheetCtx = null;
    });
  }

  void _hold() {
    widget.onHold();
    _closeSheet();
  }

  Widget _cartPanel() => CartPanel(
        cart: widget.cart,
        isUrdu: _ur,
        types: _types,
        onCheckout: _checkout,
        onHold: _hold,
      );

  Future<void> _checkout() async {
    final cart = widget.cart;
    if (cart.isEmpty || _saving) return;

    final mobile = cart.mobileCtrl.text.trim();
    if (cart.orderType == 'Delivery' && mobile.isEmpty) {
      toast(
          context,
          tr(_ur, 'Mobile number is required for Delivery orders.',
              'ڈیلیوری آرڈر کے لیے موبائل نمبر ضروری ہے۔'),
          error: true);
      return;
    }

    final choice = await showDialog<_PayChoice>(
      context: context,
      builder: (_) => _PaymentDialog(isUrdu: _ur, total: cart.grandTotal),
    );
    if (choice == null || !mounted) return;

    if (!choice.isPaid && mobile.isEmpty) {
      toast(
          context,
          tr(_ur, 'Enter the customer mobile number to record Udhar.',
              'ادھار لکھنے کے لیے گاہک کا موبائل نمبر درج کریں۔'),
          error: true);
      return;
    }

    final shortages = await DatabaseHelper.instance.checkStock(cart.items);
    if (!mounted) return;
    if (shortages.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(_ur, 'Low stock', 'اسٹاک کم ہے')),
          content: Text(shortages.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(_ur, 'Cancel', 'منسوخ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(_ur, 'Sell anyway', 'پھر بھی فروخت کریں')),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    final orderType = cart.orderType == 'Dine-In' && cart.table != null
        ? 'Dine-In (${cart.table})'
        : cart.orderType;

    setState(() => _saving = true);
    try {
      final sale = await DatabaseHelper.instance.processSale(
        items: List<CartItem>.from(cart.items),
        discount: cart.discount,
        paymentMethod: choice.method,
        orderType: orderType,
        isPaid: choice.isPaid,
        mobile: mobile,
        address: cart.addressCtrl.text.trim(),
      );
      if (!mounted) return;
      cart.clear();
      _closeSheet();
      final data = ReceiptData.fromSale(sale);
      if (choice.after == 'show') {
        showReceiptSheet(context, data: data, isUrdu: _ur);
      } else {
        toast(context,
            '${tr(_ur, 'Saved', 'محفوظ ہو گیا')}: ${sale.billNo} ${sale.tokenNo}');
        if (choice.after == 'print') {
          printReceipt(data).catchError((Object e) {
            if (mounted) toast(context, 'Could not print: $e', error: true);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        toast(context, 'Could not save the sale: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _menuGrid() {
    return FutureBuilder<List<MenuItem>>(
      future: _menuFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(_ur, 'No menu items yet. Add some in the Menu tab.',
                    'ابھی کوئی آئٹم نہیں۔ مینو ٹیب میں شامل کریں۔'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        return ListenableBuilder(
          listenable: widget.cart,
          builder: (context, _) => GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: 1.05,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final inCart = widget.cart.items
                  .where((c) => c.item.id == item.id)
                  .fold<int>(0, (sum, c) => sum + c.quantity);
              return Card(
                elevation: 2,
                clipBehavior: Clip.antiAlias,
                color: item.inStock
                    ? Colors.orange.shade50
                    : Colors.grey.shade300,
                child: InkWell(
                  onTap: item.inStock ? () => widget.cart.add(item) : null,
                  onLongPress: item.inStock ? () => _askQty(item) : null,
                  child: Stack(
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(item.iconData,
                                  size: 34, color: scheme.primary),
                              const SizedBox(height: 6),
                              Text(
                                _ur ? item.nameUr : item.nameEn,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.inStock
                                    ? money(item.price)
                                    : tr(_ur, 'OUT OF STOCK', 'اسٹاک ختم'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: item.inStock
                                      ? scheme.primary
                                      : Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (item.inStock)
                        PositionedDirectional(
                          top: 0,
                          start: 0,
                          child: IconButton(
                            tooltip: tr(_ur, 'Enter quantity', 'مقدار درج کریں'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.dialpad, size: 18),
                            onPressed: () => _askQty(item),
                          ),
                        ),
                      if (inCart > 0)
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.green.shade700,
                            child: Text(
                              '$inCart',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _cartBar() {
    return ListenableBuilder(
      listenable: widget.cart,
      builder: (context, _) {
        final c = widget.cart;
        return Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${c.units} ${tr(_ur, 'items', 'آئٹمز')}'),
                      Text(
                        money(c.grandTotal),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.green.shade700,
                  ),
                  onPressed: c.isEmpty ? null : _openCart,
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: Text(tr(_ur, 'View cart', 'کارٹ دیکھیں')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              Expanded(child: _menuGrid()),
              SizedBox(
                width: 400,
                child: Card(
                  margin: const EdgeInsets.all(8),
                  elevation: 4,
                  child: _cartPanel(),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: _menuGrid()),
            _cartBar(),
          ],
        );
      },
    );
  }
}

/* ============================================================================
 * PAYMENT DIALOG
 * ========================================================================= */

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.isUrdu, required this.total});

  final bool isUrdu;
  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String _after = 'show';

  Widget _option(IconData icon, Color color, String title, String subtitle,
      String method, bool paid) {
    return ListTile(
      leading: Icon(icon, size: 32, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.pop(context, _PayChoice(method, paid, _after)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    return AlertDialog(
      title: Text('${tr(ur, 'Payment', 'ادائیگی')}: ${money(widget.total)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(Icons.payments, Colors.green.shade700,
              tr(ur, 'Paid: Cash', 'ادا شدہ: نقد'),
              tr(ur, 'Money received in hand', 'رقم وصول ہو گئی'), 'Cash', true),
          _option(
              Icons.qr_code,
              Colors.blue.shade700,
              tr(ur, 'Paid: Online', 'ادا شدہ: آن لائن'),
              'EasyPaisa / JazzCash / Bank',
              'Online',
              true),
          const Divider(),
          _option(
              Icons.pending_actions,
              Colors.red.shade700,
              tr(ur, 'Udhar (unpaid)', 'ادھار (غیر ادا شدہ)'),
              tr(ur, 'Record as balance to collect', 'وصولی کے لیے لکھیں'),
              'Unpaid',
              false),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'none', label: Text(tr(ur, 'Save only', 'صرف محفوظ'))),
              ButtonSegment(value: 'show', label: Text(tr(ur, 'Receipt', 'رسید'))),
              ButtonSegment(value: 'print', label: Text(tr(ur, 'Print', 'پرنٹ'))),
            ],
            selected: {_after},
            onSelectionChanged: (v) => setState(() => _after = v.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(ur, 'Cancel', 'منسوخ')),
        ),
      ],
    );
  }
}

/* ============================================================================
 * CART PANEL (used in the side panel and in the phone bottom sheet)
 * ========================================================================= */

class CartPanel extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.cart,
    required this.isUrdu,
    required this.types,
    required this.onCheckout,
    required this.onHold,
  });

  final CartController cart;
  final bool isUrdu;
  final List<String> types;
  final VoidCallback onCheckout;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final ur = isUrdu;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final t in types)
                        ChoiceChip(
                          label: Text(typeLabel(ur, t)),
                          selected: cart.orderType == t,
                          onSelected: (_) => cart.setOrderType(t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (cart.orderType == 'Dine-In') ...[
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: tr(ur, 'Table (optional)', 'ٹیبل (اختیاری)'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: cart.table,
                          isExpanded: true,
                          isDense: true,
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null, child: Text('-')),
                            for (final t in kDineTables)
                              DropdownMenuItem<String?>(
                                  value: t, child: Text(t)),
                          ],
                          onChanged: cart.setTable,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: cart.mobileCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: cart.orderType == 'Delivery'
                          ? tr(ur, 'Customer mobile (required)',
                              'گاہک کا موبائل (ضروری)')
                          : tr(ur, 'Customer mobile (for Udhar)',
                              'گاہک کا موبائل (ادھار کے لیے)'),
                      prefixIcon: const Icon(Icons.phone),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (cart.orderType == 'Delivery') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: cart.addressCtrl,
                      decoration: InputDecoration(
                        labelText: tr(ur, 'Delivery address', 'ڈیلیوری کا پتہ'),
                        prefixIcon: const Icon(Icons.home),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const Divider(height: 24),
                  if (cart.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          tr(ur, 'Cart is empty. Tap an item to add it.',
                              'کارٹ خالی ہے۔ آئٹم پر ٹیپ کریں۔'),
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (final line in cart.items)
                      _CartLine(
                        key: ObjectKey(line),
                        cart: cart,
                        line: line,
                        isUrdu: ur,
                      ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            '${tr(ur, 'Subtotal', 'ذیلی کل')}: ${money(cart.subTotal)}'),
                      ),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: cart.discountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          decoration: InputDecoration(
                            labelText: tr(ur, 'Discount', 'رعایت'),
                            prefixText: 'Rs. ',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tr(ur, 'TOTAL', 'کل'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                          money(cart.grandTotal),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton.outlined(
                        tooltip: tr(ur, 'Clear cart', 'کارٹ صاف کریں'),
                        onPressed: cart.isEmpty
                            ? null
                            : () async {
                                final ok = await confirmDialog(
                                  context,
                                  title: tr(ur, 'Clear cart?', 'کارٹ صاف کریں؟'),
                                  message: tr(
                                      ur,
                                      'All items in this order will be removed.',
                                      'اس آرڈر کے تمام آئٹم ہٹا دیے جائیں گے۔'),
                                  yes: tr(ur, 'Clear', 'صاف کریں'),
                                  no: tr(ur, 'Cancel', 'منسوخ'),
                                  danger: true,
                                );
                                if (ok) cart.clear();
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48)),
                        onPressed: cart.isEmpty ? null : onHold,
                        child: Text(tr(ur, 'Hold', 'روکیں')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            backgroundColor: Colors.green.shade700,
                          ),
                          onPressed: cart.isEmpty ? null : onCheckout,
                          child: Text(
                            tr(ur, 'Checkout', 'چیک آؤٹ'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    super.key,
    required this.cart,
    required this.line,
    required this.isUrdu,
  });

  final CartController cart;
  final CartItem line;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    final name = isUrdu ? line.item.nameUr : line.item.nameEn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final v = await promptNumber(
                  context,
                  title: name,
                  label: tr(isUrdu, 'Price (Rs.)', 'قیمت (روپے)'),
                  initial: line.customPrice,
                  ok: tr(isUrdu, 'OK', 'ٹھیک ہے'),
                  cancel: tr(isUrdu, 'Cancel', 'منسوخ'),
                );
                if (v != null) cart.setPrice(line, v);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${money(line.customPrice)} ${tr(isUrdu, 'each', 'فی عدد')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => cart.decrement(line),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              final v = await promptNumber(
                context,
                title: name,
                label: tr(isUrdu, 'Quantity (0 removes)', 'مقدار (0 سے ہٹ جائے گا)'),
                initial: line.quantity.toDouble(),
                ok: tr(isUrdu, 'OK', 'ٹھیک ہے'),
                cancel: tr(isUrdu, 'Cancel', 'منسوخ'),
              );
              if (v != null) cart.setQty(line, v.floor());
            },
            child: Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${line.quantity}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => cart.increment(line),
          ),
          SizedBox(
            width: 70,
            child: Text(
              money(line.total),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================================
 * TABLES (held orders)
 * ========================================================================= */

class TablesView extends StatelessWidget {
  const TablesView({
    super.key,
    required this.isUrdu,
    required this.orders,
    required this.onNewOrder,
    required this.onOpen,
    required this.onDiscard,
  });

  final bool isUrdu;
  final List<OrderToken> orders;
  final void Function(String tableName) onNewOrder;
  final void Function(OrderToken order) onOpen;
  final void Function(OrderToken order) onDiscard;

  @override
  Widget build(BuildContext context) {
    final ur = isUrdu;
    final names = [...kDineTables, kNoTable];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final name in names) _tableCard(context, ur, name),
          ],
        ),
      ),
    );
  }

  Widget _tableCard(BuildContext context, bool ur, String name) {
    final mine = orders.where((o) => o.tableName == name).toList();
    final busy = mine.isNotEmpty;
    final title =
        name == kNoTable ? tr(ur, 'Takeaway / no table', 'ٹیک اوے / بغیر ٹیبل') : name;
    return Card(
      color: busy ? Colors.amber.shade100 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Chip(
                  label: Text(busy
                      ? '${mine.length} ${tr(ur, 'open', 'کھلے')}'
                      : tr(ur, 'Free', 'خالی')),
                  backgroundColor:
                      busy ? Colors.orange.shade200 : Colors.green.shade100,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            for (final o in mine)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '${tr(ur, 'Order', 'آرڈر')} ${o.label}: ${o.units} ${tr(ur, 'items', 'آئٹمز')}'),
                subtitle: Text('${money(o.total)}  -  ${fmtTime(o.timeSeated)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr(ur, 'Open', 'کھولیں'),
                      icon: const Icon(Icons.play_circle_fill,
                          color: Colors.green),
                      onPressed: () => onOpen(o),
                    ),
                    IconButton(
                      tooltip: tr(ur, 'Discard', 'ختم کریں'),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => onDiscard(o),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            FilledButton.tonalIcon(
              onPressed: () => onNewOrder(name),
              icon: const Icon(Icons.add),
              label: Text(tr(ur, 'New order', 'نیا آرڈر')),
            ),
          ],
        ),
      ),
    );
  }
}
