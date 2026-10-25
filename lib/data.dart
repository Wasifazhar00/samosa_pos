import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/* ============================================================================
 * SMALL HELPERS
 * ========================================================================= */

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Returns the Urdu text when [ur] is true, otherwise the English text.
String tr(bool ur, String en, String urdu) => ur ? urdu : en;

String money(num v) => 'Rs. ${v.toStringAsFixed(0)}';

String qtyText(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime d) {
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '${_two(h12)}:${_two(d.minute)} $ampm';
}

String fmtDateTime(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)}/${d.year} ${fmtTime(d)}';

String fileStamp() {
  final t = DateTime.now();
  return '${t.year}${_two(t.month)}${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}';
}

String todayKey() => DateTime.now().toIso8601String().substring(0, 10);

const List<String> kDineTables = [
  'Table 1',
  'Table 2',
  'Table 3',
  'Table 4',
  'Table 5',
];

/// Held orders that do not belong to a table are grouped under this name.
const String kNoTable = 'Takeaway';

const Map<String, String> kDefaultSettings = {
  'shop_name': 'Bismillah Shereen Mehal Samosa POS',
  'shop_address': 'Main Chowk, Layyah',
  'shop_phone': '+92 300 1234567',
  'payment_account_info': 'EasyPaisa/JazzCash: 03001234567',
  'enable_dine_in': '1',
  'enable_takeaway': '1',
  'enable_delivery': '1',
  'language': 'en',
  'paper_width': '80',
  'paper_height': '0',
  'print_qr': '1',
  'qr1_label': 'JazzCash / EasyPaisa',
  'qr2_label': '',
  'qr2_data': '',
  'qr1_image': '',
  'qr2_image': '',
  'backup_freq': 'off',
  'printer_mode': 'system',
  'printer_bt_mac': '',
  'printer_bt_name': '',
  'printer_ip': '',
  'thermal_cols': '',
  'backup_keep': '10',
};

const Map<String, IconData> kIconChoices = {
  'fastfood': Icons.fastfood,
  'chicken': Icons.lunch_dining,
  'potato': Icons.bakery_dining,
  'plate': Icons.restaurant,
  'double': Icons.room_service,
  'drink': Icons.local_drink,
};

/* ============================================================================
 * DATA MODELS
 * ========================================================================= */

class MenuItem {
  const MenuItem({
    this.id,
    required this.nameEn,
    required this.nameUr,
    required this.price,
    required this.iconKey,
    this.inStock = true,
  });

  final int? id;
  final String nameEn;
  final String nameUr;
  final double price;
  final String iconKey;
  final bool inStock;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name_en': nameEn,
        'name_ur': nameUr,
        'price': price,
        'icon_key': iconKey,
        'in_stock': inStock ? 1 : 0,
      };

  factory MenuItem.fromMap(Map<String, dynamic> map) => MenuItem(
        id: map['id'] as int?,
        nameEn: (map['name_en'] as String?) ?? '',
        nameUr: (map['name_ur'] as String?) ?? '',
        price: ((map['price'] as num?) ?? 0).toDouble(),
        iconKey: (map['icon_key'] as String?) ?? 'fastfood',
        inStock: map['in_stock'] == 1,
      );

  MenuItem copyWith({bool? inStock}) => MenuItem(
        id: id,
        nameEn: nameEn,
        nameUr: nameUr,
        price: price,
        iconKey: iconKey,
        inStock: inStock ?? this.inStock,
      );

  IconData get iconData => kIconChoices[iconKey] ?? Icons.fastfood;
}

class InventoryItem {
  const InventoryItem({
    this.id,
    required this.name,
    required this.stockQty,
    required this.unit,
    this.lowLevel = 10,
  });

  final int? id;
  final String name;
  final double stockQty;
  final String unit;
  final double lowLevel;

  bool get isLow => stockQty <= lowLevel;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'stock_qty': stockQty,
        'unit': unit,
        'low_level': lowLevel,
      };

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        id: map['id'] as int?,
        name: (map['name'] as String?) ?? '',
        stockQty: ((map['stock_qty'] as num?) ?? 0).toDouble(),
        unit: (map['unit'] as String?) ?? 'pcs',
        lowLevel: ((map['low_level'] as num?) ?? 10).toDouble(),
      );
}

