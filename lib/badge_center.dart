import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BadgeCenter {
  BadgeCenter._();
  static final BadgeCenter instance = BadgeCenter._();

  final ValueNotifier<int> _pending = ValueNotifier<int>(0);
  int? _userId;

  String? _baseUrl; // memóriában is tároljuk

  /// Olvasható listenable az ikonokhoz (ValueListenableBuilder-hez)
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
    final uid = _userId;
    if (uid == null || uid <= 0) {
      _pending.value = 0;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // sorrend: explicit setBaseUrl → prefs → fallback
      final baseUrl = _baseUrl ??
          prefs.getString('api_base') ??
          'https://bluemedusa.store/filmapp';

      // 1) Próbáljuk a COUNT endpointot (gyors)
      final countUrl = Uri.parse('$baseUrl/friends_incoming_count.php?user_id=$uid');
      final countRes = await http.get(countUrl);

      bool handled = false;
      if (countRes.statusCode == 200) {
        final data = json.decode(countRes.body);
        final raw = data is Map ? data['count'] : null;
        final count = raw is String ? int.tryParse(raw) : (raw is int ? raw : null);
        if (count != null) {
          _pending.value = count.clamp(0, 999);
          handled = true;
        }
      }

      if (handled) return;

      // 2) Fallback: lista endpoint
      final listUrl = Uri.parse('$baseUrl/friend_requests_incoming.php?user_id=$uid');
      final listRes = await http.get(listUrl);
      if (listRes.statusCode == 200) {
        final data = json.decode(listRes.body);
        if (data is Map && data['success'] == true) {
          final list = (data['requests'] as List?) ?? const [];
          _pending.value = list.length.clamp(0, 999);
        }
      }
    } catch (_) {
      // némán – ne zavarja a UI-t
    }
  }
}
