import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MovieListPage extends StatefulWidget {
  const MovieListPage({super.key});

  @override
  State<MovieListPage> createState() => MovieListPageState();
}

class MovieListPageState extends State<MovieListPage> {
  List<Map<String, dynamic>> movies = [];

  @override
  void initState() {
    super.initState();
    fetchMovies();
  }

  Future<void> fetchMovies() async {
    try {
      final uri = Uri.parse(
        'https://api.themoviedb.org/3/movie/popular'
        '?api_key=1a008d7235f9bb01ec1391a61512bc43&language=en-US&page=1',
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = (data['results'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        if (!mounted) return;
        setState(() => movies = results);
      } else {
        debugPrint('Hiba a lekérdezés során: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchMovies hiba: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Popular Movies')),
      body: ListView.builder(
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          final poster = movie['poster_path'] as String?;
          final title = (movie['title'] as String?) ?? 'Untitled';

          return ListTile(
            leading: poster == null
                ? const Icon(Icons.image_not_supported)
                : Image.network(
                    'https://image.tmdb.org/t/p/w200$poster',
                    width: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image),
                  ),
            title: Text(title),
          );
        },
      ),
    );
  }
}