class CartItem {
  CartItem({required this.item, this.quantity = 1, double? customPrice})
      : customPrice = customPrice ?? item.price;

  final MenuItem item;
  int quantity;
  double customPrice;

  double get total => customPrice * quantity;

  CartItem copy() =>
      CartItem(item: item, quantity: quantity, customPrice: customPrice);
}

class SaleLine {
  const SaleLine({
    this.menuId,
    required this.name,
    required this.qty,
    required this.price,
  });

  final int? menuId;
  final String name;
  final int qty;
  final double price;

  double get total => price * qty;

  Map<String, dynamic> toJson() => {'m': menuId, 'n': name, 'q': qty, 'p': price};

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
        menuId: j['m'] as int?,
        name: (j['n'] as String?) ?? '',
        qty: ((j['q'] as num?) ?? 1).toInt(),
        price: ((j['p'] as num?) ?? 0).toDouble(),
      );
}

class SaleRecord {
  const SaleRecord({
    this.id,
    required this.billNo,
    required this.tokenNo,
    required this.orderType,
    required this.itemsSummary,
    this.customerMobile,
    this.customerAddress,
    required this.totalAmount,
    this.discount = 0,
    required this.paymentMethod,
    required this.isPaid,
    required this.createdAt,
    this.itemsJson,
  });

  final int? id;
  final String billNo;
  final String tokenNo;
  final String orderType;
  final String itemsSummary;
  final String? customerMobile;
  final String? customerAddress;
  final double totalAmount;
  final double discount;
  final String paymentMethod;
  final bool isPaid;
  final String createdAt;
  final String? itemsJson;

  DateTime? get createdTime => DateTime.tryParse(createdAt);

  List<SaleLine> get lines {
    final raw = itemsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SaleLine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  factory SaleRecord.fromMap(Map<String, dynamic> map) => SaleRecord(
        id: map['id'] as int?,
        billNo: (map['bill_no'] as String?) ?? '',
        tokenNo: (map['token_no'] as String?) ?? '',
        orderType: (map['order_type'] as String?) ?? 'Dine-In',
        itemsSummary: (map['items_summary'] as String?) ?? '',
        customerMobile: map['customer_mobile'] as String?,
        customerAddress: map['customer_address'] as String?,
        totalAmount: ((map['total_amount'] as num?) ?? 0).toDouble(),
        discount: ((map['discount'] as num?) ?? 0).toDouble(),
        paymentMethod: (map['payment_method'] as String?) ?? 'Cash',
        isPaid: map['is_paid'] == 1,
        createdAt: (map['created_at'] as String?) ?? '',
        itemsJson: map['items_json'] as String?,
      );
}

/* ============================================================================
 * DATABASE HELPER
 * ========================================================================= */

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _dbName = 'bismillah_samosa_pos_v11.db';

  /// Incremented after every write so that all screens can refresh themselves.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<Database>? _opening;

