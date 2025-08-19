import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import 'account_page.dart';
import 'SwipePage.dart'; // ha kisbetűs: 'swipe_page.dart';
import 'qr_scan_page.dart';

// globális badge és egységes navbar ikon
import 'badge_center.dart';
import 'nav_utils.dart';

const _baseUrl = "https://bluemedusa.store/filmapp";

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  // adatok
  final List<Friend> _friends = [];
  final List<_IncomingRequest> _incoming = [];

  // állapotok
  int _navIndex = 0;
  String _myHandle = '@me';
  int? _myUserId;
  bool _loadingFriends = true;
  bool _loadingIncoming = true;

  int get _pendingCount => _incoming.length;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadMyIdentity();
    await _ensureUserIdFromServerIfMissing();

    // ha már tudjuk a usert, szóljunk a BadgeCenternek
    if (_myUserId != null && _myUserId! > 0) {
      BadgeCenter.instance.setUser(_myUserId);
    }

    await Future.wait([
      _fetchFriends(),
      _fetchIncomingRequests(),
    ]);
  }

  Future<void> _loadMyIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('user_id');
    final email = prefs.getString('email');
    String handle = '@me';
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) handle = '@$local';
    }
    if (!mounted) return;
    setState(() => _myHandle = handle);
  }

  // Ha hiányzik a user_id (régi login miatt), próbáljuk beolvasni a szerverről
  Future<void> _ensureUserIdFromServerIfMissing() async {
    if (_myUserId != null && _myUserId! > 0) return;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email');
    final password = prefs.getString('password');
    if (email == null || password == null) return;

    try {
      final url = Uri.parse("$_baseUrl/login.php");
      final r = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({"email": email, "password": password}),
      );
      if (r.statusCode != 200) return;
      final data = json.decode(r.body);
      if (data["success"] == true) {
        final uid = int.tryParse(data["user_id"].toString());
        if (uid != null && uid > 0) {
          await prefs.setInt("user_id", uid);
          if (!mounted) return;
          setState(() => _myUserId = uid);

          // user azonosítót átadjuk a BadgeCenternek is
          BadgeCenter.instance.setUser(uid);
        }
      }
    } catch (_) {/* némán */}
  }

  // ---- Barátlista ----
  Future<void> _fetchFriends() async {
    if (_myUserId == null || _myUserId! <= 0) {
      setState(() => _loadingFriends = false);
      return;
    }
    try {
      final url = Uri.parse("$_baseUrl/friends_list.php?user_id=$_myUserId");
      final r = await http.get(url);
      if (!mounted) return;
      if (r.statusCode != 200) {
        setState(() => _loadingFriends = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Szerver hiba (${r.statusCode}) a listázásnál')),
        );
        return;
      }
      final data = json.decode(r.body);
      if (data is Map && data['success'] == true) {
        final List<Friend> loaded = [];
        final list = (data['friends'] ?? []) as List;
        for (final f in list) {
          loaded.add(Friend(
            id: (f['id'] as num).toInt(),
            name: (f['name'] ?? '').toString().isEmpty
                ? (f['email'] ?? '').toString()
                : f['name'].toString(),
            handle: (f['handle'] ?? (f['username'] != null ? '@${f['username']}' : '')).toString(),
            email: (f['email'] ?? '').toString(),
          ));
        }
        setState(() {
          _friends
            ..clear()
            ..addAll(loaded);
          _loadingFriends = false;
        });
      } else {
        setState(() => _loadingFriends = false);
        final msg = (data['message'] ?? 'Sikertelen listázás').toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingFriends = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hálózati hiba: $e')));
    }
  }

  // ---- Beérkező kérelmek ----
  Future<void> _fetchIncomingRequests() async {
    if (_myUserId == null || _myUserId! <= 0) {
      setState(() {
        _loadingIncoming = false;
        _incoming.clear();
      });
      // globális badge 0-ra
      BadgeCenter.instance.setPending(0);
      return;
    }
    try {
      final url = Uri.parse("$_baseUrl/friend_requests_incoming.php?user_id=$_myUserId");
      final r = await http.get(url);
      if (!mounted) return;
      if (r.statusCode != 200) {
        setState(() => _loadingIncoming = false);
        // nem biztos, de óvatosságból ne ragadjon fent régi szám
        BadgeCenter.instance.setPending(_incoming.length);
        return;
      }
      final data = json.decode(r.body);
      if (data is Map && data["success"] == true) {
        final List<_IncomingRequest> list = [];
        for (final x in (data["requests"] as List)) {
          list.add(_IncomingRequest(
            id: (x["id"] as num).toInt(),
            fromUserId: (x["from_user_id"] as num).toInt(),
            name: (x["name"] ?? '').toString(),
            handle: (x["username"] != null && (x["username"] as String).isNotEmpty)
                ? '@${x["username"]}'
                : '',
            email: (x["email"] ?? '').toString(),
          ));
        }
        setState(() {
          _incoming
            ..clear()
            ..addAll(list);
          _loadingIncoming = false;
        });

        // 🔴 frissítsük a globális badge-et
        BadgeCenter.instance.setPending(_incoming.length);
      } else {
        setState(() {
          _loadingIncoming = false;
          _incoming.clear();
        });
        BadgeCenter.instance.setPending(0);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingIncoming = false;
        // hiba esetén ne nullázzuk erővel; de azért frissítsünk a jelenlegi állapotra
      });
      BadgeCenter.instance.setPending(_incoming.length);
    }
  }

  Future<void> _respondRequest(int reqId, bool accept) async {
    if (_myUserId == null || _myUserId! <= 0) return;
    final url = Uri.parse("$_baseUrl/friend_request_respond.php");
    try {
      final r = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "request_id": reqId,
          "action": accept ? "ACCEPT" : "DECLINE",
          "user_id": _myUserId
        }),
      );
      if (!mounted) return;
      if (r.statusCode != 200) return;
      final data = json.decode(r.body);
      if (data is Map && data["success"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? 'Elfogadva' : 'Elutasítva')),
        );
        await _fetchIncomingRequests(); // ez frissíti a globális badget is
        if (accept) await _fetchFriends();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((data["message"] ?? "Hiba").toString())),
        );
      }
    } catch (_) {/* némán */}
  }

  // ---- Kérelem küldése @névvel / username / email ----
  Future<bool> _sendFriendRequestByHandle(String handle) async {
    if (_myUserId == null || _myUserId! <= 0) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kérés küldéséhez be kell jelentkezni.')),
      );
      return false;
    }

    final url = Uri.parse("$_baseUrl/friends_add.php");
    try {
      final payload = {
        "user_id": _myUserId,
        "friend_handle": handle,
      };
      final r = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      // debug
      // ignore: avoid_print
      print("REQ STATUS: ${r.statusCode}");
      // ignore: avoid_print
      print("REQ BODY: ${r.body}");

      Map<String, dynamic> data = {};
      try { data = json.decode(r.body); } catch (_) {}

      if (r.statusCode != 200) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Szerver hiba (${r.statusCode})")),
        );
        return false;
      }

      if ((data["success"] ?? false) == true) {
        final status = (data["status"] ?? "").toString();
        switch (status) {
          case "request_sent":
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Kérelem elküldve ✅")),
              );
            }
            // bejövő frissítés; ha egy másik eszközről azonnal visszajön, a badge reagáljon
            _fetchIncomingRequests();
            return true;
          case "request_pending":
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Már van függő kérelem ⏳")),
              );
            }
            return true;
          case "already_friends":
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Már barátok vagytok 🤝")),
              );
            }
            return true;
          default:
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text((data["message"] ?? "Ismeretlen válasz").toString())),
              );
            }
            return false;
        }
      } else {
        final msg = (data["message"] ?? "Kérés sikertelen").toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hálózati hiba: $e')));
      return false;
    }
  }

  // ---- UI akciók ----
  Future<void> _openSearch() async {
    final result = await showSearch<Friend?>(
      context: context,
      delegate: _FriendsSearchDelegate(_friends),
    );
    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kiválasztva: ${result.name}')),
      );
    }
  }

  // QR: a másik fél @handle/username/email-jét tartalmazza → kérelmet küldünk neki
  Future<void> _openQrScanner() async {
    final raw = await Navigator.push<String?>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const QrScanPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (!mounted || raw == null || raw.trim().isEmpty) return;

    try {
      final map = json.decode(raw);
      final handle0 = (map['handle'] as String?)?.trim();
      if (handle0 == null || handle0.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR nem tartalmaz nevet.')));
        return;
      }
      // elfogadjuk @-al vagy anélkül
      final handle = handle0.startsWith('@') ? handle0 : handle0;
      final ok = await _sendFriendRequestByHandle(handle);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kérés elküldve.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Érvénytelen QR: $e')));
    }
  }

  // Manuális kérelem küldése
  Future<void> _addFriendManually() async {
    final nameCtrl = TextEditingController();
    final okPressed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Barát kérés küldése'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Felhasználónév / e-mail',
            hintText: 'pl. pisti vagy pisti@email.com',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Küldés')),
        ],
      ),
    );
    if (okPressed != true || !mounted) return;

    final raw = nameCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adj meg nevet vagy e-mailt.')));
      return;
    }
    final ok = await _sendFriendRequestByHandle(raw);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kérés elküldve.')));
    }
  }

  // --- Saját QR megosztása ---
  Future<void> _shareMyQr(String qrPayload) async {
    try {
      final painter = QrPainter(
        data: qrPayload,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      );
      final byteData = await painter.toImageData(1024, format: ui.ImageByteFormat.png);
      if (byteData == null) throw 'QR render failed';
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/my_profile_qr.png');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Add me on Film Match: $_myHandle');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nem sikerült megosztani a QR-t: $e')));
    }
  }

  void _openQrFullscreen(String qrPayload) {
    Navigator.of(context).push(
      PageRouteBuilder(
        barrierColor: Colors.black,
        opaque: false,
        pageBuilder: (_, __, ___) => _QrFullscreen(payload: qrPayload, handle: _myHandle),
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );
  }

  Widget _badgeDot({double size = 10}) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      );

  // -------- build (TabBar + TabBarView) --------
  @override
  Widget build(BuildContext context) {
    final qrPayload = jsonEncode({
      'type': 'profile',
      'handle': _myHandle,
      'name': _myHandle.startsWith('@') ? _myHandle.substring(1) : _myHandle,
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Ismerősök'),
          centerTitle: true,
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              tooltip: 'Kérés küldése',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: _addFriendManually,
            ),
            IconButton(
              tooltip: 'Keresés',
              icon: const Icon(Icons.search),
              onPressed: _openSearch,
            ),
            IconButton(
              tooltip: 'QR olvasó',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _openQrScanner,
            ),
          ],
          bottom: TabBar(
            indicatorColor: Colors.purpleAccent,
            tabs: [
              const Tab(text: 'Barátok'),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Kérések'),
                    if (_pendingCount > 0) ...[
                      const SizedBox(width: 6),
                      _badgeDot(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        body: TabBarView(
          children: [
            // --------- 1. FÜL: BARÁTOK ---------
            Column(
              children: [
                // Saját QR kártya
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _openQrFullscreen(qrPayload),
                          child: Hero(
                            tag: 'my-profile-qr',
                            child: Container(
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.all(8),
                              child: QrImageView(
                                data: qrPayload,
                                version: QrVersions.auto,
                                size: 92,
                                gapless: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Saját profil QR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(_myHandle, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                              const SizedBox(height: 8),
                              const Text(
                                'Mutasd ezt a kódot, hogy gyorsan meghívót küldhessenek.',
                                style: TextStyle(fontSize: 12, color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Megosztás',
                          icon: const Icon(Icons.share),
                          onPressed: () => _shareMyQr(qrPayload),
                        ),
                      ],
                    ),
                  ),
                ),

                // Barátlista
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchFriends,
                    child: _loadingFriends
                        ? const Center(child: CircularProgressIndicator())
                        : _friends.isEmpty
                            ? const Center(child: Text('Még nincsenek barátok.', style: TextStyle(color: Colors.white70)))
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _friends.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                                itemBuilder: (context, i) {
                                  final f = _friends[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.purple.shade700,
                                      child: Text((f.name.isNotEmpty ? f.name[0] : '?').toUpperCase()),
                                    ),
                                    title: Text(f.name),
                                    subtitle: Text(
                                      f.handle.isNotEmpty ? f.handle : (f.email.isNotEmpty ? f.email : 'ID: ${f.id}'),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () {/* profil/chat később */},
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),

            // --------- 2. FÜL: KÉRÉSEK ---------
            RefreshIndicator(
              onRefresh: _fetchIncomingRequests,
              child: _buildRequestsList(),
            ),
          ],
        ),

        // egységes navbar – az első ikon legyen a globális badgelős
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            canvasColor: Colors.black,
          ),
          child: BottomNavigationBar(
            backgroundColor: Colors.black,
            type: BottomNavigationBarType.fixed,
            currentIndex: _navIndex,
            enableFeedback: false,
            selectedItemColor: Colors.purpleAccent,
            unselectedItemColor: Colors.white60,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            iconSize: 24,
            onTap: (i) {
              setState(() => _navIndex = i);
              if (i == 2) {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const SwipePage(initialIndex: 2),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
              if (i == 4) {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const AccountPage(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
            items: [
  BottomNavigationBarItem(icon: friendsIconWithGlobalBadge(), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.chat), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.extension), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
],
          ),
        ),
      ),
    );
  }

  // --- Kérések lista UI ---
  Widget _buildRequestsList() {
    if (_loadingIncoming) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_incoming.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nincs beérkező kérés.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _incoming.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final r = _incoming[i];
        final title = r.name.isNotEmpty ? r.name : (r.handle.isNotEmpty ? r.handle : r.email);
        final subtitle = r.handle.isNotEmpty ? r.handle : (r.email.isNotEmpty ? r.email : 'ID: ${r.fromUserId}');

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _respondRequest(r.id, true),
                      icon: const Icon(Icons.check),
                      label: const Text('Elfogad'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _respondRequest(r.id, false),
                      icon: const Icon(Icons.close),
                      label: const Text('Elutasít'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- modellek ---
class Friend {
  final int id;
  final String name;
  final String handle;
  final String email;
  const Friend({required this.id, required this.name, required this.handle, required this.email});
}

class _IncomingRequest {
  final int id;
  final int fromUserId;
  final String name;
  final String handle;
  final String email;
  _IncomingRequest({
    required this.id,
    required this.fromUserId,
    required this.name,
    required this.handle,
    required this.email,
  });
}

// --- kereső ---
class _FriendsSearchDelegate extends SearchDelegate<Friend?> {
  final List<Friend> all;
  _FriendsSearchDelegate(this.all);

  @override
  String? get searchFieldLabel => 'Ismerős keresése...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none, hintStyle: TextStyle(color: Colors.white70)),
      textTheme: base.textTheme.apply(bodyColor: Colors.white),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) =>
      [if (query.isNotEmpty) IconButton(tooltip: 'Törlés', icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(tooltip: 'Vissza', icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildList(_filter(query));
  @override
  Widget buildSuggestions(BuildContext context) => _buildList(_filter(query));

  List<Friend> _filter(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return all;
    return all.where((f) =>
        f.name.toLowerCase().contains(t) ||
        f.email.toLowerCase().contains(t) ||
        f.handle.toLowerCase().contains(t) ||
        f.id.toString() == t).toList();
  }

  Widget _buildList(List<Friend> list) {
    if (list.isEmpty) {
      return const Center(child: Text('Nincs találat.', style: TextStyle(color: Colors.white70)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
      itemBuilder: (context, i) {
        final f = list[i];
        return ListTile(
          leading: CircleAvatar(child: Text(f.name.isNotEmpty ? f.name[0].toUpperCase() : '?')),
          title: Text(f.name),
          subtitle: Text(f.handle.isNotEmpty ? f.handle : (f.email.isNotEmpty ? f.email : 'ID: ${f.id}')),
          onTap: () => close(context, f),
        );
      },
    );
  }
}

// --- Teljes képernyős QR nézet ---
class _QrFullscreen extends StatelessWidget {
  final String payload;
  final String handle;
  const _QrFullscreen({required this.payload, required this.handle});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final qrSize = size.shortestSide * 0.9;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(handle)),
      body: Center(
        child: Hero(
          tag: 'my-profile-qr',
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: QrImageView(data: payload, version: QrVersions.auto, size: qrSize, gapless: true),
            ),
          ),
        ),
      ),
    );
  }
}
