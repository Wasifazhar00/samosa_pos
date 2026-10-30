import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup.dart';
import 'data.dart';
import 'receipt.dart';
import 'thermal.dart';
import 'reports.dart';
import 'ui_helpers.dart';

/* ============================================================================
 * MENU MANAGEMENT
 * ========================================================================= */

class MenuManagementView extends StatefulWidget {
  const MenuManagementView(
      {super.key, required this.isUrdu, required this.locked});

  final bool isUrdu;
  final bool locked;

  @override
  State<MenuManagementView> createState() => _MenuManagementViewState();
}

class _MenuManagementViewState extends State<MenuManagementView> {
  late Future<List<MenuItem>> _future;

  bool get _ur => widget.isUrdu;

  @override
  void initState() {
    super.initState();
    _future = DatabaseHelper.instance.getMenuItems();
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
      _future = DatabaseHelper.instance.getMenuItems();
    });
  }

  Future<void> _addOrEdit([MenuItem? item]) async {
    final result = await showDialog<MenuItem>(
      context: context,
      builder: (_) => _MenuItemDialog(item: item, isUrdu: _ur),
    );
    if (result == null) return;
    if (item == null) {
      await DatabaseHelper.instance.addMenuItem(result);
    } else {
      await DatabaseHelper.instance.updateMenuItem(result);
    }
  }

  Future<void> _editRecipe(MenuItem item) async {
    final inventory = await DatabaseHelper.instance.getInventory();
    final recipe = await DatabaseHelper.instance.getRecipe(item.id!);
    if (!mounted) return;
    final result = await showDialog<Map<int, double>>(
      context: context,
      builder: (_) => _RecipeDialog(
        item: item,
        inventory: inventory,
        recipe: recipe,
        isUrdu: _ur,
      ),
    );
    if (result == null) return;
    await DatabaseHelper.instance.saveRecipe(item.id!, result);
    if (!mounted) return;
    toast(context, tr(_ur, 'Recipe saved', 'ریسیپی محفوظ ہو گئی'));
  }

  Future<void> _delete(MenuItem item) async {
    final ok = await confirmDialog(
      context,
      title: tr(_ur, 'Delete item?', 'آئٹم حذف کریں؟'),
      message: tr(
        _ur,
        '"${item.nameEn}" and its recipe will be removed. Past bills are not affected.',
        '"${item.nameUr}" اور اس کی ریسیپی ہٹا دی جائے گی۔ پرانے بل متاثر نہیں ہوں گے۔',
      ),
      yes: tr(_ur, 'Delete', 'حذف کریں'),
      no: tr(_ur, 'Cancel', 'منسوخ'),
      danger: true,
    );
    if (ok) await DatabaseHelper.instance.deleteMenuItem(item.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: Text(tr(_ur, 'Add item', 'آئٹم شامل کریں')),
      ),
      body: FutureBuilder<List<MenuItem>>(
        future: _future,
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
              child: Text(tr(_ur, 'No menu items yet.', 'ابھی کوئی آئٹم نہیں۔')),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: items.length,
                onReorder: (o, n) {
                  final l = List<MenuItem>.of(items);
                  if (n > o) n -= 1;
                  l.insert(n, l.removeAt(o));
                  DatabaseHelper.instance.reorderMenu([for (final m in l) m.id!]);
                },
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    key: ValueKey(item.id),
                    child: ListTile(
                      leading: ItemThumb(
                          path: item.imagePath, icon: item.iconData, size: 44),
                      title: Text(
                        _ur ? item.nameUr : item.nameEn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${money(item.price)}  -  ${item.inStock ? tr(_ur, 'Available', 'دستیاب') : tr(_ur, 'Not available', 'دستیاب نہیں')}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!widget.locked)
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                          Switch(
                            value: item.inStock,
                            onChanged: (v) => DatabaseHelper.instance
                                .updateMenuItem(item.copyWith(inStock: v)),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _addOrEdit(item);
                              if (v == 'recipe') _editRecipe(item);
                              if (v == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'edit',
                                  child: Text(tr(_ur, 'Edit', 'ترمیم'))),
                              PopupMenuItem(
                                  value: 'recipe',
                                  child: Text(tr(_ur,
                                      'Recipe (stock used)', 'ریسیپی (اسٹاک)'))),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text(tr(_ur, 'Delete', 'حذف کریں'))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuItemDialog extends StatefulWidget {
  const _MenuItemDialog({required this.item, required this.isUrdu});

  final MenuItem? item;
  final bool isUrdu;

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  late final TextEditingController _en =
      TextEditingController(text: widget.item?.nameEn ?? '');
  late final TextEditingController _ur =
      TextEditingController(text: widget.item?.nameUr ?? '');
  late final TextEditingController _price = TextEditingController(
      text: widget.item == null ? '' : qtyText(widget.item!.price));
  late String _icon = widget.item?.iconKey ?? 'fastfood';
  late String _img = widget.item?.imagePath ?? '';
  String? _nameError;
  String? _priceError;

  @override
  void dispose() {
    _en.dispose();
    _ur.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final name = _en.text.trim();
    final price = double.tryParse(_price.text.trim());
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _priceError = (price == null || price < 0) ? 'Enter a valid price' : null;
    });
    if (_nameError != null || _priceError != null) return;
    Navigator.pop(
      context,
      MenuItem(
        id: widget.item?.id,
        nameEn: name,
        nameUr: _ur.text.trim().isEmpty ? name : _ur.text.trim(),
        price: price!,
        iconKey: _icon,
        inStock: widget.item?.inStock ?? true,
        imagePath: _img,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    return AlertDialog(
      title: Text(widget.item == null
          ? tr(ur, 'Add menu item', 'مینو آئٹم شامل کریں')
          : tr(ur, 'Edit menu item', 'مینو آئٹم میں ترمیم')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _en,
              decoration: InputDecoration(
                  labelText: tr(ur, 'English name', 'انگریزی نام'),
                  errorText: _nameError),
            ),
            TextField(
              controller: _ur,
              textDirection: TextDirection.rtl,
              decoration:
                  InputDecoration(labelText: tr(ur, 'Urdu name', 'اردو نام')),
            ),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: InputDecoration(
                  labelText: tr(ur, 'Price (Rs.)', 'قیمت (روپے)'),
                  errorText: _priceError),
            ),
            const SizedBox(height: 12),
            ImagePickRow(
              path: _img,
              icon: kIconChoices[_icon] ?? Icons.fastfood,
              onChanged: (v) => setState(() => _img = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final e in kIconChoices.entries)
                  ChoiceChip(
                    label: Icon(e.value, size: 22),
                    selected: _icon == e.key,
                    onSelected: (_) => setState(() => _icon = e.key),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(ur, 'Cancel', 'منسوخ')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(tr(ur, 'Save', 'محفوظ کریں')),
        ),
      ],
    );
  }
}

class _RecipeDialog extends StatefulWidget {
  const _RecipeDialog({
    required this.item,
    required this.inventory,
    required this.recipe,
    required this.isUrdu,
  });

  final MenuItem item;
  final List<InventoryItem> inventory;
  final Map<int, double> recipe;
  final bool isUrdu;

  @override
  State<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<_RecipeDialog> {
  late final Map<int, TextEditingController> _ctrls = {
    for (final inv in widget.inventory)
      inv.id!: TextEditingController(
        text: widget.recipe.containsKey(inv.id)
            ? qtyText(widget.recipe[inv.id]!)
            : '',
      ),
  };
  String? _error;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final result = <int, double>{};
    for (final e in _ctrls.entries) {
      final text = e.value.text.trim();
      if (text.isEmpty) continue;
      final v = double.tryParse(text);
      if (v == null || v < 0) {
        setState(() => _error = 'Check the quantities');
        return;
      }
      if (v > 0) result[e.key] = v;
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    return AlertDialog(
      title: Text(
          '${tr(ur, 'Recipe', 'ریسیپی')}: ${ur ? widget.item.nameUr : widget.item.nameEn}'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: widget.inventory.isEmpty
            ? Center(
                child: Text(tr(
                    ur,
                    'Add materials in the Stock tab first.',
                    'پہلے اسٹاک ٹیب میں سامان شامل کریں۔')))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                        ur,
                        'Stock used for 1 sold. Leave blank if not used.',
                        'ایک فروخت پر استعمال ہونے والا اسٹاک۔ استعمال نہ ہو تو خالی چھوڑیں۔'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(color: Colors.red.shade700)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final inv in widget.inventory)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text('${inv.name} (${inv.unit})')),
                                SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: _ctrls[inv.id!],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9.]'))
                                    ],
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(ur, 'Cancel', 'منسوخ')),
        ),
        if (widget.inventory.isNotEmpty)
          FilledButton(
            onPressed: _save,
            child: Text(tr(ur, 'Save', 'محفوظ کریں')),
          ),
      ],
    );
  }
}

