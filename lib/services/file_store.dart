import 'package:shared_preferences/shared_preferences.dart';

class FileStore {
  static const _key = 'recent_datasets';

  static Future<List<String>> getRecentDatasets() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> addDataset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(name);
    list.insert(0, name);
    while (list.length > 20) {
      list.removeLast();
    }
    await prefs.setStringList(_key, list);
  }

  static Future<void> removeDataset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(name);
    await prefs.setStringList(_key, list);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
