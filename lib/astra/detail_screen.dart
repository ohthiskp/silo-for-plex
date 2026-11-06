import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../media/catalog_item_ref.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/catalog/catalog_item.dart';
import '../providers/catalog_sources_provider.dart';
import '../services/catalog/catalog_library_matcher.dart';
import '../services/catalog/catalog_source.dart';
import '../utils/external_ids.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../widgets/optimized_media_image.dart';
import 'astra_style.dart';
import 'tmdb_client.dart';

/// Astra 3.0 details page for movies and shows, from a server item or a
/// TMDB catalog item. Play is offered only when the title is on the user's
/// server; otherwise the primary action is Request.
class AstraDetailScreen extends StatefulWidget {
  const AstraDetailScreen({super.key, required this.item, this.onLegacyDetails, this.onRequest});

  final MediaItem item;

  /// Opens the classic server detail page (seasons and episodes).
  final Future<void> Function(BuildContext context, MediaItem libraryItem)? onLegacyDetails;

  /// Opens the request flow for a title that isn't on the server.
  final Future<void> Function(BuildContext context, CatalogItem item)? onRequest;

  @override
  State<AstraDetailScreen> createState() => _AstraDetailScreenState();
}

enum _Tab { overview, cast, trailers, related }

class _AstraDetailScreenState extends State<AstraDetailScreen> {
  TmdbDetail? _detail;
  MediaItem? _library; // the playable copy on the user's server, if any
  bool _matching = true;
  _Tab _tab = _Tab.overview;

  MediaItem get item => widget.item;
  bool get _isCatalog => item.isCatalogItem;
  MediaKind get _kind => item.kind == MediaKind.show || item.kind == MediaKind.season ? MediaKind.show : MediaKind.movie;

  @override
  void initState() {
    super.initState();
    final src = _wlSource = context.read<CatalogSourcesProvider>().watchlistCapableSource;
    if (src != null) {
      src.watchlistChanges.addListener(_onWatchlistChanged);
      unawaited(src.ensureWatchlistLoaded());
    }
    if (!_isCatalog) {
      _library = item;
      _matching = false;
    }
    unawaited(_load());
  }

  void _onWatchlistChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _wlSource?.watchlistChanges.removeListener(_onWatchlistChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = item.catalogItem;
    var tmdbId = catalog?.ids.tmdb;
    if (tmdbId == null && !_isCatalog) {
      final guids = item.raw?['Guid'];
      if (guids is List) tmdbId = ExternalIds.fromGuids(guids).tmdb;
      tmdbId ??= await TmdbClient.instance.findId(item.grandparentTitle ?? item.title ?? '', item.year, _kind);
    }
    if (tmdbId != null && tmdbAvailable) {
      final d = await TmdbClient.instance.detail(tmdbId, _kind);
      if (mounted) setState(() => _detail = d);
    }
    if (_isCatalog && catalog != null) {
      try {
        final result = await context.read<CatalogLibraryMatcher>().match(catalog);
        if (mounted) setState(() => _library = result.items.firstOrNull);
      } catch (_) {
        // Unknown: keep Request; the classic page can retry.
      } finally {
        if (mounted) setState(() => _matching = false);
      }
    }
  }

  // ------------------------------------------------------------ data helpers

  String get _title => _detail?.item.title ?? item.grandparentTitle ?? item.title ?? '';
  String? get _logo => _detail?.item.logoUrl ?? item.clearLogoPath;
  String? get _backdrop => _detail?.item.backdropUrl ?? item.artPath ?? item.grandparentArtPath;
  String? get _poster => _detail?.item.posterUrl ?? item.thumbPath;
  String? get _overview {
    final s = item.summary;
    return (s != null && s.isNotEmpty) ? s : _detail?.item.overview;
  }

  List<String> get _genres => (item.genres?.isNotEmpty ?? false) ? item.genres! : (_detail?.item.genres ?? const []);