/* ============================================================================
 * STOCK / INVENTORY
 * ========================================================================= */

class InventoryView extends StatefulWidget {
  const InventoryView(
      {super.key, required this.isUrdu, required this.locked});

  final bool isUrdu;
  final bool locked;

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  late Future<List<InventoryItem>> _future;

  bool get _ur => widget.isUrdu;

  @override
  void initState() {
    super.initState();
    _future = DatabaseHelper.instance.getInventory();
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
      _future = DatabaseHelper.instance.getInventory();
    });
  }

  Future<void> _addOrEdit([InventoryItem? item]) async {
    final result = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => _MaterialDialog(item: item, isUrdu: _ur),
    );
    if (result == null) return;
    if (item == null) {
      await DatabaseHelper.instance.addInventoryItem(result);
    } else {
      await DatabaseHelper.instance.updateInventoryItem(result);
    }
  }

  Future<void> _addStock(InventoryItem item) async {
    final v = await promptNumber(
      context,
      title: '${tr(_ur, 'Add stock', 'اسٹاک شامل کریں')}: ${item.name}',
      label: '${tr(_ur, 'Quantity to add', 'شامل کرنے کی مقدار')} (${item.unit})',
      allowZero: false,
      ok: tr(_ur, 'Add', 'شامل کریں'),
      cancel: tr(_ur, 'Cancel', 'منسوخ'),
    );
    if (v != null) await DatabaseHelper.instance.adjustStock(item.id!, v);
  }

  Future<void> _setStock(InventoryItem item) async {
    final v = await promptNumber(
      context,
      title: '${tr(_ur, 'Set stock count', 'اسٹاک گنتی درج کریں')}: ${item.name}',
      label: '${tr(_ur, 'Quantity in hand', 'موجود مقدار')} (${item.unit})',
      initial: item.stockQty,
      ok: tr(_ur, 'Save', 'محفوظ کریں'),
      cancel: tr(_ur, 'Cancel', 'منسوخ'),
    );
    if (v != null) await DatabaseHelper.instance.setStock(item.id!, v);
  }

  Future<void> _delete(InventoryItem item) async {
    final ok = await confirmDialog(
      context,
      title: tr(_ur, 'Delete material?', 'سامان حذف کریں؟'),
      message: tr(
        _ur,
        '"${item.name}" will be removed from stock and from every recipe that uses it.',
        '"${item.name}" اسٹاک اور تمام ریسیپیز سے ہٹا دیا جائے گا۔',
      ),
      yes: tr(_ur, 'Delete', 'حذف کریں'),
      no: tr(_ur, 'Cancel', 'منسوخ'),
      danger: true,
    );
    if (ok) await DatabaseHelper.instance.deleteInventoryItem(item.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_box),
        label: Text(tr(_ur, 'Add material', 'سامان شامل کریں')),
      ),
      body: FutureBuilder<List<InventoryItem>>(
        future: _future,
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
              child: Text(tr(_ur, 'No materials yet.', 'ابھی کوئی سامان نہیں۔')),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: items.length,
                onReorder: (o, n) {
                  final l = List<InventoryItem>.of(items);
                  if (n > o) n -= 1;
                  l.insert(n, l.removeAt(o));
                  DatabaseHelper.instance
                      .reorderInventory([for (final m in l) m.id!]);
                },
                itemBuilder: (context, index) {
                  final item = items[index];
                  final low = item.isLow;
                  return Card(
                    key: ValueKey(item.id),
                    child: ListTile(
                      leading: ItemThumb(
                          path: item.imagePath,
                          icon: Icons.inventory_2,
                          size: 44,
                          color: low ? Colors.red.shade700 : Colors.green.shade700),
                      title: Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        low
                            ? tr(_ur, 'Low stock: reorder soon',
                                'اسٹاک کم ہے: جلد منگوائیں')
                            : tr(_ur, 'In stock', 'اسٹاک موجود ہے'),
                        style: TextStyle(
                            color: low ? Colors.red.shade700 : null),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!widget.locked)
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                          Text(
                            '${qtyText(item.stockQty)} ${item.unit}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: low ? Colors.red.shade700 : null,
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'add') _addStock(item);
                              if (v == 'set') _setStock(item);
                              if (v == 'edit') _addOrEdit(item);
                              if (v == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'add',
                                  child: Text(
                                      tr(_ur, 'Add stock', 'اسٹاک شامل کریں'))),
                              PopupMenuItem(
                                  value: 'set',
                                  child: Text(tr(
                                      _ur, 'Set exact count', 'درست گنتی درج کریں'))),
                              PopupMenuItem(
                                  value: 'edit',
                                  child: Text(tr(_ur, 'Edit', 'ترمیم'))),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text(tr(_ur, 'Delete', 'حذف کریں'))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MaterialDialog extends StatefulWidget {
  const _MaterialDialog({required this.item, required this.isUrdu});

  final InventoryItem? item;
  final bool isUrdu;

  @override
  State<_MaterialDialog> createState() => _MaterialDialogState();
}

class _MaterialDialogState extends State<_MaterialDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.item?.name ?? '');
  late final TextEditingController _qty = TextEditingController(text: '');
  late final TextEditingController _unit =
      TextEditingController(text: widget.item?.unit ?? 'pcs');
  late final TextEditingController _low = TextEditingController(
      text: qtyText(widget.item?.lowLevel ?? 10));
  String? _nameError;
  String? _qtyError;
  String? _lowError;
  late String _img = widget.item?.imagePath ?? '';

  bool get _isNew => widget.item == null;

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _unit.dispose();
    _low.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final qty = _isNew ? double.tryParse(_qty.text.trim()) : widget.item!.stockQty;
    final low = double.tryParse(_low.text.trim());
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _qtyError = (qty == null || qty < 0) ? 'Enter a valid quantity' : null;
      _lowError = (low == null || low < 0) ? 'Enter a valid number' : null;
    });
    if (_nameError != null || _qtyError != null || _lowError != null) return;
    Navigator.pop(
      context,
      InventoryItem(
        id: widget.item?.id,
        name: name,
        stockQty: qty!,
        unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
        lowLevel: low!,
        imagePath: _img,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    const numFmt = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: Text(_isNew
          ? tr(ur, 'Add material', 'سامان شامل کریں')
          : tr(ur, 'Edit material', 'سامان میں ترمیم')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: tr(ur, 'Material name', 'سامان کا نام'),
                  errorText: _nameError),
            ),
            const SizedBox(height: 8),
            ImagePickRow(
              path: _img,
              icon: Icons.inventory_2,
              onChanged: (v) => setState(() => _img = v),
            ),
            if (_isNew)
              TextField(
                controller: _qty,
                keyboardType: numFmt,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: InputDecoration(
                    labelText: tr(ur, 'Starting quantity', 'ابتدائی مقدار'),
                    errorText: _qtyError),
              ),
            TextField(
              controller: _unit,
              decoration: InputDecoration(
                  labelText:
                      tr(ur, 'Unit (pcs, kg, bottles)', 'اکائی (عدد، کلو، بوتل)')),
            ),
            TextField(
              controller: _low,
              keyboardType: numFmt,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: InputDecoration(
                  labelText: tr(ur, 'Warn me when stock is at or below',
                      'اسٹاک اس سے کم ہو تو خبردار کریں'),
                  errorText: _lowError),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(ur, 'Cancel', 'منسوخ')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(tr(ur, 'Save', 'محفوظ کریں')),
        ),
      ],
    );
  }
}

