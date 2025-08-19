import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'swipe_page.dart';
import 'badge_center.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // API base URL (ha változik, itt elég átírni)
  BadgeCenter.instance.setBaseUrl("https://bluemedusa.store/filmapp");

  runApp(const FilmApp());
}

/// Egyszerű oldalváltás animáció nélkül (globális használatra)
class NoTransitionsBuilder extends PageTransitionsBuilder {
  const NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child; // nincs animáció
  }
}

/// Globális session helper
class Session {
  static const _kEmail = 'email';
  static const _kPassword = 'password';
  static const _kUserId = 'user_id';
  static const _kName = 'name';

  static Future<void> saveLogin({
    required String email,
    required String password,
    required int userId,
    String? name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // tiszta indulás
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kPassword, password);
    await prefs.setInt(_kUserId, userId);
    if (name != null) await prefs.setString(_kName, name);

    // BadgeCenter-nek jelezzük az aktuális usert (realtime jelzéshez)
    BadgeCenter.instance.setUser(userId);
  }

  static Future<void> logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    BadgeCenter.instance.setUser(null);

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  static Future<Map<String, dynamic>?> getSavedCreds() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_kEmail);
    final password = prefs.getString(_kPassword);
    if (email == null || password == null) return null;
    return {"email": email, "password": password};
  }

  static Future<int?> get userId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kUserId);
  }
}

class FilmApp extends StatelessWidget {
  const FilmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Film Match',
      routes: <String, Widget Function(BuildContext)>{
        "/login": (_) => const LoginPage(),
      },
      // Deprecation-mentes theme
      theme: ThemeData.from(
        colorScheme: const ColorScheme.dark(
          primary: Colors.purple,
          secondary: Colors.purpleAccent,
        ),
        useMaterial3: false,
      ).copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: NoTransitionsBuilder(),
            TargetPlatform.iOS: NoTransitionsBuilder(),
            TargetPlatform.windows: NoTransitionsBuilder(),
            TargetPlatform.linux: NoTransitionsBuilder(),
            TargetPlatform.macOS: NoTransitionsBuilder(),
          },
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: Colors.purple),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.white70),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white38),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.purpleAccent),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.purpleAccent,
          unselectedItemColor: Colors.white60,
          type: BottomNavigationBarType.fixed,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/// SPLASH képernyő – itt dől el hova navigáljunk
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _attemptAutoLogin();
  }

  Future<void> _attemptAutoLogin() async {
    // Kis delay, hogy a splash megvillanjon
    await Future.delayed(const Duration(milliseconds: 250));

    final creds = await Session.getSavedCreds();
    if (!mounted) return;

    if (creds == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
      return;
    }

    // Valódi auto-login a szerver felé, hogy friss useradat legyen
    try {
      final url = Uri.parse("https://bluemedusa.store/filmapp/login.php");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "email": creds["email"],
          "password": creds["password"],
        }),
      );

      final data = json.decode(response.body);
      if (data["success"] == true) {
        final userId = (data["user_id"] is String)
            ? int.tryParse(data["user_id"]) ?? -1
            : (data["user_id"] ?? -1);
        final name = data["name"]; // ha küld a backend

        if (userId == -1) {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
          return;
        }

        await Session.saveLogin(
          email: creds["email"],
          password: creds["password"],
          userId: userId,
          name: name,
        );

        // login után azonnal legyen aktív a badge polling
        BadgeCenter.instance.setUser(userId);

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SwipePage()),
          (route) => false,
        );
      } else {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String message = "";

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => message = "Add meg az emailt és a jelszót.");
      return;
    }

    try {
      final url = Uri.parse("https://bluemedusa.store/filmapp/login.php");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({"email": email, "password": password}),
      );

      final data = json.decode(response.body);
      if (data["success"] == true) {
        final userId = (data["user_id"] is String)
            ? int.tryParse(data["user_id"]) ?? -1
            : (data["user_id"] ?? -1);
        final name = data["name"]; // ha küld

        if (userId == -1) {
          setState(() => message = "Hibás válasz a szervertől.");
          return;
        }

        await Session.saveLogin(
          email: email,
          password: password,
          userId: userId,
          name: name,
        );

        // login után azonnal induljon a badge polling
        BadgeCenter.instance.setUser(userId);

        if (!mounted) return;
        if (name != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Szia, $name! (ID: $userId)")),
          );
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SwipePage()),
          (route) => false,
        );
      } else {
        setState(() => message = data["message"] ?? "Sikertelen bejelentkezés.");
      }
    } catch (e) {
      setState(() => message = "Hálózati hiba: $e");
    }
  }

  void goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: login, child: const Text("Login")),
            ),
            TextButton(
              onPressed: goToRegister,
              child: const Text("Don't have an account? Register"),
            ),
            const SizedBox(height: 16),
            if (message.isNotEmpty)
              Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  String message = "";

  Future<void> register() async {
    try {
      final url = Uri.parse("https://bluemedusa.store/filmapp/register.php");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "email": emailController.text.trim(),
          "password": passwordController.text,
          "name": nameController.text.trim(),
        }),
      );

      final data = json.decode(response.body);
      setState(() {
        message = data["message"] ?? "Registration failed.";
      });

      if (data["success"] == true && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => message = "Hálózati hiba: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Register")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child:
                  ElevatedButton(onPressed: register, child: const Text("Register")),
            ),
            const SizedBox(height: 16),
            if (message.isNotEmpty)
              Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
