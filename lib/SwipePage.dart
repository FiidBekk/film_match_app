import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'tmdb_service.dart';
import 'account_page.dart';
import 'friends_page.dart';
import 'nav_utils.dart';
import 'badge_center.dart';


// ⇩⇩⇩ Állítsd a saját API-dhoz
const _baseUrl = "https://bluemedusa.store/filmapp";

class SwipePage extends StatefulWidget {
  const SwipePage({super.key, this.initialIndex = 2}); // 🔹 középen a Home
  final int initialIndex;

  @override
  _SwipePageState createState() => _SwipePageState();
}

class _SwipePageState extends State<SwipePage> with TickerProviderStateMixin {
  List<Movie> movies = [];
  int currentIndex = 0;
  late int _selectedIndex; // a kezdő fül a widget.initialIndex

  Offset position = Offset.zero;
  double angle = 0;
  bool isDragging = false;
  bool showDescriptionPanel = false;
  bool trailerReady = false;

  // --- Friends badge (piros pötty)
  int _incomingCount = 0;

  late AnimationController panelController;
  late Animation<Offset> panelOffset;
  YoutubePlayerController? youtubeController;

  bool get isEmbeddedVideoSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    loadMovies();
    _loadIncomingCount();

    panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    panelOffset = Tween<Offset>(
      begin: const Offset(0, 1),
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(parent: panelController, curve: Curves.easeOut));
  }

  Future<void> loadMovies() async {
    final fetched = await TMDBService().fetchRandomMovies(pageCount: 10);
    if (!mounted) return;
    setState(() {
      movies = fetched;
      currentIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
  BadgeCenter.instance.refresh();
});

  }

  // --- Bejövő friend requestek számának lekérése (badge)
  Future<void> _loadIncomingCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId == null) return;

      // ⇩⇩⇩ Endpoint testreszabás: ha máshogy hívod vagy más a response kulcs, itt írd át
      final url = Uri.parse("$_baseUrl/friends_incoming_count.php?user_id=$userId");
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final count = (data['count'] is String)
            ? int.tryParse(data['count']) ?? 0
            : (data['count'] ?? 0) as int;
        if (!mounted) return;
        setState(() => _incomingCount = count.clamp(0, 999));
      }
    } catch (_) {
      // csendben elnyeljük
    }
  }

  // --- Gesztusok
  void startPosition(DragStartDetails details) {
    setState(() => isDragging = true);
  }

  void updatePosition(DragUpdateDetails details) {
    if (details.delta.dy.abs() < details.delta.dx.abs()) {
      setState(() {
        position += Offset(details.delta.dx, 0);
        angle = 45 * position.dx / MediaQuery.of(context).size.width;
      });
    }
  }

  void endPosition(DragEndDetails details) {
    setState(() => isDragging = false);

    final screenWidth = MediaQuery.of(context).size.width;
    final x = position.dx;

    if (x > screenWidth * 0.2) {
      swipeRight();
    } else if (x < -screenWidth * 0.2) {
      swipeLeft();
    } else {
      resetPosition();
    }
  }

  void swipeRight() {
    animateOut(Offset(2 * MediaQuery.of(context).size.width, 0));
  }

  void swipeLeft() {
    animateOut(Offset(-2 * MediaQuery.of(context).size.width, 0));
  }

  void animateOut(Offset target) {
    final duration = const Duration(milliseconds: 300);
    final curve = Curves.easeOut;

    final animationController = AnimationController(vsync: this, duration: duration);
    final animation = Tween<Offset>(begin: position, end: target)
        .animate(CurvedAnimation(parent: animationController, curve: curve));

    animationController.addListener(() {
      setState(() {
        position = animation.value;
        angle = 45 * position.dx / MediaQuery.of(context).size.width;
      });
    });

    animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        animationController.dispose();
        youtubeController?.close();
        youtubeController = null;

        setState(() {
          currentIndex++;
          position = Offset.zero;
          angle = 0;
          showDescriptionPanel = false;
          trailerReady = false;
        });
      }
    });

    animationController.forward();
  }

  void resetPosition() {
    setState(() {
      position = Offset.zero;
      angle = 0;
    });
  }

  Future<void> openDescriptionPanel() async {
    if (currentIndex >= movies.length) return;
    final movie = movies[currentIndex];

    if (movie.trailerKey == null) {
      final trailerKey = await TMDBService().fetchTrailerKey(movie.id);
      if (!mounted) return;
      movies[currentIndex] = movie.copyWith(trailerKey: trailerKey);
    }

    setState(() {
      showDescriptionPanel = true;
      trailerReady = false;
    });

    panelController.forward().then((_) {
      final trailerKey = movies[currentIndex].trailerKey;
      if (trailerKey != null && isEmbeddedVideoSupported) {
        youtubeController = YoutubePlayerController(
          params: const YoutubePlayerParams(
            mute: false,
            showControls: true,
            showFullscreenButton: true,
          ),
        )..cueVideoById(videoId: trailerKey);

        setState(() => trailerReady = true);
      }
    });
  }

  void closeDescriptionPanel() {
    panelController.reverse().then((_) {
      youtubeController?.pauseVideo();
      setState(() {
        showDescriptionPanel = false;
        trailerReady = false;
      });
    });
  }

  // --- UI elemek
  Widget buildCard(Movie movie) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.network(
        movie.posterPath,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[800],
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }

  Widget buildFrontCard() {
    final movie = movies[currentIndex];
    return GestureDetector(
      onPanStart: startPosition,
      onPanUpdate: updatePosition,
      onPanEnd: endPosition,
      child: Transform.translate(
        offset: position,
        child: Transform.rotate(
          angle: angle * 3.1415926535 / 180,
          child: buildCard(movie),
        ),
      ),
    );
  }

  // Friends ikon + badge (piros pötty)
  Widget _friendsIconWithBadge() {
    final hasBadge = _incomingCount > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.group),
        if (hasBadge)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    panelController.dispose();
    youtubeController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Film Match"),
        backgroundColor: Colors.black,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: "Friends badge frissítés",
            onPressed: _loadIncomingCount,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Center(
        child: movies.isEmpty
            ? const CircularProgressIndicator()
            : currentIndex >= movies.length
                ? const Text(
                    '🎬 Nincs több film!',
                    style: TextStyle(color: Colors.white, fontSize: 22),
                  )
                : Stack(
                    children: [
                      if (currentIndex + 1 < movies.length)
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: buildCard(movies[currentIndex + 1]),
                          ),
                        ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: buildFrontCard(),
                        ),
                      ),

                      // Alsó trigger zóna a panelhez
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragUpdate: (details) {
                            if (details.delta.dy < -10 && !showDescriptionPanel) {
                              openDescriptionPanel();
                            } else if (details.delta.dy > 10 && showDescriptionPanel) {
                              closeDescriptionPanel();
                            }
                          },
                          child: Container(
                            height: size.height * 0.1,
                            color: Colors.transparent,
                          ),
                        ),
                      ),

                      // Leíró panel
                      AnimatedBuilder(
                        animation: panelController,
                        builder: (context, child) {
                          return SlideTransition(
                            position: panelOffset,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: GestureDetector(
                                onVerticalDragUpdate: (details) {
                                  if (details.delta.dy > 5) {
                                    closeDescriptionPanel();
                                  }
                                },
                                child: Container(
                                  height: size.height * 0.7,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[900],
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                                    boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 6,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[600],
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                      Text(
                                        movies[currentIndex].title,
                                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 36),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                movies[currentIndex].overview,
                                                style: const TextStyle(fontSize: 16),
                                              ),
                                              if (trailerReady && youtubeController != null) ...[
                                                const SizedBox(height: 24),
                                                AspectRatio(
                                                  aspectRatio: 16 / 9,
                                                  child: YoutubePlayer(controller: youtubeController!),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
      ),

      // Navbar (Friends balra, Home középen, Account jobbra)
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
          currentIndex: _selectedIndex,
          enableFeedback: false,
          onTap: (int index) {
            if (_selectedIndex == index) return;
            setState(() => _selectedIndex = index);

            // 0: FRIENDS (külön oldal)
            if (index == 0) {
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

            // 4: ACCOUNT (külön oldal)
            if (index == 4) {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const AccountPage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
              return;
            }

            // A Home (2) és a két középső ikon (1,3) marad itt – ha szeretnél külön oldalt rájuk, cseréld le pushReplacement-re.
          },
          selectedItemColor: Colors.purpleAccent,
          unselectedItemColor: Colors.white60,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          iconSize: 24,
          items: [
  BottomNavigationBarItem(icon: friendsIconWithGlobalBadge(), label: ''), // Friends + badge
  const BottomNavigationBarItem(icon: Icon(Icons.chat), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
  const BottomNavigationBarItem(icon: Icon(Icons.extension), label: ''),
  const BottomNavigationBarItem(icon: kAccountIcon, label: ''),           // egységes Account
],

        ),
      ),
    );
  }
}