/* ============================================================================
 * TRANSACTIONS / UDHAR LEDGER
 * ========================================================================= */

class ReportsAndSalesHistoryView extends StatefulWidget {
  const ReportsAndSalesHistoryView({super.key, required this.isUrdu});

  final bool isUrdu;

  @override
  State<ReportsAndSalesHistoryView> createState() =>
      _ReportsAndSalesHistoryViewState();
}

class _SaleEdit {
  const _SaleEdit(this.amount, this.mobile, this.address);
  final double amount;
  final String mobile;
  final String address;
}

class _ReportsAndSalesHistoryViewState
    extends State<ReportsAndSalesHistoryView> {
  late Future<List<SaleRecord>> _future;
  String _search = '';
  String _payFilter = 'All';
  bool _todayOnly = true;

  bool get _ur => widget.isUrdu;

  @override
  void initState() {
    super.initState();
    _future = DatabaseHelper.instance.getAllSales();
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
      _future = DatabaseHelper.instance.getAllSales();
    });
  }

  void _reprint(SaleRecord sale) {
    showReceiptSheet(context, data: ReceiptData.fromSale(sale), isUrdu: _ur);
  }

  Future<void> _edit(SaleRecord sale) async {
    final result = await showDialog<_SaleEdit>(
      context: context,
      builder: (_) => _EditSaleDialog(sale: sale, isUrdu: _ur),
    );
    if (result == null) return;
    await DatabaseHelper.instance.updateSaleDetails(
        sale.id!, result.amount, result.mobile, result.address);
  }

  Future<void> _markPaid(SaleRecord sale) async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr(_ur, 'Payment received as', 'ادائیگی کیسے ملی')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Cash'),
            child: Text(tr(_ur, 'Cash', 'نقد')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Online'),
            child: Text(tr(_ur, 'Online (EasyPaisa / JazzCash / Bank)',
                'آن لائن (ایزی پیسہ / جاز کیش / بینک)')),
          ),
        ],
      ),
    );
    if (method == null) return;
    await DatabaseHelper.instance
        .updatePaymentStatus(sale.id!, true, method: method);
  }

  Future<void> _markUnpaid(SaleRecord sale) async {
    final ok = await confirmDialog(
      context,
      title: tr(_ur, 'Mark as Udhar?', 'ادھار کے طور پر نشان زد کریں؟'),
      message: '${sale.billNo}: ${money(sale.totalAmount)}',
      yes: tr(_ur, 'Mark Udhar', 'ادھار کریں'),
      no: tr(_ur, 'Cancel', 'منسوخ'),
    );
    if (ok) {
      await DatabaseHelper.instance
          .updatePaymentStatus(sale.id!, false, method: 'Unpaid');
    }
  }

  Future<void> _delete(SaleRecord sale) async {
    final hasStockInfo = sale.lines.isNotEmpty;
    final ok = await confirmDialog(
      context,
      title: tr(_ur, 'Delete this bill?', 'یہ بل حذف کریں؟'),
      message: hasStockInfo
          ? tr(
              _ur,
              '${sale.billNo} (${money(sale.totalAmount)}) will be deleted and its stock returned to inventory.',
              '${sale.billNo} (${money(sale.totalAmount)}) حذف ہو جائے گا اور اسٹاک واپس شامل ہو گا۔')
          : tr(
              _ur,
              '${sale.billNo} (${money(sale.totalAmount)}) will be deleted. Stock for old bills cannot be restored.',
              '${sale.billNo} (${money(sale.totalAmount)}) حذف ہو جائے گا۔ پرانے بلوں کا اسٹاک واپس نہیں ہو سکتا۔'),
      yes: tr(_ur, 'Delete', 'حذف کریں'),
      no: tr(_ur, 'Cancel', 'منسوخ'),
      danger: true,
    );
    if (ok) {
      await DatabaseHelper.instance
          .deleteSale(sale, restoreStock: hasStockInfo);
    }
  }

  Widget _summaryCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        color: color.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(
                  value,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SaleRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final today = todayKey();
        final period = _todayOnly
            ? all.where((s) => s.createdAt.startsWith(today)).toList()
            : all;

        final paidTotal = period
            .where((s) => s.isPaid)
            .fold<double>(0, (sum, s) => sum + s.totalAmount);
        final udharAll = all
            .where((s) => !s.isPaid)
            .fold<double>(0, (sum, s) => sum + s.totalAmount);

        final q = _search.trim().toLowerCase();
        final shown = period.where((s) {
          final matchesSearch = q.isEmpty ||
              s.billNo.toLowerCase().contains(q) ||
              s.tokenNo.toLowerCase().contains(q) ||
              (s.customerMobile ?? '').contains(q);
          final matchesPay = _payFilter == 'All' ||
              (_payFilter == 'Paid' && s.isPaid) ||
              (_payFilter == 'Unpaid' && !s.isPaid);
          return matchesSearch && matchesPay;
        }).toList();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      _summaryCard(
                          _todayOnly
                              ? tr(_ur, 'Paid today', 'آج کی وصولی')
                              : tr(_ur, 'Paid (all)', 'کل وصولی'),
                          money(paidTotal),
                          Colors.green.shade800),
                      _summaryCard(tr(_ur, 'Udhar due (all)', 'ادھار باقی (کل)'),
                          money(udharAll), Colors.red.shade700),
                      _summaryCard(tr(_ur, 'Bills', 'بل'), '${period.length}',
                          Colors.blue.shade700),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: tr(_ur, 'Search bill, token or mobile',
                                'بل، ٹوکن یا موبائل تلاش کریں'),
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _payFilter,
                        items: [
                          DropdownMenuItem(
                              value: 'All',
                              child: Text(tr(_ur, 'All', 'تمام'))),
                          DropdownMenuItem(
                              value: 'Paid',
                              child: Text(tr(_ur, 'Paid', 'ادا شدہ'))),
                          DropdownMenuItem(
                              value: 'Unpaid',
                              child: Text(tr(_ur, 'Udhar', 'ادھار'))),
                        ],
                        onChanged: (v) =>
                            setState(() => _payFilter = v ?? 'All'),
                      ),
                      IconButton(
                        tooltip: tr(_ur, 'Sales reports', 'سیلز رپورٹس'),
                        icon: const Icon(Icons.bar_chart),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => SalesReportPage(isUrdu: _ur)),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: true,
                          label: Text(tr(_ur, 'Today', 'آج'))),
                      ButtonSegment(
                          value: false,
                          label: Text(tr(_ur, 'All time', 'تمام'))),
                    ],
                    selected: {_todayOnly},
                    onSelectionChanged: (s) =>
                        setState(() => _todayOnly = s.first),
                  ),
                ),
                const SizedBox(height: 4),
                const Divider(height: 1),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text(tr(_ur, 'No bills to show',
                              'دکھانے کے لیے کوئی بل نہیں')))
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: shown.length,
                          itemBuilder: (context, index) =>
                              _saleTile(shown[index]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _saleTile(SaleRecord sale) {
    final time = sale.createdTime;
    return Card(
      child: ListTile(
        onTap: () => _reprint(sale),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor:
              sale.isPaid ? Colors.green.shade700 : Colors.red.shade700,
          child: Icon(sale.isPaid ? Icons.check : Icons.priority_high,
              color: Colors.white, size: 16),
        ),
        title: Text('${sale.billNo}  ${sale.tokenNo}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${sale.orderType}${time == null ? '' : '  -  ${fmtDateTime(time)}'}\n'
          '${sale.itemsSummary}'
          '${(sale.customerMobile ?? '').isEmpty ? '' : '\n${sale.customerMobile}'}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              money(sale.totalAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sale.isPaid ? Colors.green.shade800 : Colors.red.shade700,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'print') _reprint(sale);
                if (v == 'paid') _markPaid(sale);
                if (v == 'unpaid') _markUnpaid(sale);
                if (v == 'edit') _edit(sale);
                if (v == 'delete') _delete(sale);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'print',
                    child: Text(tr(_ur, 'Receipt', 'رسید'))),
                if (!sale.isPaid)
                  PopupMenuItem(
                      value: 'paid',
                      child: Text(tr(_ur, 'Mark as paid', 'ادا شدہ کریں'))),
                if (sale.isPaid)
                  PopupMenuItem(
                      value: 'unpaid',
                      child: Text(tr(_ur, 'Mark as Udhar', 'ادھار کریں'))),
                PopupMenuItem(
                    value: 'edit', child: Text(tr(_ur, 'Edit', 'ترمیم'))),
                PopupMenuItem(
                    value: 'delete',
                    child: Text(tr(_ur, 'Delete', 'حذف کریں'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSaleDialog extends StatefulWidget {
  const _EditSaleDialog({required this.sale, required this.isUrdu});

  final SaleRecord sale;
  final bool isUrdu;

  @override
  State<_EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends State<_EditSaleDialog> {
  late final TextEditingController _amount =
      TextEditingController(text: qtyText(widget.sale.totalAmount));
  late final TextEditingController _mobile =
      TextEditingController(text: widget.sale.customerMobile ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.sale.customerAddress ?? '');
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _mobile.dispose();
    _address.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_amount.text.trim());
    if (v == null || v < 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    Navigator.pop(
        context, _SaleEdit(v, _mobile.text.trim(), _address.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    return AlertDialog(
      title: Text('${tr(ur, 'Edit bill', 'بل میں ترمیم')} ${widget.sale.billNo}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: InputDecoration(
                  labelText: tr(ur, 'Total amount (Rs.)', 'کل رقم (روپے)'),
                  errorText: _error),
            ),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: tr(ur, 'Customer mobile', 'گاہک کا موبائل')),
            ),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                  labelText: tr(ur, 'Delivery address', 'ڈیلیوری کا پتہ')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(ur, 'Cancel', 'منسوخ')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(tr(ur, 'Update bill', 'بل اپ ڈیٹ کریں')),
        ),
      ],
    );
  }
}

/* ============================================================================
 * SETTINGS
 * ========================================================================= */

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.isUrdu});

  final bool isUrdu;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _account = TextEditingController();

  bool _dineIn = true;
  bool _takeaway = true;
  bool _delivery = true;
  bool _loaded = false;
  final _pw = TextEditingController();
  final _ph = TextEditingController();
  final _qr1l = TextEditingController();
  final _qr2l = TextEditingController();
  final _qr2d = TextEditingController();
  bool _printQr = true;
  String _img1 = '';
  String _img2 = '';
  String _freq = 'off';
  String _pmode = 'system';
  String _pmac = '';
  String _pname = '';
  final _pip = TextEditingController();
  final _pcols = TextEditingController();
  final Map<String, String> _t = {};
  static const _tKeys = [
    'printer_win_name', 't_bold', 't_cut', 't_drawer', 't_feed', 't_copies',
    't_hname', 't_haddr', 't_hphone', 't_qty', 't_footer',
    'enable_tables', 'pay_cash', 'pay_online', 'pay_udhar', 'menu_layout'
  ];
  static const _presets = [
    ('80 mm roll', '80', '0'),
    ('58 mm roll', '58', '0'),
    ('A6', '105', '148'),
    ('A5', '148', '210'),
  ];

  bool get _ur => widget.isUrdu;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _account.dispose();
    _pw.dispose();
    _ph.dispose();
    _qr1l.dispose();
    _qr2l.dispose();
    _qr2d.dispose();
    _pip.dispose();
    _pcols.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await DatabaseHelper.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _name.text = s['shop_name'] ?? '';
      _address.text = s['shop_address'] ?? '';
      _phone.text = s['shop_phone'] ?? '';
      _account.text = s['payment_account_info'] ?? '';
      _dineIn = s['enable_dine_in'] == '1';
      _takeaway = s['enable_takeaway'] == '1';
      _delivery = s['enable_delivery'] == '1';
      _pw.text = s['paper_width'] ?? '80';
      _ph.text = s['paper_height'] ?? '0';
      _qr1l.text = s['qr1_label'] ?? '';
      _qr2l.text = s['qr2_label'] ?? '';
      _qr2d.text = s['qr2_data'] ?? '';
      _printQr = s['print_qr'] != '0';
      _img1 = s['qr1_image'] ?? '';
      _img2 = s['qr2_image'] ?? '';
      _freq = s['backup_freq'] ?? 'off';
      _pmode = s['printer_mode'] ?? 'system';
      _pmac = s['printer_bt_mac'] ?? '';
      _pname = s['printer_bt_name'] ?? '';
      _pip.text = s['printer_ip'] ?? '';
      _pcols.text = s['thermal_cols'] ?? '';
      for (final k in _tKeys) {
        _t[k] = s[k] ?? kDefaultSettings[k] ?? '';
      }
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, tr(_ur, 'Shop name cannot be empty.', 'دکان کا نام خالی نہیں ہو سکتا۔'),
          error: true);
      return;
    }
    if (!_dineIn && !_takeaway && !_delivery) {
      toast(
          context,
          tr(_ur, 'Keep at least one order type switched on.',
              'کم از کم ایک آرڈر قسم آن رکھیں۔'),
          error: true);
      return;
    }
    if (_t['pay_cash'] == '0' && _t['pay_online'] == '0' && _t['pay_udhar'] == '0') {
      toast(context,
          tr(_ur, 'Keep at least one payment option on.',
              'کم از کم ایک ادائیگی کا طریقہ آن رکھیں۔'),
          error: true);
      return;
    }
    await DatabaseHelper.instance.setSettings({
      'shop_name': _name.text.trim(),
      'shop_address': _address.text.trim(),
      'shop_phone': _phone.text.trim(),
      'payment_account_info': _account.text.trim(),
      'enable_dine_in': _dineIn ? '1' : '0',
      'enable_takeaway': _takeaway ? '1' : '0',
      'enable_delivery': _delivery ? '1' : '0',
      'paper_width': _pw.text.trim().isEmpty ? '80' : _pw.text.trim(),
      'paper_height': _ph.text.trim().isEmpty ? '0' : _ph.text.trim(),
      'print_qr': _printQr ? '1' : '0',
      'qr1_image': _img1,
      'qr2_image': _img2,
      'backup_freq': _freq,
      ..._printerMap(),
      'qr1_label': _qr1l.text.trim(),
      'qr2_label': _qr2l.text.trim(),
      'qr2_data': _qr2d.text.trim(),
    });
    if (!mounted) return;
    toast(context, tr(_ur, 'Settings saved', 'ترتیبات محفوظ ہو گئیں'));
  }

  Future<void> _pickQr(int slot) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final src = res?.files.single.path;
    if (src == null) return;
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    final dest = File(p.join(base.path,
        'qr_${slot}_${DateTime.now().millisecondsSinceEpoch}${p.extension(src)}'));
    await File(src).copy(dest.path);
    if (!mounted) return;
    setState(() {
      if (slot == 1) {
        _img1 = dest.path;
      } else {
        _img2 = dest.path;
      }
    });
  }

  Widget _qrImageRow(int slot) {
    final path = slot == 1 ? _img1 : _img2;
    final has = path.isNotEmpty && File(path).existsSync();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          has
              ? Image.file(File(path), width: 56, height: 56)
              : const Icon(Icons.qr_code_2, size: 44),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickQr(slot),
                  icon: const Icon(Icons.upload, size: 18),
                  label: Text(has
                      ? tr(_ur, 'Change QR image', 'QR تصویر بدلیں')
                      : tr(_ur, 'Upload QR image', 'QR تصویر اپ لوڈ کریں')),
                ),
                if (has)
                  TextButton(
                    onPressed: () => setState(() {
                      if (slot == 1) {
                        _img1 = '';
                      } else {
                        _img2 = '';
                      }
                    }),
                    child: Text(tr(_ur, 'Remove', 'ہٹائیں')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _printerMap() => {
        'printer_mode': _pmode,
        'printer_bt_mac': _pmac,
        'printer_bt_name': _pname,
        'printer_ip': _pip.text.trim(),
        'thermal_cols': _pcols.text.trim(),
        ..._t,
      };

  Future<void> _choosePrinter() async {
    try {
      await ThermalPrinter.ensureBluetoothPermission();
      final list = await PrintBluetoothThermal.pairedBluetooths;
      if (!mounted) return;
      if (list.isEmpty) {
        toast(context,
            'No paired printers. Pair it first in Android Bluetooth settings (PIN 0000 or 1234).',
            error: true);
        return;
      }
      final pick = await showDialog<BluetoothInfo>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(tr(_ur, 'Choose printer', 'پرنٹر منتخب کریں')),
          children: [
            for (final d in list)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, d),
                child: Text('${d.name}\n${d.macAdress}'),
              ),
          ],
        ),
      );
      if (pick == null) return;
      setState(() {
        _pname = pick.name;
        _pmac = pick.macAdress;
      });
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Widget _tSwitch(String k, String label) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: _t[k] == '1',
        onChanged: (v) => setState(() => _t[k] = v ? '1' : '0'),
      );

  Widget _tField(String k, String label, {bool number = true}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          key: ValueKey('tf_$k'),
          initialValue: _t[k],
          keyboardType: number ? TextInputType.number : TextInputType.text,
          onChanged: (v) => _t[k] = v,
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true),
        ),
      );

  Future<void> _chooseWinPrinter() async {
    try {
      final list = await ThermalPrinter.windowsPrinters();
      if (!mounted) return;
      if (list.isEmpty) {
        toast(context, 'No printers found. Install the printer in Windows first.',
            error: true);
        return;
      }
      final pick = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(tr(_ur, 'Choose printer', 'پرنٹر منتخب کریں')),
          children: [
            for (final n in list)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, n), child: Text(n)),
          ],
        ),
      );
      if (pick != null) setState(() => _t['printer_win_name'] = pick);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _testPrint() async {
    try {
      final s = await DatabaseHelper.instance.getSettings();
      s.addAll(_printerMap());
      s['paper_width'] = _pw.text.trim().isEmpty ? '80' : _pw.text.trim();
      await ThermalPrinter.test(s);
    } catch (e) {
      if (mounted) toast(context, 'Test print failed: $e', error: true);
    }
  }

  Future<void> _backup() async {
    try {
      final f = await BackupService.backupNow();
      if (!mounted) return;
      toast(context, '${tr(_ur, 'Backup saved', 'بیک اپ محفوظ ہو گیا')}: ${f.path}');
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e', error: true);
    }
  }

  Future<void> _shareBackup() async {
    try {
      final src = await DatabaseHelper.instance.databaseFileForCopy();
      final tmp = await getTemporaryDirectory();
      final copy = await src
          .copy(p.join(tmp.path, 'samosa_pos_backup_${fileStamp()}.db'));
      await Share.shareXFiles([XFile(copy.path)],
          text: 'Samosa POS database backup');
    } catch (e) {
      if (mounted) toast(context, 'Share failed: $e', error: true);
    }
  }

  Future<void> _partBackup(bool menu) async {
    try {
      final f = menu
          ? await BackupService.exportMenuStock()
          : await BackupService.exportTransactions();
      if (!mounted) return;
      toast(context, '${tr(_ur, 'Backup saved', 'بیک اپ محفوظ ہو گیا')}: ${f.path}');
      if (!isDesktop) await Share.shareXFiles([XFile(f.path)]);
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e', error: true);
    }
  }

  Future<void> _partRestore(bool menu) async {
    final res = await FilePicker.platform.pickFiles();
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    try {
      final data =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final tables = menu ? ['menu', 'inventory', 'recipes'] : ['sales'];
      for (final t in tables) {
        if (data[t] is! List) {
          throw Exception(menu
              ? 'Not a menu and stock backup file'
              : 'Not a transactions backup file');
        }
      }
      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: tr(_ur, 'Restore backup?', 'بیک اپ بحال کریں؟'),
        message: menu
            ? tr(_ur, 'Current menu, stock and recipes will be replaced.',
                'موجودہ مینو، اسٹاک اور ریسیپیز بدل دی جائیں گی۔')
            : tr(_ur, 'All current bills will be replaced.',
                'موجودہ تمام بل بدل دیے جائیں گے۔'),
        yes: tr(_ur, 'Restore', 'بحال کریں'),
        no: tr(_ur, 'Cancel', 'منسوخ'),
        danger: true,
      );
      if (!ok) return;
      await DatabaseHelper.instance.restoreTables(data, tables);
      if (mounted) toast(context, tr(_ur, 'Backup restored', 'بیک اپ بحال ہو گیا'));
    } catch (e) {
      if (mounted) toast(context, 'Restore failed: $e', error: true);
    }
  }

  Future<void> _restore() async {
    final res = await FilePicker.platform.pickFiles();
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final head = await File(path).openRead(0, 15).expand((b) => b).toList();
    if (String.fromCharCodes(head) != 'SQLite format 3') {
      if (mounted) toast(context, 'That file is not a Samosa POS backup.', error: true);
      return;
    }
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: tr(_ur, 'Restore backup?', 'بیک اپ بحال کریں؟'),
      message: tr(
          _ur,
          'All current data will be replaced by the selected backup.',
          'موجودہ تمام ڈیٹا منتخب بیک اپ سے بدل دیا جائے گا۔'),
      yes: tr(_ur, 'Restore', 'بحال کریں'),
      no: tr(_ur, 'Cancel', 'منسوخ'),
      danger: true,
    );
    if (!ok) return;
    try {
      await DatabaseHelper.instance.restoreFrom(path);
      await _load();
      if (mounted) toast(context, tr(_ur, 'Backup restored', 'بیک اپ بحال ہو گیا'));
    } catch (e) {
      if (mounted) toast(context, 'Restore failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr(_ur, 'Shop profile', 'دکان کی معلومات'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: tr(_ur, 'Shop name', 'دکان کا نام'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                  labelText: tr(_ur, 'Address', 'پتہ'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: tr(_ur, 'Phone number', 'فون نمبر'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _account,
              decoration: InputDecoration(
                  labelText: tr(_ur, 'EasyPaisa / JazzCash account info',
                      'ایزی پیسہ / جاز کیش اکاؤنٹ کی تفصیل'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text(tr(_ur, 'Order types', 'آرڈر کی اقسام'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SwitchListTile(
              title: Text(tr(_ur, 'Dine-In', 'ڈائن ان')),
              value: _dineIn,
              onChanged: (v) => setState(() => _dineIn = v),
            ),
            SwitchListTile(
              title: Text(tr(_ur, 'Takeaway', 'ٹیک اوے')),
              value: _takeaway,
              onChanged: (v) => setState(() => _takeaway = v),
            ),
            SwitchListTile(
              title: Text(tr(_ur, 'Delivery', 'ڈیلیوری')),
              value: _delivery,
              onChanged: (v) => setState(() => _delivery = v),
            ),
            const SizedBox(height: 16),
            Text(tr(_ur, 'Receipt size and QR codes', 'رسید کا سائز اور QR کوڈ'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final t in _presets)
                  ActionChip(
                    label: Text(t.$1),
                    onPressed: () => setState(() {
                      _pw.text = t.$2;
                      _ph.text = t.$3;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pw,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: InputDecoration(
                        labelText: tr(_ur, 'Width (mm)', 'چوڑائی (mm)'),
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ph,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: InputDecoration(
                        labelText:
                            tr(_ur, 'Height (mm, 0 = auto)', 'اونچائی (mm، 0 = آٹو)'),
                        border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(_ur, 'Print payment QR codes on receipt',
                  'رسید پر ادائیگی کے QR کوڈ چھاپیں')),
              value: _printQr,
              onChanged: (v) => setState(() => _printQr = v),
            ),
            TextField(
              controller: _qr1l,
              decoration: InputDecoration(
                  labelText: tr(_ur, 'QR 1 name (account is the field above)',
                      'QR 1 کا نام (اکاؤنٹ اوپر والے خانے میں)'),
                  border: const OutlineInputBorder()),
            ),
            _qrImageRow(1),
            const SizedBox(height: 10),
            TextField(
              controller: _qr2l,
              decoration: InputDecoration(
                  labelText: tr(_ur, 'QR 2 name (e.g. EasyPaisa)',
                      'QR 2 کا نام (مثلاً ایزی پیسہ)'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _qr2d,
              decoration: InputDecoration(
                  labelText: tr(_ur, 'QR 2 account / payment text',
                      'QR 2 اکاؤنٹ / ادائیگی کی تفصیل'),
                  border: const OutlineInputBorder()),
            ),
            _qrImageRow(2),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  backgroundColor: Colors.green.shade700),
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(tr(_ur, 'Save settings', 'ترتیبات محفوظ کریں')),
            ),
            const SizedBox(height: 10),
            const Divider(height: 32),
            Text(tr(_ur, 'Layout and options', 'لے آؤٹ اور آپشنز'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            _tSwitch('enable_tables',
                tr(_ur, 'Enable tables and hold orders', 'ٹیبلز اور آرڈر ہولڈ فعال کریں')),
            _tSwitch('pay_cash', tr(_ur, 'Accept Cash', 'نقد قبول کریں')),
            _tSwitch('pay_online', tr(_ur, 'Accept Online', 'آن لائن قبول کریں')),
            _tSwitch('pay_udhar', tr(_ur, 'Accept Udhar (credit)', 'ادھار قبول کریں')),
            Row(
              children: [
                Expanded(child: Text(tr(_ur, 'Menu layout style', 'مینو لے آؤٹ'))),
                DropdownButton<String>(
                  value: _t['menu_layout'] ?? 'grid',
                  items: [
                    DropdownMenuItem(
                        value: 'grid', child: Text(tr(_ur, 'Grid', 'گرڈ'))),
                    DropdownMenuItem(
                        value: 'compact',
                        child: Text(tr(_ur, 'Compact grid', 'چھوٹا گرڈ'))),
                    DropdownMenuItem(
                        value: 'list', child: Text(tr(_ur, 'List', 'فہرست'))),
                  ],
                  onChanged: (v) => setState(() => _t['menu_layout'] = v ?? 'grid'),
                ),
              ],
            ),
            Text(
              tr(_ur,
                  'To rearrange menu, stock, tables or POS items: tap the lock icon at the top, drag items, then lock again.',
                  'ترتیب بدلنے کے لیے اوپر لاک آئیکن دبائیں، آئٹم گھسیٹیں، پھر دوبارہ لاک کریں۔'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 32),
            Text(tr(_ur, 'Printer', 'پرنٹر'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: ((_pmode == 'bluetooth' && !Platform.isAndroid) ||
                      (_pmode == 'windows' && !Platform.isWindows))
                  ? 'system'
                  : _pmode,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                    value: 'system',
                    child: Text(tr(_ur, 'System print dialog', 'سسٹم پرنٹ ڈائیلاگ'))),
                if (Platform.isAndroid)
                  DropdownMenuItem(
                      value: 'bluetooth',
                      child: Text(tr(_ur, 'Bluetooth thermal printer (recommended)',
                          'بلوٹوتھ تھرمل پرنٹر (تجویز کردہ)'))),
                if (Platform.isWindows)
                  DropdownMenuItem(
                      value: 'windows',
                      child: Text(tr(_ur, 'Windows installed printer (USB / shared)',
                          'ونڈوز انسٹال شدہ پرنٹر (USB)'))),
                DropdownMenuItem(
                    value: 'network',
                    child: Text(tr(_ur, 'Wi-Fi / LAN thermal printer',
                        'وائی فائی / LAN تھرمل پرنٹر'))),
              ],
              onChanged: (v) => setState(() => _pmode = v ?? 'system'),
            ),
            if (_pmode == 'bluetooth')
              Row(
                children: [
                  Expanded(
                      child: Text(_pname.isEmpty
                          ? tr(_ur, 'No printer chosen', 'کوئی پرنٹر منتخب نہیں')
                          : '$_pname ($_pmac)')),
                  OutlinedButton(
                    onPressed: _choosePrinter,
                    child: Text(tr(_ur, 'Choose', 'منتخب کریں')),
                  ),
                ],
              ),
            if (_pmode == 'network')
              TextField(
                controller: _pip,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: tr(_ur, 'Printer IP address (port 9100)',
                        'پرنٹر کا IP ایڈریس (پورٹ 9100)'),
                    border: const OutlineInputBorder()),
              ),
            if (_pmode == 'windows')
              Row(
                children: [
                  Expanded(
                      child: Text((_t['printer_win_name'] ?? '').isEmpty
                          ? tr(_ur, 'No printer chosen', 'کوئی پرنٹر منتخب نہیں')
                          : _t['printer_win_name']!)),
                  OutlinedButton(
                    onPressed: _chooseWinPrinter,
                    child: Text(tr(_ur, 'Choose', 'منتخب کریں')),
                  ),
                ],
              ),
            if (_pmode != 'system') ...[
              const SizedBox(height: 12),
              Text(tr(_ur, 'Thermal page size', 'تھرمل پیج سائز'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: [
                  for (final o in const [
                    ('2 inch (58mm)', '58', '32'),
                    ('3 inch (80mm)', '80', '48'),
                    ('4 inch (112mm)', '112', '64'),
                  ])
                    ChoiceChip(
                      label: Text(o.$1),
                      selected: _pw.text == o.$2 && _pcols.text == o.$3,
                      onSelected: (_) => setState(() {
                        _pw.text = o.$2;
                        _pcols.text = o.$3;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pcols,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: tr(_ur, 'Custom: characters per line',
                        'کسٹم: ہر لائن میں حروف'),
                    border: const OutlineInputBorder(),
                    isDense: true),
              ),
              _tSwitch('t_bold', tr(_ur, 'Use text styling (bold)', 'بولڈ ٹیکسٹ')),
              _tSwitch('t_cut', tr(_ur, 'Auto cut paper after printing', 'پرنٹ کے بعد آٹو کٹ')),
              _tSwitch('t_drawer', tr(_ur, 'Open cash drawer after printing', 'پرنٹ کے بعد کیش دراز کھولیں')),
              _tSwitch('t_qty', tr(_ur, 'Print total item quantity', 'کل آئٹم تعداد پرنٹ کریں')),
              _tSwitch('t_hname', tr(_ur, 'Print shop name', 'دکان کا نام پرنٹ کریں')),
              _tSwitch('t_haddr', tr(_ur, 'Print shop address', 'دکان کا پتہ پرنٹ کریں')),
              _tSwitch('t_hphone', tr(_ur, 'Print shop phone', 'دکان کا فون پرنٹ کریں')),
              _tField('t_feed', tr(_ur, 'Extra lines at the end', 'آخر میں اضافی لائنیں')),
              _tField('t_copies', tr(_ur, 'Number of copies', 'کاپیوں کی تعداد')),
              _tField('t_footer', tr(_ur, 'Footer message', 'فوٹر پیغام'), number: false),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _testPrint,
                icon: const Icon(Icons.print),
                label: Text(tr(_ur, 'Test print', 'ٹیسٹ پرنٹ')),
              ),
            ],
            const Divider(height: 32),
            Text(tr(_ur, 'Backup', 'بیک اپ'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                    child: Text(tr(_ur, 'Automatic backup', 'خودکار بیک اپ'))),
                DropdownButton<String>(
                  value: _freq,
                  items: [
                    DropdownMenuItem(
                        value: 'off', child: Text(tr(_ur, 'Off', 'بند'))),
                    DropdownMenuItem(
                        value: 'daily',
                        child: Text(tr(_ur, 'Daily', 'روزانہ'))),
                    DropdownMenuItem(
                        value: 'weekly',
                        child: Text(tr(_ur, 'Weekly', 'ہفتہ وار'))),
                    DropdownMenuItem(
                        value: 'monthly',
                        child: Text(tr(_ur, 'Monthly', 'ماہانہ'))),
                  ],
                  onChanged: (v) => setState(() => _freq = v ?? 'off'),
                ),
              ],
            ),
            Text(
              tr(_ur, 'Press "Save settings" to apply. The app must be opened for a scheduled backup to run; the last 10 automatic backups are kept.',
                  'لاگو کرنے کے لیے "ترتیبات محفوظ کریں" دبائیں۔ شیڈول بیک اپ کے لیے ایپ کھلنی چاہیے؛ آخری 10 خودکار بیک اپ رکھے جاتے ہیں۔'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _backup,
                  icon: const Icon(Icons.backup),
                  label: Text(tr(_ur, 'Backup now', 'ابھی بیک اپ لیں')),
                ),
                if (!isDesktop)
                  OutlinedButton.icon(
                    onPressed: _shareBackup,
                    icon: const Icon(Icons.share),
                    label: Text(tr(_ur, 'Share backup', 'بیک اپ شیئر کریں')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _partBackup(true),
                  icon: const Icon(Icons.restaurant_menu),
                  label: Text(tr(_ur, 'Backup menu and stock', 'مینو اور اسٹاک بیک اپ')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _partRestore(true),
                  icon: const Icon(Icons.settings_backup_restore),
                  label: Text(tr(_ur, 'Restore menu and stock', 'مینو اور اسٹاک بحال کریں')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _partBackup(false),
                  icon: const Icon(Icons.receipt_long),
                  label: Text(tr(_ur, 'Backup transactions', 'ٹرانزیکشنز بیک اپ')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _partRestore(false),
                  icon: const Icon(Icons.settings_backup_restore),
                  label: Text(tr(_ur, 'Restore transactions', 'ٹرانزیکشنز بحال کریں')),
                ),
                OutlinedButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.restore),
                  label: Text(tr(_ur, 'Restore from file', 'فائل سے بحال کریں')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
