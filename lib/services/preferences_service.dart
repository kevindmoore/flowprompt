import 'package:lumberdash/lumberdash.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowprompt/models/recent_file.dart';
import 'package:flowprompt/signals/prompter_signals.dart';

const _keyScrollSpeed = 'scroll_speed';
const _keyFontSize = 'font_size';
const _keyFontFamily = 'font_family';
const _keyDarkMode = 'dark_mode';
const _keyRecentFiles = 'recent_files';

class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  /// Load all persisted settings into signals
  void loadSettings() {
    scrollSpeed.value = _prefs.getDouble(_keyScrollSpeed) ?? 30.0;
    fontSize.value = _prefs.getDouble(_keyFontSize) ?? 32.0;
    fontFamily.value = _prefs.getString(_keyFontFamily) ?? 'Roboto Slab';
    isDarkMode.value = _prefs.getBool(_keyDarkMode) ?? true;

    final recentJson = _prefs.getString(_keyRecentFiles);
    if (recentJson != null && recentJson.isNotEmpty) {
      try {
        recentFiles.value = RecentFile.decodeList(recentJson);
      } catch (e) {
        logWarning('Failed to decode recent files: $e');
        recentFiles.value = [];
      }
    }

  }

  void saveScrollSpeed(double speed) {
    scrollSpeed.value = speed;
    _prefs.setDouble(_keyScrollSpeed, speed);
  }

  void saveFontSize(double size) {
    fontSize.value = size;
    _prefs.setDouble(_keyFontSize, size);
  }

  void saveFontFamily(String family) {
    fontFamily.value = family;
    _prefs.setString(_keyFontFamily, family);
  }

  void saveDarkMode(bool dark) {
    isDarkMode.value = dark;
    _prefs.setBool(_keyDarkMode, dark);
  }

  void addRecentFile(RecentFile file) {
    final current = List<RecentFile>.from(recentFiles.value);
    // Remove if already exists (will re-add at top)
    current.removeWhere((f) => f == file);
    // Add at the beginning
    current.insert(0, file);
    // Keep only the last 20
    if (current.length > 20) {
      current.removeRange(20, current.length);
    }
    recentFiles.value = current;
    _prefs.setString(_keyRecentFiles, RecentFile.encodeList(current));
  }

  void clearRecentFiles() {
    recentFiles.value = [];
    _prefs.remove(_keyRecentFiles);
  }
}
