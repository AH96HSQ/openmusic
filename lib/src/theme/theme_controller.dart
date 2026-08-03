import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _kModeKey = 'theme_mode';
  static const _kSeedKey = 'theme_seed';

  ThemeMode _mode = ThemeMode.system;
  // Default brand teal color (#006A6A)
  Color _seedColor = const Color(0xFF006A6A);

  ThemeMode get mode => _mode;
  Color get seedColor => _seedColor;

  ThemeController();

  /// Create and load saved settings from SharedPreferences.
  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController();

    final modeIndex = prefs.getInt(_kModeKey);
    if (modeIndex != null &&
        modeIndex >= 0 &&
        modeIndex < ThemeMode.values.length) {
      controller._mode = ThemeMode.values[modeIndex];
    }

    final seed = prefs.getInt(_kSeedKey);
    if (seed != null) controller._seedColor = Color(seed);

    return controller;
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kModeKey, _mode.index);
    await prefs.setInt(_kSeedKey, _seedColor.toARGB32()); // <-- no .value
  }

  void setMode(ThemeMode mode) {
    debugPrint('ThemeController: Changing theme mode from $_mode to $mode');
    _mode = mode;
    notifyListeners();
    _savePrefs();
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    notifyListeners();
    _savePrefs();
  }
}
