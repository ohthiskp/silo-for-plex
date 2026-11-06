import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../media/media_kind.dart';
import '../models/catalog/catalog_item.dart';
import 'streaming_services.dart';

/// TMDB read token, injected at build time (`--dart-define=TMDB_TOKEN=...`).
const String kTmdbToken = String.fromEnvironment('TMDB_TOKEN');

bool get tmdbAvailable => kTmdbToken.isNotEmpty;

/// Minimal TMDB v3 client for Astra's discovery surfaces, with an in-memory
/// cache so switching services back and forth is instant.
class TmdbClient {
  TmdbClient._();
  static final TmdbClient instance = TmdbClient._();

  static const _base = 'https://api.themoviedb.org/3';
  static const _img = 'https://image.tmdb.org/t/p';
  static const Duration _ttl = Duration(minutes: 30);

  final http.Client _http = http.Client();
  final Map<String, ({DateTime at, Object? json})> _cache = {};
  final Map<String, Future<Object?>> _inflight = {};
  Map<int, String>? _movieGenres;
  Map<int, String>? _tvGenres;

  Future<Object?> _get(String path, [Map<String, String> query = const {}]) {
    final uri = Uri.parse('$_base$path').replace(queryParameters: {'language': 'en-US', ...query});
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) return Future.value(hit.json);
    return _inflight.putIfAbsent(key, () async {
      try {
        final res = await _http
            .get(uri, headers: {'Authorization': 'Bearer $kTmdbToken', 'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) throw TmdbException('TMDB ${res.statusCode} for $path');
        final json = jsonDecode(res.body);
        _cache[key] = (at: DateTime.now(), json: json);
        return json;
      } finally {
        unawaited(_inflight.remove(key));
      }
    });
  }

  Future<void> _ensureGenres() async {
    if (_movieGenres != null && _tvGenres != null) return;
    Map<int, String> parse(Object? json) {
      final out = <int, String>{};
      if (json is Map && json['genres'] is List) {
        for (final g in json['genres'] as List) {
          if (g is Map && g['id'] is int && g['name'] is String) out[g['id'] as int] = g['name'] as String;
        }
      }
      return out;
    }

    final results = await Future.wait([_get('/genre/movie/list'), _get('/genre/tv/list')]);
    _movieGenres = parse(results[0]);
    _tvGenres = parse(results[1]);
  }

  static String? image(String? path, String size) => path == null || path.isEmpty ? null : '$_img/$size$path';

  CatalogItem? _toItem(Object? raw, {MediaKind? forcedKind}) {
    if (raw is! Map) return null;
    final mediaType = raw['media_type'];
    final kind = forcedKind ?? (mediaType == 'tv' ? MediaKind.show : mediaType == 'movie' ? MediaKind.movie : null);
    if (kind == null) return null;
    final id = raw['id'];
    if (id is! int) return null;
    final isShow = kind == MediaKind.show;
    final title = (isShow ? raw['name'] : raw['title']) as String?;
    if (title == null || title.isEmpty) return null;
    final date = (isShow ? raw['first_air_date'] : raw['release_date']) as String?;
    final genreNames = isShow ? _tvGenres : _movieGenres;
    final genres = <String>[
      if (raw['genre_ids'] is List)
        for (final g in raw['genre_ids'] as List)
          if (g is int && genreNames?[g] != null) genreNames![g]!,
    ];
    final vote = raw['vote_average'];
    return CatalogItem(
      source: CatalogSourceId.tmdb,
      kind: kind,
      title: title,
      year: date != null && date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      releaseDate: date == null || date.isEmpty ? null : DateTime.tryParse(date),
      overview: raw['overview'] as String?,
      rating: vote is num && vote > 0 ? vote.toDouble() : null,
      votes: raw['vote_count'] is int ? raw['vote_count'] as int : null,
      genres: genres.isEmpty ? null : genres,
      ids: CatalogItemIds(tmdb: id),
      posterUrl: image(raw['poster_path'] as String?, 'w342'),
      backdropUrl: image(raw['backdrop_path'] as String?, 'w1280'),
    );
  }

  Future<List<CatalogItem>> _list(String path, Map<String, String> query, {MediaKind? kind}) async {
    await _ensureGenres();
    final json = await _get(path, query);
    if (json is! Map || json['results'] is! List) return const [];
    return [
      for (final r in json['results'] as List)
        if (_toItem(r, forcedKind: kind) case final item?)
          if (item.backdropUrl != null || item.posterUrl != null) item,
    ];
  }

  Future<List<CatalogItem>> trendingWeek() => _list('/trending/all/week', const {});

  Future<List<CatalogItem>> popularMovies() =>
      _list('/discover/movie', {'sort_by': 'popularity.desc', 'watch_region': tmdbWatchRegion}, kind: MediaKind.movie);

  Future<List<CatalogItem>> popularShows() =>
      _list('/discover/tv', {'sort_by': 'popularity.desc', 'watch_region': tmdbWatchRegion}, kind: MediaKind.show);

  Future<List<CatalogItem>> topRatedMovies() => _list('/movie/top_rated', const {}, kind: MediaKind.movie);

  Future<List<CatalogItem>> onService(StreamingService service, MediaKind kind, {bool topRated = false}) {
    final isShow = kind == MediaKind.show;
    return _list(isShow ? '/discover/tv' : '/discover/movie', {
      'with_watch_providers': service.tmdbFilter,
      'watch_region': tmdbWatchRegion,
      'with_watch_monetization_types': 'flatrate',
      'sort_by': topRated ? 'vote_average.desc' : 'popularity.desc',
      if (topRated) 'vote_count.gte': isShow ? '200' : '500',
    }, kind: kind);
  }

  /// Fills in what the hero needs and list endpoints omit: the title logo,
  /// runtime or season count, and the US content rating.
  Future<CatalogItem> enrich(CatalogItem item) async {
    final id = item.ids.tmdb;
    if (id == null) return item;
    final isShow = item.kind == MediaKind.show;
    try {
      final json = await _get(isShow ? '/tv/$id' : '/movie/$id', {
        'append_to_response': isShow ? 'images,content_ratings,external_ids' : 'images,release_dates,external_ids',
        'include_image_language': 'en,null',
      });
      if (json is! Map) return item;
      String? logo;
      final images = json['images'];
      if (images is Map && images['logos'] is List) {
        final logos = (images['logos'] as List).whereType<Map>().toList();
        final en = logos.where((l) => l['iso_639_1'] == 'en').toList();
        final pick = (en.isNotEmpty ? en : logos).firstOrNull;
        logo = image(pick?['file_path'] as String?, 'w500');
      }
      String? cert;
      if (isShow) {
        final results = (json['content_ratings'] as Map?)?['results'];
        if (results is List) {
          for (final r in results.whereType<Map>()) {
            if (r['iso_3166_1'] == 'US' && (r['rating'] as String?)?.isNotEmpty == true) cert = r['rating'] as String;
          }
        }
      } else {
        final results = (json['release_dates'] as Map?)?['results'];
        if (results is List) {
          for (final r in results.whereType<Map>()) {
            if (r['iso_3166_1'] != 'US' || r['release_dates'] is! List) continue;
            for (final d in (r['release_dates'] as List).whereType<Map>()) {
              final c = d['certification'] as String?;
              if (c != null && c.isNotEmpty) {
                cert = c;
                break;
              }
            }
          }
        }
      }
      final runtime = isShow ? null : json['runtime'] as int?;
      final seasons = isShow ? json['number_of_seasons'] as int? : null;
      final ext = json['external_ids'];
      final imdb = ext is Map ? ext['imdb_id'] as String? : null;
      final tvdb = ext is Map ? ext['tvdb_id'] as int? : null;
      final genres = <String>[
        if (json['genres'] is List)
          for (final g in (json['genres'] as List).whereType<Map>())
            if (g['name'] is String) g['name'] as String,
      ];
      return CatalogItem(
        source: item.source,
        kind: item.kind,
        title: item.title,
        year: item.year,
        releaseDate: item.releaseDate,
        overview: item.overview,
        rating: item.rating,
        votes: item.votes,
        genres: genres.isEmpty ? item.genres : genres,
        certification: cert,
        runtimeMinutes: runtime,
        episodeCount: seasons,
        ids: CatalogItemIds(tmdb: id, imdb: imdb, tvdb: tvdb),
        posterUrl: item.posterUrl,
        backdropUrl: image(json['backdrop_path'] as String?, 'original') ?? item.backdropUrl,
        logoUrl: logo,
      );
    } catch (_) {
      return item;
    }
  }
}

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}
