import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data.dart';

class BackupService {
  static Future<Directory> backupDir() async {
    Directory base;
    if (Platform.isAndroid) {
      base = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory(p.join(base.path, 'SamosaPOS', 'Backups'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> backupNow({String prefix = 'manual'}) async {
    final src = await DatabaseHelper.instance.databaseFileForCopy();
    final dir = await backupDir();
    final out = await src
        .copy(p.join(dir.path, 'samosa_pos_${prefix}_${fileStamp()}.db'));
    await exportMenuStock(prefix: prefix);
    await exportTransactions(prefix: prefix);
    final s = await DatabaseHelper.instance.getSettings();
    await _prune(dir, int.tryParse(s['backup_keep'] ?? '') ?? 10);
    await DatabaseHelper.instance
        .setSetting('last_backup', DateTime.now().toIso8601String());
    return out;
  }

  static Future<File> _json(String name, List<String> tables) async {
    final dir = await backupDir();
    final data = await DatabaseHelper.instance.dumpTables(tables);
    final f = File(p.join(dir.path, 'samosa_pos_${name}_${fileStamp()}.json'));
    await f.writeAsString(jsonEncode({'version': 1, ...data}));
    return f;
  }

  static Future<File> exportMenuStock({String prefix = 'manual'}) =>
      _json('${prefix}_menu_stock', ['menu', 'inventory', 'recipes']);

  static Future<File> exportTransactions({String prefix = 'manual'}) =>
      _json('${prefix}_transactions', ['sales']);

  static Future<void> _prune(Directory dir, int keep) async {
    for (final prefix in [
      'samosa_pos_auto_menu_stock_',
      'samosa_pos_auto_transactions_',
      'samosa_pos_auto_2',
    ]) {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith(prefix))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(keep)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Runs an automatic backup when the chosen schedule says one is due.
  static Future<bool> runIfDue() async {
    try {
      final s = await DatabaseHelper.instance.getSettings();
      final freq = s['backup_freq'] ?? 'off';
      if (freq == 'off') return false;
      final last = DateTime.tryParse(s['last_backup'] ?? '');
      final now = DateTime.now();
      var due = last == null;
      if (last != null) {
        final today = DateTime(now.year, now.month, now.day);
        final lastDay = DateTime(last.year, last.month, last.day);
        if (freq == 'daily') due = today.isAfter(lastDay);
        if (freq == 'weekly') due = today.difference(lastDay).inDays >= 7;
        if (freq == 'monthly') {
          due = now.year != last.year || now.month != last.month;
        }
      }
      if (!due) return false;
      await backupNow(prefix: 'auto');
      return true;
    } catch (_) {
      return false;
    }
  }
}