  String get _metaLine {
    final year = item.year ?? _detail?.item.year;
    final cert = (item.contentRating?.isNotEmpty ?? false) ? item.contentRating : _detail?.item.certification;
    String? length;
    if (_kind == MediaKind.show) {
      final n = _detail?.seasons ?? item.childCount;
      if (n != null && n > 0) length = n == 1 ? '1 Season' : '$n Seasons';
    } else {
      final mins = item.durationMs != null ? (item.durationMs! / 60000).round() : _detail?.item.runtimeMinutes;
      if (mins != null && mins > 0) length = mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m';
    }
    return [if (year != null) '$year', ?cert, ?length].where((e) => e.isNotEmpty).join('  •  ');
  }

  bool get _is4k {
    final media = _library?.raw?['Media'];
    if (media is List) {
      return media.whereType<Map>().any((m) => '${m['videoResolution']}'.toLowerCase() == '4k');
    }
    return false;
  }

  bool get _isDolbyVision {
    final media = _library?.raw?['Media'];
    if (media is! List) return false;
    for (final m in media.whereType<Map>()) {
      final parts = m['Part'];
      if (parts is! List) continue;
      for (final p in parts.whereType<Map>()) {
        final streams = p['Stream'];
        if (streams is List && streams.whereType<Map>().any((s) => s['DOVIPresent'] == true || s['DOVIPresent'] == '1')) {
          return true;
        }
      }
    }
    return false;
  }

  String? get _rottenTomatoes {
    for (final r in item.ratings ?? const []) {
      if (r.source == 'rottenTomatoesCritic') return '${(r.value * 10).round()}%';
    }
    return null;
  }

  // ------------------------------------------------------------ actions

  void _play() {
    final lib = _library;
    if (lib == null) return;
    // Shows play from their episode list (next up / pick a season).
    if (_kind == MediaKind.show && widget.onLegacyDetails != null) {
      unawaited(widget.onLegacyDetails!(context, lib));
      return;
    }
    unawaited(navigateToMediaItem(context, lib, playDirectly: true));
  }

  CatalogSource? _wlSource;
  CatalogSource? get _watchlistSource => _wlSource;

  CatalogItemIds? get _ids {
    final c = item.catalogItem;
    if (c != null) return c.ids;
    final d = _detail?.item.ids;
    return d;
  }

  bool? get _onWatchlist {
    final src = _watchlistSource;
    final ids = _ids;
    if (src == null || ids == null) return null;
    return src.isOnWatchlist(_kind, ids);
  }

