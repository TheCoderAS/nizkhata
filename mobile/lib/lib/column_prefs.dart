// Persisted per-table column preferences (which columns are hidden + custom
// widths), keyed by a stable table id. Ports the intent of the web
// useColumnPrefs hook. Backed by shared_preferences.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ColumnPrefs {
  final Set<String> hidden; // hidden column keys
  final Map<String, double> widths; // key -> custom width
  ColumnPrefs(this.hidden, this.widths);

  static Future<ColumnPrefs> load(String tableId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('cols_$tableId');
    if (raw == null) return ColumnPrefs(<String>{}, <String, double>{});
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final hidden = ((m['hidden'] as List?) ?? const []).map((e) => e as String).toSet();
      final widths = <String, double>{};
      (m['widths'] as Map?)?.forEach((k, v) => widths[k as String] = (v as num).toDouble());
      return ColumnPrefs(hidden, widths);
    } catch (_) {
      return ColumnPrefs(<String>{}, <String, double>{});
    }
  }

  Future<void> save(String tableId) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cols_$tableId', jsonEncode({'hidden': hidden.toList(), 'widths': widths}));
  }
}
