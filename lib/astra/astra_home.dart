import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/catalog/catalog_item.dart';
import '../utils/app_logger.dart';
import 'streaming_services.dart';
import 'tmdb_client.dart';

/// The home screen's discovery layer: which streaming service is selected in
/// the top switcher, and the TMDB-backed hero titles and rows for it.
///
/// "For You" (no service) shows TMDB's weekly trending in the hero and mixes
/// TMDB rows around the user's own server rows. A selected service replaces
/// the hero and rows with what TMDB lists on that service in the US. Rows are
/// labelled as popularity, never as a service's official ranking.
class AstraHome extends ChangeNotifier {
  AstraHome._() {
    unawaited(_restore());
  }
  static final AstraHome instance = AstraHome._();

  static const _prefsKey = 'astra_selected_service';
  static const int heroCount = 6;

  String? _serviceId;
  bool _loading = false;
  int _generation = 0;
  final Map<String, ({List<MediaItem> hero, List<MediaHub> hubs})> _byService = {};

  /// Null means "For You".
  String? get serviceId => _serviceId;
  StreamingService? get service => streamingServiceById(_serviceId);
  bool get isForYou => _serviceId == null;
  bool get loading => _loading;

  /// Bumps whenever [heroItems] or [hubs] change, for cheap memo keys.
  int get generation => _generation;

  String get _key => _serviceId ?? 'foryou';
  List<MediaItem> get heroItems => _byService[_key]?.hero ?? const [];
  List<MediaHub> get hubs => _byService[_key]?.hubs ?? const [];

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (streamingServiceById(saved) != null) _serviceId = saved;
    } catch (_) {}
    unawaited(load());
  }

  Future<void> select(String? serviceId) async {
    if (serviceId == _serviceId) return;
    _serviceId = serviceId;
    _generation++;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (serviceId == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, serviceId);
      }
    } catch (_) {}
    await load();
  }

  Future<void> load({bool force = false}) async {
    if (!tmdbAvailable) return;
    final key = _key;
    if (!force && _byService.containsKey(key)) return;
    _loading = true;
    notifyListeners();
    try {
      final result = service == null ? await _loadForYou() : await _loadService(service!);
      _byService[key] = result;
    } catch (e) {
      appLogger.w('Astra: TMDB load failed for $key', error: e);
    } finally {
      _loading = false;
      _generation++;
      notifyListeners();
    }
  }

  static List<CatalogItem> _interleave(List<CatalogItem> a, List<CatalogItem> b) {
    final out = <CatalogItem>[];
    final seen = <String>{};
    for (var i = 0; i < a.length || i < b.length; i++) {
      for (final list in [a, b]) {
        if (i < list.length && seen.add(list[i].identityKey)) out.add(list[i]);
      }
    }
    return out;
  }

  static MediaHub _hub(String id, String title, List<CatalogItem> items) => MediaHub(
    id: 'astra.$id',
    identifier: 'astra.$id',
    title: title,
    type: 'mixed',
    items: [for (final i in items) i.toMediaItem()],
    size: items.length,
  );

  Future<List<MediaItem>> _hero(List<CatalogItem> candidates) async {
    final picks = candidates.where((i) => i.backdropUrl != null).take(heroCount).toList();
    final enriched = await Future.wait(picks.map(TmdbClient.instance.enrich));
    return [for (final i in enriched) i.toMediaItem()];
  }

  Future<({List<MediaItem> hero, List<MediaHub> hubs})> _loadForYou() async {
    final tmdb = TmdbClient.instance;
    final r = await Future.wait([tmdb.trendingWeek(), tmdb.popularMovies(), tmdb.popularShows(), tmdb.topRatedMovies()]);
    final hero = await _hero(r[0]);
    return (
      hero: hero,
      hubs: [
        _hub('trending', 'Trending This Week', r[0]),
        _hub('popular-movies', 'Popular Movies', r[1]),
        _hub('popular-tv', 'Popular TV', r[2]),
        _hub('top-rated', 'Top Rated', r[3]),
      ],
    );
  }

  Future<({List<MediaItem> hero, List<MediaHub> hubs})> _loadService(StreamingService s) async {
    final tmdb = TmdbClient.instance;
    final r = await Future.wait([
      tmdb.onService(s, MediaKind.movie),
      tmdb.onService(s, MediaKind.show),
      tmdb.onService(s, MediaKind.movie, topRated: true),
      tmdb.onService(s, MediaKind.show, topRated: true),
    ]);
    final popular = _interleave(r[1], r[0]);
    final hero = await _hero(popular);
    return (
      hero: hero,
      hubs: [
        _hub('${s.id}.popular', 'Popular on ${s.label}', popular),
        _hub('${s.id}.tv', 'TV Shows on ${s.label}', r[1]),
        _hub('${s.id}.movies', 'Movies on ${s.label}', r[0]),
        _hub('${s.id}.top', 'Top Rated on ${s.label}', _interleave(r[3], r[2])),
      ],
    );
  }
}
