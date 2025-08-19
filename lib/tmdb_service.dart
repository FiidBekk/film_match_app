import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class Movie {
  final String title;
  final String overview;
  final String posterPath;
  final int id;
  final String? trailerKey;

  Movie({
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.id,
    this.trailerKey,
  });

  Movie copyWith({String? trailerKey}) {
    return Movie(
      title: title,
      overview: overview,
      posterPath: posterPath,
      id: id,
      trailerKey: trailerKey ?? this.trailerKey,
    );
  }

  factory Movie.fromJson(Map<String, dynamic> json, {String? trailerKey}) {
    return Movie(
      title: json['title'],
      overview: json['overview'] ?? '',
      posterPath: 'https://image.tmdb.org/t/p/w500${json['poster_path']}',
      id: json['id'],
      trailerKey: trailerKey,
    );
  }
}

class TMDBService {
  final String _apiKey = '1a008d7235f9bb01ec1391a61512bc43';

  /// Véletlenszerűen válogat filmeket a teljes kínálatból (maximum 500 oldal elérhető az API szerint)
  Future<List<Movie>> fetchRandomMovies({int pageCount = 10}) async {
    List<Map<String, dynamic>> allMovieJsons = [];

    final random = Random();
    final Set<int> usedPages = {};

    // Véletlenszerű oldalszámok kiválasztása (1–500 között)
    while (usedPages.length < pageCount) {
      usedPages.add(random.nextInt(500) + 1);
    }

    // Lekérjük az oldalakat
    for (int page in usedPages) {
      final url = Uri.parse(
        'https://api.themoviedb.org/3/discover/movie?api_key=$_apiKey&language=en-US&page=$page',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final List results = jsonData['results'];
        allMovieJsons.addAll(results.cast<Map<String, dynamic>>());
      }
    }

    // Egyedi filmek ID alapján
    final uniqueJsons = {
      for (var json in allMovieJsons) json['id']: json,
    }.values.toList();

    uniqueJsons.shuffle();

    return uniqueJsons.map((json) => Movie.fromJson(json)).toList();
  }

  /// Trailer lekérdezése egy adott filmhez (csak akkor hívjuk meg, ha a leírás meg van nyitva)
  Future<String?> fetchTrailerKey(int movieId) async {
    final url = Uri.parse(
      'https://api.themoviedb.org/3/movie/$movieId/videos?api_key=$_apiKey&language=en-US',
    );
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final results = json.decode(response.body)['results'] as List;
      final trailer = results.firstWhere(
        (video) => video['type'] == 'Trailer' && video['site'] == 'YouTube',
        orElse: () => null,
      );
      return trailer != null ? trailer['key'] : null;
    } else {
      return null;
    }
  }
}