  Future<Database> get database {
    return _opening ??= _open().catchError((Object e, StackTrace st) {
      _opening = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  void _changed() => revision.value++;

  Future<String> getDatabasePath() async {
    final String dir;
    if (isDesktop) {
      final d = await getApplicationSupportDirectory();
      await d.create(recursive: true);
      dir = d.path;
    } else {
      dir = await getDatabasesPath();
    }
    return p.join(dir, _dbName);
  }

  Future<Database> _open() async {
    final path = await getDatabasePath();
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE menu (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_en TEXT,
        name_ur TEXT,
        price REAL,
        icon_key TEXT,
        in_stock INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        stock_qty REAL,
        unit TEXT,
        low_level REAL DEFAULT 10
      )
    ''');
    await db.execute('''
      CREATE TABLE recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_id INTEGER,
        inventory_id INTEGER,
        required_qty REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bill_no TEXT,
        token_no TEXT,
        order_type TEXT,
        items_summary TEXT,
        customer_mobile TEXT,
        customer_address TEXT,
        total_amount REAL,
        discount REAL DEFAULT 0,
        payment_method TEXT,
        is_paid INTEGER,
        created_at TEXT,
        items_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await _seed(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE sales ADD COLUMN discount REAL DEFAULT 0');
      await db.execute('ALTER TABLE sales ADD COLUMN items_json TEXT');
      await db.execute(
          'ALTER TABLE inventory ADD COLUMN low_level REAL DEFAULT 10');
    }
  }

  Future<void> _seed(Database db) async {
    Future<int> inv(String name, double qty, String unit, double low) =>
        db.insert('inventory', {
          'name': name,
          'stock_qty': qty,
          'unit': unit,
          'low_level': low,
        });

    final pati = await inv('Samosa Pati', 500, 'pcs', 100);
    final chana = await inv('Chana', 100, 'servings', 20);
    final chatni = await inv('Chatni', 100, 'servings', 20);
    final chicken = await inv('Chicken Filling', 50, 'kg', 5);
    final aloo = await inv('Aloo Filling', 50, 'kg', 5);
    final coke = await inv('Cold Drink (Coke)', 40, 'bottles', 10);

    Future<int> menu(String en, String ur, double price, String icon) =>
        db.insert('menu', {
          'name_en': en,
          'name_ur': ur,
          'price': price,
          'icon_key': icon,
          'in_stock': 1,
        });

    final m1 = await menu('Chicken Samosa', 'چکن سموسہ', 50, 'chicken');
    final m2 = await menu('Aloo Samosa', 'آلو سموسہ', 30, 'potato');
    final m3 = await menu('Single Plate', 'سنگل پلیٹ', 80, 'plate');
    final m4 = await menu('Double Plate', 'ڈبل پلیٹ', 140, 'double');
    final m5 = await menu('Cold Drink', 'کولڈ ڈرنک', 70, 'drink');

    Future<void> rec(int menuId, int invId, double qty) => db.insert(
          'recipes',
          {'menu_id': menuId, 'inventory_id': invId, 'required_qty': qty},
        ).then((_) {});

    await rec(m1, pati, 1);
    await rec(m1, chicken, 0.05);
    await rec(m2, pati, 1);
    await rec(m2, aloo, 0.05);
    await rec(m3, pati, 1);
    await rec(m3, chana, 1);
    await rec(m3, chatni, 1);
    await rec(m4, pati, 2);
    await rec(m4, chana, 1);
    await rec(m4, chatni, 1);
    await rec(m5, coke, 1);
  }

  /* ---------------------------- MENU ---------------------------------- */

  Future<List<MenuItem>> getMenuItems() async {
    final db = await database;
    final rows = await db.query('menu', orderBy: 'id');
    return rows.map(MenuItem.fromMap).toList();
  }

  Future<void> addMenuItem(MenuItem item) async {
    final db = await database;
    await db.insert('menu', item.toMap());
    _changed();
  }

  Future<void> updateMenuItem(MenuItem item) async {
    final db = await database;
    await db.update('menu', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
    _changed();
  }

  Future<void> deleteMenuItem(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('recipes', where: 'menu_id = ?', whereArgs: [id]);
      await txn.delete('menu', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  /* ---------------------------- RECIPES -------------------------------- */

  /// inventory id -> quantity used for one unit sold.
  Future<Map<int, double>> getRecipe(int menuId) async {
    final db = await database;
    final rows =
        await db.query('recipes', where: 'menu_id = ?', whereArgs: [menuId]);
    return {
      for (final r in rows)
        r['inventory_id'] as int: ((r['required_qty'] as num?) ?? 0).toDouble(),
    };
  }

  Future<void> saveRecipe(int menuId, Map<int, double> recipe) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('recipes', where: 'menu_id = ?', whereArgs: [menuId]);
      for (final e in recipe.entries) {
        await txn.insert('recipes', {
          'menu_id': menuId,
          'inventory_id': e.key,
          'required_qty': e.value,
        });
      }
    });
    _changed();
  }

  /* --------------------------- INVENTORY ------------------------------- */

  Future<List<InventoryItem>> getInventory() async {
    final db = await database;
    final rows = await db.query('inventory', orderBy: 'name COLLATE NOCASE');
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<void> addInventoryItem(InventoryItem item) async {
    final db = await database;
    await db.insert('inventory', item.toMap());
    _changed();
  }

  Future<void> updateInventoryItem(InventoryItem item) async {
    final db = await database;
    await db.update('inventory', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
    _changed();
  }

  Future<void> deleteInventoryItem(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('recipes', where: 'inventory_id = ?', whereArgs: [id]);
      await txn.delete('inventory', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  Future<void> adjustStock(int id, double delta) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE inventory SET stock_qty = MAX(stock_qty + ?, 0) WHERE id = ?',
        [delta, id]);
    _changed();
  }

  Future<void> setStock(int id, double qty) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE inventory SET stock_qty = ? WHERE id = ?', [qty, id]);
    _changed();
  }

  /// Returns a human readable line for every material that is not enough
  /// to cover [items]. An empty list means stock is sufficient.
  Future<List<String>> checkStock(List<CartItem> items) async {
    final db = await database;
    final need = <int, double>{};
    for (final c in items) {
      final recipes = await db
          .query('recipes', where: 'menu_id = ?', whereArgs: [c.item.id]);
      for (final r in recipes) {
        final invId = r['inventory_id'] as int;
        final req = ((r['required_qty'] as num?) ?? 0).toDouble();
        need[invId] = (need[invId] ?? 0) + req * c.quantity;
      }
    }
    final problems = <String>[];
    for (final e in need.entries) {
      final rows =
          await db.query('inventory', where: 'id = ?', whereArgs: [e.key]);
      if (rows.isEmpty) continue;
      final inv = InventoryItem.fromMap(rows.first);
      if (inv.stockQty + 1e-9 < e.value) {
        problems.add(
            '${inv.name}: need ${qtyText(e.value)}, have ${qtyText(inv.stockQty)} ${inv.unit}');
      }
    }
    return problems;
  }

  /* ------------------------------ SALES -------------------------------- */

  Future<List<SaleRecord>> getAllSales() async {
    final db = await database;
    final rows = await db.query('sales', orderBy: 'id DESC');
    return rows.map(SaleRecord.fromMap).toList();
  }

  Future<void> updatePaymentStatus(int saleId, bool isPaid,
      {required String method}) async {
    final db = await database;
    await db.update(
      'sales',
      {'is_paid': isPaid ? 1 : 0, 'payment_method': method},
      where: 'id = ?',
      whereArgs: [saleId],
    );
    _changed();
  }

  Future<void> updateSaleDetails(
      int saleId, double newAmount, String mobile, String address) async {
    final db = await database;
    await db.update(
      'sales',
      {
        'total_amount': newAmount,
        'customer_mobile': mobile.isNotEmpty ? mobile : null,
        'customer_address': address.isNotEmpty ? address : null,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
    _changed();
  }

  Future<void> deleteSale(SaleRecord sale, {required bool restoreStock}) async {
    final db = await database;
    await db.transaction((txn) async {
      if (restoreStock) {
        for (final line in sale.lines) {
          final menuId = line.menuId;
          if (menuId == null) continue;
          final recipes = await txn
              .query('recipes', where: 'menu_id = ?', whereArgs: [menuId]);
          for (final r in recipes) {
            final back =
                ((r['required_qty'] as num?) ?? 0).toDouble() * line.qty;
            await txn.rawUpdate(
                'UPDATE inventory SET stock_qty = stock_qty + ? WHERE id = ?',
                [back, r['inventory_id']]);
          }
        }
      }
      await txn.delete('sales', where: 'id = ?', whereArgs: [sale.id]);
    });
    _changed();
  }

  /// Saves a sale, deducts stock and returns the stored record
  /// (with its unique bill number and daily token number).
  Future<SaleRecord> processSale({
    required List<CartItem> items,
    required double discount,
    required String paymentMethod,
    required String orderType,
    required bool isPaid,
    String? mobile,
    String? address,
  }) async {
    final db = await database;

    final sale = await db.transaction<SaleRecord>((txn) async {
      double subtotal = 0;
      final names = <String>[];
      final lines = <SaleLine>[];

      for (final c in items) {
        subtotal += c.total;
        names.add('${c.quantity}x ${c.item.nameEn}');
        lines.add(SaleLine(
          menuId: c.item.id,
          name: c.item.nameEn,
          qty: c.quantity,
          price: c.customPrice,
        ));

        final recipes = await txn
            .query('recipes', where: 'menu_id = ?', whereArgs: [c.item.id]);
        for (final r in recipes) {
          final used = ((r['required_qty'] as num?) ?? 0).toDouble() * c.quantity;
          await txn.rawUpdate(
              'UPDATE inventory SET stock_qty = MAX(stock_qty - ?, 0) WHERE id = ?',
              [used, r['inventory_id']]);
        }
      }

      final disc = discount < 0 ? 0.0 : (discount > subtotal ? subtotal : discount);
      final total = subtotal - disc;

      // Daily token counter (#001, #002, ...).
      final today = todayKey();
      final rows = await txn.query('settings',
          where: 'key IN (?, ?)', whereArgs: ['token_date', 'token_counter']);
      final m = <String, String>{
        for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
      };
      var counter =
          m['token_date'] == today ? (int.tryParse(m['token_counter'] ?? '') ?? 0) : 0;
      counter++;
      await txn.insert('settings', {'key': 'token_date', 'value': today},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {'key': 'token_counter', 'value': '$counter'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      final tokenNo = '#${counter.toString().padLeft(3, '0')}';

      final createdAt = DateTime.now().toIso8601String();
      final itemsJson = jsonEncode(lines.map((l) => l.toJson()).toList());

      final id = await txn.insert('sales', {
        'bill_no': '',
        'token_no': tokenNo,
        'order_type': orderType,
        'items_summary': names.join(', '),
        'customer_mobile': (mobile == null || mobile.isEmpty) ? null : mobile,
        'customer_address': (address == null || address.isEmpty) ? null : address,
        'total_amount': total,
        'discount': disc,
        'payment_method': paymentMethod,
        'is_paid': isPaid ? 1 : 0,
        'created_at': createdAt,
        'items_json': itemsJson,
      });
      final billNo = 'INV-${id.toString().padLeft(5, '0')}';
      await txn.update('sales', {'bill_no': billNo},
          where: 'id = ?', whereArgs: [id]);

      return SaleRecord(
        id: id,
        billNo: billNo,
        tokenNo: tokenNo,
        orderType: orderType,
        itemsSummary: names.join(', '),
        customerMobile: (mobile == null || mobile.isEmpty) ? null : mobile,
        customerAddress: (address == null || address.isEmpty) ? null : address,
        totalAmount: total,
        discount: disc,
        paymentMethod: paymentMethod,
        isPaid: isPaid,
        createdAt: createdAt,
        itemsJson: itemsJson,
      );
    });

    _changed();
    return sale;
  }

  Future<String?> getHeldJson() async {
    final db = await database;
    final rows = await db
        .query('settings', where: 'key = ?', whereArgs: ['held_orders']);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> saveHeldJson(String json) async {
    final db = await database;
    await db.insert('settings', {'key': 'held_orders', 'value': json},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Flushes pending writes and returns the database file, ready to copy.
  Future<File> databaseFileForCopy() async {
    final db = await database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    return File(await getDatabasePath());
  }

  Future<void> restoreFrom(String sourcePath) async {
    final path = await getDatabasePath();
    final pending = _opening;
    if (pending != null) {
      final db = await pending;
      await db.close();
    }
    _opening = null;
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(sourcePath).copy(path);
    _changed();
  }

  /* ---------------------------- SETTINGS -------------------------------- */

  Future<Map<String, String>> getSettings() async {
    final db = await database;
    final rows = await db.query('settings');
    final out = Map<String, String>.from(kDefaultSettings);
    for (final r in rows) {
      final v = r['value'];
      if (v is String) out[r['key'] as String] = v;
    }
    return out;
  }

  Future<void> setSettings(Map<String, String> values) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final e in values.entries) {
        await txn.insert('settings', {'key': e.key, 'value': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _changed();
  }

  Future<void> setSetting(String key, String value) =>
      setSettings({key: value});
}
