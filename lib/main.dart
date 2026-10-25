import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data.dart';
import 'manage.dart';
import 'pos.dart';
import 'ui_helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const SamosaPosApp());
}

class SamosaPosApp extends StatefulWidget {
  const SamosaPosApp({super.key});

  @override
  State<SamosaPosApp> createState() => _SamosaPosAppState();
}

class _SamosaPosAppState extends State<SamosaPosApp> {
  bool _isUrdu = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final s = await DatabaseHelper.instance.getSettings();
      if (!mounted) return;
      setState(() {
        _isUrdu = s['language'] == 'ur';
      });
    } catch (_) {
      // Keep English if the database is not ready.
    }
  }

  Future<void> _toggleLanguage() async {
    setState(() {
      _isUrdu = !_isUrdu;
    });
    await DatabaseHelper.instance.setSetting('language', _isUrdu ? 'ur' : 'en');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Samosa POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          secondary: Colors.green.shade700,
        ),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      builder: (context, child) => Directionality(
        textDirection: _isUrdu ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: MainPosScreen(isUrdu: _isUrdu, onToggleLanguage: _toggleLanguage),
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.en, this.ur);
  final IconData icon;
  final String en;
  final String ur;
}

const List<_Dest> _destinations = [
  _Dest(Icons.point_of_sale, 'POS', 'کاؤنٹر'),
  _Dest(Icons.table_restaurant, 'Tables', 'ٹیبلز'),
  _Dest(Icons.restaurant_menu, 'Menu', 'مینو'),
  _Dest(Icons.inventory_2, 'Stock', 'اسٹاک'),
  _Dest(Icons.receipt_long, 'Bills', 'بلز'),
  _Dest(Icons.settings, 'Settings', 'ترتیبات'),
];

class MainPosScreen extends StatefulWidget {
  const MainPosScreen({
    super.key,
    required this.isUrdu,
    required this.onToggleLanguage,
  });

  final bool isUrdu;
  final VoidCallback onToggleLanguage;

  @override
  State<MainPosScreen> createState() => _MainPosScreenState();
}

class _MainPosScreenState extends State<MainPosScreen> {
  final CartController _cart = CartController();
  final List<OrderToken> _held = [];
  final GlobalKey _bodyKey = GlobalKey();
  int _index = 0;
  String _shopName = kDefaultSettings['shop_name']!;

  bool get _ur => widget.isUrdu;

  @override
  void initState() {
    super.initState();
    _loadShopName();
    DatabaseHelper.revision.addListener(_loadShopName);
  }

  @override
  void dispose() {
    DatabaseHelper.revision.removeListener(_loadShopName);
    _cart.dispose();
    super.dispose();
  }

  Future<void> _loadShopName() async {
    try {
      final s = await DatabaseHelper.instance.getSettings();
      if (!mounted) return;
      setState(() {
        _shopName = s['shop_name'] ?? _shopName;
      });
    } catch (_) {
      // Ignore: the title keeps its previous value.
    }
  }

  String _nextLabel(String tableName) {
    final used =
        _held.where((t) => t.tableName == tableName).map((t) => t.label).toSet();
    for (var i = 0; i < 26; i++) {
      final l = String.fromCharCode(65 + i);
      if (!used.contains(l)) return l;
    }
    return '${used.length + 1}';
  }

  void _holdCurrent() {
    if (_cart.isEmpty) return;
    final tableName = _cart.table ?? kNoTable;
    final token = _cart.toToken(_nextLabel(tableName));
    setState(() {
      _held.add(token);
    });
    _cart.clear();
    toast(
        context,
        tr(_ur, 'Order held: $tableName ${token.label}',
            'آرڈر روک لیا گیا: $tableName ${token.label}'));
  }

  Future<bool> _confirmReplaceCart() async {
    if (_cart.isEmpty) return true;
    return confirmDialog(
      context,
      title: tr(_ur, 'Replace current cart?', 'موجودہ کارٹ بدلیں؟'),
      message: tr(
          _ur,
          'The items in the current cart will be discarded. Use Hold to keep them.',
          'موجودہ کارٹ کے آئٹم ختم ہو جائیں گے۔ محفوظ رکھنے کے لیے "روکیں" استعمال کریں۔'),
      yes: tr(_ur, 'Replace', 'بدلیں'),
      no: tr(_ur, 'Cancel', 'منسوخ'),
      danger: true,
    );
  }

  Future<void> _newOrder(String tableName) async {
    if (!await _confirmReplaceCart() || !mounted) return;
    _cart.clear();
    if (tableName == kNoTable) {
      _cart.setOrderType('Takeaway');
    } else {
      _cart.setOrderType('Dine-In');
      _cart.setTable(tableName);
    }
    setState(() {
      _index = 0;
    });
  }

  Future<void> _openHeld(OrderToken order) async {
    if (!await _confirmReplaceCart() || !mounted) return;
    setState(() {
      _held.remove(order);
      _index = 0;
    });
    _cart.loadToken(order);
  }

  Future<void> _discardHeld(OrderToken order) async {
    final ok = await confirmDialog(
      context,
      title: tr(_ur, 'Discard held order?', 'روکا ہوا آرڈر ختم کریں؟'),
      message:
          '${order.tableName} ${order.label}: ${money(order.total)}',
      yes: tr(_ur, 'Discard', 'ختم کریں'),
      no: tr(_ur, 'Keep', 'رہنے دیں'),
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _held.remove(order);
    });
  }

  Widget _tablesIcon() => Badge(
        isLabelVisible: _held.isNotEmpty,
        label: Text('${_held.length}'),
        child: const Icon(Icons.table_restaurant),
      );

  Widget _iconFor(int i) =>
      i == 1 ? _tablesIcon() : Icon(_destinations[i].icon);

  @override
  Widget build(BuildContext context) {
    final body = KeyedSubtree(
      key: _bodyKey,
      child: IndexedStack(
        index: _index,
        children: [
          PosTerminalView(isUrdu: _ur, cart: _cart, onHold: _holdCurrent),
          TablesView(
            isUrdu: _ur,
            orders: _held,
            onNewOrder: _newOrder,
            onOpen: _openHeld,
            onDiscard: _discardHeld,
          ),
          MenuManagementView(isUrdu: _ur),
          InventoryView(isUrdu: _ur),
          ReportsAndSalesHistoryView(isUrdu: _ur),
          SettingsView(isUrdu: _ur),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            title: Text(
              _shopName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: widget.onToggleLanguage,
                icon: const Icon(Icons.translate),
                label: Text(_ur ? 'English' : 'اردو'),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (var i = 0; i < _destinations.length; i++)
                          NavigationRailDestination(
                            icon: _iconFor(i),
                            label: Text(
                                tr(_ur, _destinations[i].en, _destinations[i].ur)),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    for (var i = 0; i < _destinations.length; i++)
                      NavigationDestination(
                        icon: _iconFor(i),
                        label: tr(_ur, _destinations[i].en, _destinations[i].ur),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
