// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ⬇️ hagyd így, ha a pubspec name: film_match_app
// ha más a csomagnév, ÍRD ÁT pontosra!
import 'package:film_match_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Ha az app induláskor Preferences-t olvas, ne dőljön el testben:
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('FilmApp smoke test - felépül hiba nélkül', (WidgetTester tester) async {
    // Ha a FilmApp konstruktora NEM const, vedd ki a const-ot!
    await tester.pumpWidget(const FilmApp());
    await tester.pump(); // engedünk egy frame-et

    expect(find.byType(FilmApp), findsOneWidget);
  });
}
