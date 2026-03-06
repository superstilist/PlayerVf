import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsModel extends ChangeNotifier {
  static const String _musicPathsKey = 'music_source_paths';
  static const String _cardSizeKey = 'card_size';
  static const String _cardMarginsKey = 'card_margins';
  static const String _cardCountKey = 'card_count';
  static const String _useAutoCardCountKey = 'use_auto_card_count';
  static const String _themeModeKey = 'theme_mode';
  static const String _topMarginKey = 'top_margin';

  List<String> musicSourcePaths = [];
  double cardSize = 140.0;
  double cardMargins = 8.0;
  double topMargin = 60.0;
  int cardCount = 3;
  bool useAutoCardCount = true;
  ThemeMode themeMode = ThemeMode.dark;

  SettingsModel() {
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      musicSourcePaths = prefs.getStringList(_musicPathsKey) ?? [];
      cardSize = prefs.getDouble(_cardSizeKey) ?? 140.0;
      cardMargins = prefs.getDouble(_cardMarginsKey) ?? 8.0;
      topMargin = prefs.getDouble(_topMarginKey) ?? 60.0;
      cardCount = prefs.getInt(_cardCountKey) ?? 3;
      useAutoCardCount = prefs.getBool(_useAutoCardCountKey) ?? true;
      
      final themeIndex = prefs.getInt(_themeModeKey) ?? ThemeMode.dark.index;
      themeMode = ThemeMode.values[themeIndex];
      
      notifyListeners();
    } catch (e) {
      print('Error loading settings: $e');
      musicSourcePaths = [];
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCardSize(double size) async {
    cardSize = size;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCardMargins(double margins) async {
    cardMargins = margins;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setTopMargin(double margin) async {
    topMargin = margin;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCardCount(int count) async {
    cardCount = count;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setUseAutoCardCount(bool useAuto) async {
    useAutoCardCount = useAuto;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> addMusicPath(String path) async {
    if (!musicSourcePaths.contains(path)) {
      musicSourcePaths.add(path);
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> removeMusicPath(String path) async {
    musicSourcePaths.remove(path);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> clearAllPaths() async {
    musicSourcePaths.clear();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_musicPathsKey, musicSourcePaths);
      await prefs.setDouble(_cardSizeKey, cardSize);
      await prefs.setDouble(_cardMarginsKey, cardMargins);
      await prefs.setDouble(_topMarginKey, topMargin);
      await prefs.setInt(_cardCountKey, cardCount);
      await prefs.setBool(_useAutoCardCountKey, useAutoCardCount);
      await prefs.setInt(_themeModeKey, themeMode.index);
    } catch (e) {
      print('Error saving settings: $e');
    }
  }
}
