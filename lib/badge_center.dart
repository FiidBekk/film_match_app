import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BadgeCenter {
  BadgeCenter._();
  static final BadgeCenter instance = BadgeCenter._();

  final ValueNotifier<int> _pending = ValueNotifier<int>(0);
  int? _userId;

  String? _baseUrl; // <-- itt tároljuk memóriában is

  /// Olvasható listenable az ikonokhoz
  ValueListenable<int> get pendingListenable => _pending;

  /// Opcionális: API base URL beállítása és elmentése (pl. main.dart-ból)
  Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_base', url);
    } catch (_) {/* némán */}
  }

  /// Beállítjuk (vagy töröljük) a felhasználót
  void setUser(int? userId) {
    _userId = userId;
    if (userId == null) {
      _pending.value = 0;
    } else {
      refresh(); // induláskor frissítünk
    }
  }

  /// Kívülről közvetlenül állítható a szám (pl. FriendsPage lekérése után)
  void setPending(int value) {
    if (value != _pending.value) {
      _pending.value = value;
    }
  }

  /// Szerverről frissíti a bejövő kérések számát (ha van user)
  Future<void> refresh() async {
    if (_userId == null || _userId! <= 0) {
      _pending.value = 0;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // sorrend: explicit setBaseUrl → prefs → fallback
      final baseUrl = _baseUrl ??
          prefs.getString('api_base') ??
          'https://bluemedusa.store/filmapp';

      final url = Uri.parse('$baseUrl/friend_requests_incoming.php?user_id=${_userId}');
      final r = await http.get(url);
      if (r.statusCode != 200) return;

      final data = json.decode(r.body);
      if (data is Map && data['success'] == true) {
        final list = (data['requests'] as List?) ?? const [];
        _pending.value = list.length;
      }
    } catch (_) {
      // némán – ne zavarja a UI-t
    }
  }
}
