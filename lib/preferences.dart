import 'package:shared_preferences/shared_preferences.dart';

import 'domain/lesson.dart';

class PreferencesStore {
  late final SharedPreferencesAsync _storage = SharedPreferencesAsync();

  Future<Magazine?> loadMagazine() async {
    final saved = await _storage.getString('selected_magazine');
    for (final magazine in Magazine.values) {
      if (magazine.name == saved) return magazine;
    }
    return null;
  }

  Future<void> saveMagazine(Magazine magazine) =>
      _storage.setString('selected_magazine', magazine.name);
}
