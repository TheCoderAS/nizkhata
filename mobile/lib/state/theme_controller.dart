// App theme mode (light/dark/system), persisted — ports the web Appearance
// toggle. Wired into MaterialApp.router in main.dart.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  ThemeController() {
    _load();
  }

  static ThemeMode _parse(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    mode = _parse(p.getString('themeMode'));
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == mode) return;
    mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('themeMode', _encode(m));
  }
}
