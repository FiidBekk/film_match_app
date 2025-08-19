import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'SwipePage.dart';
import 'friends_page.dart';
import 'nav_utils.dart';     // friendsIconWithGlobalBadge(), kAccountIcon
import 'badge_center.dart'; // BadgeCenter.instance.refresh(), setUser(null)

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();                 // minden session adat törlése
    BadgeCenter.instance.setUser(null);  // 🔴 badge leáll / nullázás
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, "/login", (route) => false);
    }
  }

  void _onNavTap(BuildContext context, int index) {
    if (index == 4) return; // már az Accounton vagyunk

    if (index == 0) {
      // Friends külön oldal
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const FriendsPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    // Egyébként vissza SwipePage-re, a megfelelő index-szel
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => SwipePage(initialIndex: index),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => _logout(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text("Logout"),
            ),
            const SizedBox(height: 16),
            // manuális frissítés a pöttyre (globális)
            TextButton.icon(
              onPressed: () => BadgeCenter.instance.refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text("Frissítsd a bejövő kérések számát"),
            ),
          ],
        ),
      ),

      // egységes navbar – Account legyen aktív (index: 4)
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
          currentIndex: 4,
          enableFeedback: false,
          onTap: (index) => _onNavTap(context, index),
          selectedItemColor: Colors.purpleAccent,
          unselectedItemColor: Colors.white60,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          iconSize: 24,
          items: [
  BottomNavigationBarItem(icon: friendsIconWithGlobalBadge(), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.chat), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.extension), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
],
        ),
      ),
    );
  }
}