  Future<void> _toggleWatchlist() async {
    final src = _watchlistSource;
    final ids = _ids;
    if (src == null || ids == null) return;
    final resolved = await src.resolveItemIds(_kind, ids.toExternalIds()) ?? ids;
    try {
      if (src.isOnWatchlist(_kind, resolved) == true) {
        await src.removeFromWatchlist(_kind, resolved);
      } else {
        await src.addToWatchlist(_kind, resolved);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Widget _watchlistButton({double? width, required double height}) {
    final on = _onWatchlist == true;
    return AstraGlassButton(
      label: on ? 'On Watchlist' : 'Watchlist',
      icon: on ? Icons.check_rounded : Icons.add_rounded,
      width: width,
      height: height,
      onTap: _toggleWatchlist,
    );
  }

  Future<void> _request() async {
    final catalog = item.catalogItem ?? _detail?.item;
    if (catalog == null || widget.onRequest == null) return;
    await widget.onRequest!(context, catalog);
  }

  void _openRelated(CatalogItem c) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AstraDetailScreen(item: c.toMediaItem(), onLegacyDetails: widget.onLegacyDetails, onRequest: widget.onRequest),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    final top = MediaQuery.paddingOf(context).top;
    final client = _library != null ? context.getMediaClientForItemOrNull(_library!) : null;
    final artClient = _backdrop?.startsWith('http') ?? false ? null : client;

    return Scaffold(
      backgroundColor: AstraColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: wide ? _wideHeader(context, artClient, client) : _phoneHeader(context, artClient, client)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(wide ? 48 : 22, 6, wide ? 48 : 22, 0),
                  child: _tabs(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(wide ? 48 : 22, 8, wide ? 48 : 0, MediaQuery.paddingOf(context).bottom + 60),
                  child: _tabBody(wide),
                ),
              ),
            ],
          ),
          Positioned(
            top: top + (wide ? 22 : 10),
            left: wide ? 40 : 16,
            child: _CircleButton(icon: Icons.chevron_left_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
          ),
          if (!wide && _library != null && _kind == MediaKind.show && widget.onLegacyDetails != null)
            Positioned(
              top: top + 10,
              right: 16,
              child: _CircleButton(
                icon: Icons.more_horiz_rounded,
                label: 'Seasons and episodes',
                onTap: () => widget.onLegacyDetails!(context, _library!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _art(dynamic client, {Alignment alignment = const Alignment(0.3, -0.4)}) {
    final art = _backdrop;
    if (art == null) return const ColoredBox(color: AstraColors.surface);
    return OptimizedMediaImage(client: client, imagePath: art, imageType: ImageType.art, fit: BoxFit.cover, alignment: alignment);
  }

  Widget _logoOrTitle(dynamic client, {required bool wide, required double width, required double height}) {
    final logo = _logo;
    final title = _title;
    final subtitle = title.contains(':') ? title.split(':').last.trim() : null;
    if (logo == null || logo.isEmpty) {
      return AstraTitleText(subtitle != null ? title.split(':').first : title, wide: true);
    }
    return ClearLogoImage(
      client: logo.startsWith('http') ? null : client,
      logoPath: logo,
      width: width,
      height: height,
      fallbackWidth: width,
      alignment: Alignment.bottomLeft,
      fallbackBuilder: (_) => AstraTitleText(title, wide: true),
    );
  }

  Widget _phoneHeader(BuildContext context, dynamic artClient, dynamic client) {
    final h = (MediaQuery.sizeOf(context).height * 0.52).clamp(380.0, 520.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _art(artClient),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0, 0.35, 0.65],
                    colors: [AstraColors.bg, Color(0x9907060B), Color(0x0007060B)],
                  ),
                ),
              ),
              Positioned(left: 24, right: 24, bottom: 12, child: _logoOrTitle(client, wide: false, width: 300, height: 100)),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 0), child: _infoBlock(wide: false)),
      ],
    );
  }

  Widget _wideHeader(BuildContext context, dynamic artClient, dynamic client) {
    final poster = _poster;
    return SizedBox(
      height: 600,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _art(artClient, alignment: const Alignment(0.6, -0.3)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                stops: [0, 0.35, 0.62, 0.85],
                colors: [Color(0xF507060B), Color(0xD107060B), Color(0x3307060B), Color(0x0007060B)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: [0, 0.3],
                colors: [AstraColors.bg, Color(0x0007060B)],
              ),
            ),
          ),
          Positioned(
            left: 48,
            top: 120,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              child: Container(
                width: 230,
                height: 345,
                decoration: BoxDecoration(
                  color: AstraColors.surface,
                  border: Border.all(color: const Color(0x24FFFFFF)),
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                ),
                child: poster == null
                    ? null
                    : OptimizedMediaImage(
                        client: poster.startsWith('http') ? null : client,
                        imagePath: poster,
                        imageType: ImageType.poster,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
          Positioned(
            left: 316,
            top: 128,
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _logoOrTitle(client, wide: true, width: 440, height: 130),
                const SizedBox(height: 22),
                _infoBlock(wide: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock({required bool wide}) {
    final tmdbScore = _detail?.item.rating ?? item.catalogItem?.rating;
    final rt = _rottenTomatoes;
    final onServer = _library != null;
    final showAction = !_matching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (_metaLine.isNotEmpty) Text(_metaLine, style: const TextStyle(color: AstraColors.muted, fontSize: 14.5)),
            if (_is4k) const _Badge('4K'),
            if (_isDolbyVision) const Text('Dolby Vision', style: TextStyle(color: AstraColors.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
        if (tmdbScore != null || rt != null) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            children: [
              if (rt != null) _Chip(leading: const _TomatoDot(), label: rt),
              if (tmdbScore != null && tmdbScore > 0) _Chip(label: 'TMDB ${tmdbScore.toStringAsFixed(1)}'),
            ],
          ),
        ],
        if ((_overview ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 470 : 700),
            child: Text(
              _overview!,
              maxLines: wide ? 4 : 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xD1F2F0F7), fontSize: 15.5, height: 1.55),
            ),
          ),
        ],
        const SizedBox(height: 22),
        AnimatedOpacity(
          opacity: showAction ? 1 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: Row(
            children: [
              if (wide) ...[
                AstraPlayButton(
                  label: onServer ? 'Play' : 'Request',
                  icon: onServer ? Icons.play_arrow_rounded : Icons.add_rounded,
                  width: 160,
                  height: 50,
                  onTap: onServer ? _play : _request,
                ),
                const SizedBox(width: 14),
                if (_watchlistSource != null) _watchlistButton(width: 172, height: 50),
                if (onServer && _kind == MediaKind.show && widget.onLegacyDetails != null) ...[
                  const SizedBox(width: 14),
                  AstraGlassButton(
                    label: 'Episodes',
                    icon: Icons.format_list_bulleted_rounded,
                    height: 50,
                    onTap: () => widget.onLegacyDetails!(context, _library!),
                  ),
                ],
              ] else ...[
                Expanded(
                  child: AstraPlayButton(
                    label: onServer ? 'Play' : 'Request',
                    icon: onServer ? Icons.play_arrow_rounded : Icons.add_rounded,
                    height: 52,
                    onTap: onServer ? _play : _request,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: onServer && _kind == MediaKind.show && widget.onLegacyDetails != null
                      ? AstraGlassButton(
                          label: 'Episodes',
                          icon: Icons.format_list_bulleted_rounded,
                          height: 52,
                          onTap: () => widget.onLegacyDetails!(context, _library!),
                        )
                      : _watchlistSource != null
                      ? _watchlistButton(height: 52)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
        if (!_matching && !onServer)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Not on your server yet.', style: TextStyle(color: AstraColors.muted, fontSize: 12.5)),
          ),
      ],
    );
  }

  Widget _tabs() {
    const labels = {_Tab.overview: 'Overview', _Tab.cast: 'Cast', _Tab.trailers: 'Trailers', _Tab.related: 'Related'};
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AstraColors.hairline))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in _Tab.values)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Semantics(
                  selected: _tab == t,
                  button: true,
                  child: InkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    onTap: () => setState(() => _tab = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: _tab == t ? const Color(0x24FFFFFF) : Colors.transparent,
                        borderRadius: const BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        labels[t]!,
                        style: TextStyle(
                          color: _tab == t ? AstraColors.ink : AstraColors.muted,
                          fontSize: 15.5,
                          fontWeight: _tab == t ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabBody(bool wide) {
    final d = _detail;
    switch (_tab) {
      case _Tab.overview:
        final facts = Column(
          children: [
            if (d != null && d.directors.isNotEmpty) _Fact(_kind == MediaKind.show ? 'Created by' : 'Director', Text(d.directors.join(', '), style: _factStyle)),
            if (d != null && d.writers.isNotEmpty) _Fact('Writers', Text(d.writers.join(', '), style: _factStyle)),
            if (_genres.isNotEmpty)
              _Fact('Genres', Wrap(spacing: 8, runSpacing: 6, children: [for (final g in _genres.take(4)) _GenreChip(g)])),
            if (d?.studio != null) _Fact(_kind == MediaKind.show ? 'Network' : 'Studio', Text(d!.studio!, style: _factStyle), last: true),
          ],
        );
        final cast = _castRow(d, compact: !wide);
        if (wide) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 520, child: facts),
                const SizedBox(width: 56),
                Expanded(child: cast),
              ],
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(right: 22), child: facts), const SizedBox(height: 18), cast]);
      case _Tab.cast:
        final people = d?.cast ?? const <TmdbPerson>[];
        return Padding(
          padding: EdgeInsets.only(top: 16, right: wide ? 0 : 22),
          child: Wrap(spacing: 12, runSpacing: 14, children: [for (final p in people) _PersonCard(p, width: wide ? 150 : 104)]),
        );
      case _Tab.trailers:
        final vids = d?.trailers ?? const <TmdbVideo>[];
        if (vids.isEmpty) return const _Empty('No trailers yet.');
        return Padding(
          padding: EdgeInsets.only(top: 16, right: wide ? 0 : 22),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final v in vids)
                InkWell(
                  onTap: () => launchUrl(v.url, mode: LaunchMode.externalApplication),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  child: SizedBox(
                    width: wide ? 300 : double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(Radius.circular(12)),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(v.thumbnail, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: AstraColors.surface)),
                                const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 46)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AstraColors.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      case _Tab.related:
        final rel = d?.related ?? const <CatalogItem>[];
        if (rel.isEmpty) return const _Empty('Nothing related yet.');
        return Padding(
          padding: EdgeInsets.only(top: 16, right: wide ? 0 : 22),
          child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              for (final c in rel)
                InkWell(
                  onTap: () => _openRelated(c),
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  child: SizedBox(
                    width: wide ? 180 : 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.all(Radius.circular(10)),
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: c.posterUrl == null
                                ? const ColoredBox(color: AstraColors.surface)
                                : Image.network(c.posterUrl!, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AstraColors.ink, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
    }
  }

  Widget _castRow(TmdbDetail? d, {required bool compact}) {
    final people = d?.cast ?? const <TmdbPerson>[];
    if (people.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _tab = _Tab.cast),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cast', style: TextStyle(color: AstraColors.ink, fontSize: 21, fontWeight: FontWeight.w700)),
                Icon(Icons.chevron_right_rounded, color: AstraColors.ink),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: compact ? 172 : 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(right: compact ? 22 : 0),
            itemCount: people.length.clamp(0, 12),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _PersonCard(people[i], width: compact ? 122 : 150),
          ),
        ),
      ],
    );
  }
}

const _factStyle = TextStyle(color: AstraColors.ink, fontSize: 15);

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.last = false});
  final String label;
  final Widget value;
  final bool last;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AstraColors.hairline))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AstraColors.muted, fontSize: 15))),
          Expanded(child: value),
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: const BoxDecoration(color: Color(0x14FFFFFF), borderRadius: BorderRadius.all(Radius.circular(999))),
    child: Text(label, style: const TextStyle(color: AstraColors.ink, fontSize: 13.5, fontWeight: FontWeight.w500)),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.all(Radius.circular(7)),
      border: Border.all(color: const Color(0x4DFFFFFF)),
    ),
    child: Text(label, style: const TextStyle(color: AstraColors.ink, fontSize: 13, fontWeight: FontWeight.w800)),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.leading});
  final String label;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0x0AFFFFFF),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      border: Border.all(color: const Color(0x29FFFFFF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Text(label, style: const TextStyle(color: AstraColors.ink, fontSize: 14.5, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _TomatoDot extends StatelessWidget {
  const _TomatoDot();
  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle),
  );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard(this.p, {required this.width});
  final TmdbPerson p;
  final double width;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AstraColors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: AstraColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.05,
            child: p.photo == null
                ? const ColoredBox(color: AstraColors.surface2, child: Icon(Icons.person_rounded, color: AstraColors.muted, size: 40))
                : Image.network(p.photo!, fit: BoxFit.cover, alignment: const Alignment(0, -0.4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AstraColors.ink, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
                if (p.role.isNotEmpty)
                  Text(p.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AstraColors.muted, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: AstraGlass(
        child: SizedBox(width: 48, height: 48, child: Icon(icon, color: Colors.white, size: 28)),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Text(text, style: const TextStyle(color: AstraColors.muted)));
}
