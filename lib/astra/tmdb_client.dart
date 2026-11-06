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
  /// Finds a TMDB id by title and year (for server items without TMDB guids).
  Future<int?> findId(String title, int? year, MediaKind kind) async {
    final isShow = kind == MediaKind.show;
    try {
      final json = await _get(isShow ? '/search/tv' : '/search/movie', {
        'query': title,
        if (year != null) (isShow ? 'first_air_date_year' : 'year'): '$year',
      });
      if (json is! Map || json['results'] is! List) return null;
      final first = (json['results'] as List).whereType<Map>().firstOrNull;
      return first?['id'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Everything the Astra details page shows for one title.
  Future<TmdbDetail?> detail(int id, MediaKind kind) async {
    final isShow = kind == MediaKind.show;
    try {
      await _ensureGenres();
      final json = await _get(isShow ? '/tv/$id' : '/movie/$id', {
        'append_to_response': [
          'credits',
          'videos',
          'recommendations',
          'images',
          'external_ids',
          if (isShow) 'content_ratings' else 'release_dates',
        ].join(','),
        'include_image_language': 'en,null',
      });
      if (json is! Map) return null;
      final base = await enrich(CatalogItem(source: CatalogSourceId.tmdb, kind: kind, title: (isShow ? json['name'] : json['title']) as String? ?? '', ids: CatalogItemIds(tmdb: id)));
      final credits = json['credits'];
      final cast = <TmdbPerson>[
        if (credits is Map && credits['cast'] is List)
          for (final c in (credits['cast'] as List).whereType<Map>().take(20))
            TmdbPerson(
              name: c['name'] as String? ?? '',
              role: c['character'] as String? ?? '',
              photo: image(c['profile_path'] as String?, 'w185'),
            ),
      ];
      final crew = credits is Map && credits['crew'] is List ? (credits['crew'] as List).whereType<Map>().toList() : <Map>[];
      List<String> crewNames(bool Function(Map) test) => [
        for (final c in crew)
          if (test(c) && c['name'] is String) c['name'] as String,
      ].toSet().toList();
      final directors = isShow
          ? [
              if (json['created_by'] is List)
                for (final c in (json['created_by'] as List).whereType<Map>())
                  if (c['name'] is String) c['name'] as String,
            ]
          : crewNames((c) => c['job'] == 'Director');
      final writers = crewNames((c) => c['department'] == 'Writing').take(3).toList();
      final studios = [
        for (final c in ((isShow ? json['networks'] : json['production_companies']) as List? ?? const []).whereType<Map>())
          if (c['name'] is String) c['name'] as String,
      ];
      final videos = json['videos'];
      final trailers = <TmdbVideo>[
        if (videos is Map && videos['results'] is List)
          for (final v in (videos['results'] as List).whereType<Map>())
            if (v['site'] == 'YouTube' && v['key'] is String)
              TmdbVideo(name: v['name'] as String? ?? 'Trailer', key: v['key'] as String, type: v['type'] as String? ?? ''),
      ]..sort((a, b) => (a.type == 'Trailer' ? 0 : 1).compareTo(b.type == 'Trailer' ? 0 : 1));
      final recs = json['recommendations'];
      final related = <CatalogItem>[
        if (recs is Map && recs['results'] is List)
          for (final r in (recs['results'] as List))
            if (_toItem(r, forcedKind: kind) case final item?) item,
      ];
      return TmdbDetail(
        item: CatalogItem(
          source: CatalogSourceId.tmdb,
          kind: kind,
          title: base.title,
          year: base.year ?? int.tryParse(((isShow ? json['first_air_date'] : json['release_date']) as String? ?? '').split('-').first),
          overview: json['overview'] as String?,
          rating: (json['vote_average'] as num?)?.toDouble(),
          votes: json['vote_count'] as int?,
          genres: base.genres,
          certification: base.certification,
          runtimeMinutes: base.runtimeMinutes,
          episodeCount: base.episodeCount,
          ids: base.ids,
          posterUrl: image(json['poster_path'] as String?, 'w500'),
          backdropUrl: base.backdropUrl,
          logoUrl: base.logoUrl,
          tagline: json['tagline'] as String?,
        ),
        cast: cast,
        directors: directors,
        writers: writers,
        studio: studios.firstOrNull,
        trailers: trailers.take(6).toList(),
        related: related.take(18).toList(),
        seasons: isShow ? json['number_of_seasons'] as int? : null,
      );
    } catch (_) {
      return null;
    }
  }
}

class TmdbPerson {
  const TmdbPerson({required this.name, required this.role, this.photo});
  final String name;
  final String role;
  final String? photo;
}

class TmdbVideo {
  const TmdbVideo({required this.name, required this.key, required this.type});
  final String name;
  final String key;
  final String type;
  String get thumbnail => 'https://img.youtube.com/vi/$key/hqdefault.jpg';
  Uri get url => Uri.parse('https://www.youtube.com/watch?v=$key');
}

class TmdbDetail {
  const TmdbDetail({
    required this.item,
    required this.cast,
    required this.directors,
    required this.writers,
    required this.studio,
    required this.trailers,
    required this.related,
    required this.seasons,
  });
  final CatalogItem item;
  final List<TmdbPerson> cast;
  final List<String> directors;
  final List<String> writers;
  final String? studio;
  final List<TmdbVideo> trailers;
  final List<CatalogItem> related;
  final int? seasons;
}

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}
