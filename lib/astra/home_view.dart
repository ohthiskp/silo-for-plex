import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/catalog_item_ref.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../providers/catalog_sources_provider.dart';
import '../services/catalog/catalog_source.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../widgets/optimized_media_image.dart';
import '../navigation/main_screen_scope.dart';
import '../screens/search_screen.dart';
import 'astra_art.dart';
import 'astra_home.dart';
import 'astra_style.dart';
import 'service_pill.dart';

/// Astra 3.0 home (iPhone, iPad and Mac): the hero art framed around its
/// faces with the title logo under it, all on a frosted-glass background made
/// from the same art; the service pills on top, then Continue Watching, the
/// ranked Top Trending row and artwork rows. Apple TV keeps its own home.
class AstraHomeView extends StatefulWidget {
  const AstraHomeView({
    super.key,
    required this.heroItems,
    required this.continueWatching,
    required this.hubs,
    required this.scrollController,
    required this.onRefresh,
    required this.loading,
  });

  final List<MediaItem> heroItems;
  final List<MediaItem> continueWatching;
  final List<MediaHub> hubs;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final bool loading;

  @override
  State<AstraHomeView> createState() => _AstraHomeViewState();
}

class _AstraHomeViewState extends State<AstraHomeView> {
  final PageController _pages = PageController();
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant AstraHomeView old) {
    super.didUpdateWidget(old);
    if (!identical(old.heroItems, widget.heroItems)) {
      _index = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
      _arm();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    if (widget.heroItems.length < 2) return;
    _timer = Timer(const Duration(seconds: 8), () {
      if (!mounted || !_pages.hasClients) return;
      final next = (_index + 1) % widget.heroItems.length;
      unawaited(_pages.animateToPage(next, duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic));
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    final pad = MediaQuery.paddingOf(context);
    final topInset = pad.top;
    final heroHeight = wide ? (size.height * 0.7).clamp(540.0, 780.0) : (size.height * 0.79).clamp(560.0, 720.0);
    final rowInset = wide ? 156.0 : 20.0;

    final current = widget.heroItems.isEmpty ? null : widget.heroItems[_index.clamp(0, widget.heroItems.length - 1)];
    final bgClient = current == null ? null : context.getMediaClientForItemOrNull(current);
    final bgArt = current == null ? null : current.artPath ?? current.grandparentArtPath ?? current.thumbPath;

    final hubs = widget.hubs.where((h) => h.items.isNotEmpty).toList();
    final ranked = hubs.isNotEmpty && hubs.first.id.startsWith('astra.') ? hubs.first : null;
    final rest = ranked == null ? hubs : hubs.skip(1);

    final rows = <Widget>[
      if (widget.continueWatching.isNotEmpty)
        _Row(
          title: 'Continue Watching',
          inset: rowInset,
          height: wide ? 170 : 134,
          children: [
            for (final item in widget.continueWatching)
              _ContinueCard(item: item, width: wide ? 320 : 238, height: wide ? 170 : 134),
          ],
        ),
      if (ranked != null)
        _RankedRow(
          hub: ranked,
          title: AstraHome.instance.isForYou ? 'Top Trending' : ranked.title,
          inset: rowInset,
          wide: wide,
        ),
      for (final hub in rest)
        _Row(
          title: hub.title,
          inset: rowInset,
          height: wide ? 168 : 128,
          children: [for (final item in hub.items) _ArtCard(item: item, width: wide ? 220 : 150, height: wide ? 138 : 92)],
        ),
    ];

    return Stack(
      children: [
        Positioned.fill(child: AstraFrostedBackground(imagePath: bgArt, client: bgClient)),
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          edgeOffset: topInset + 60,
          color: AstraColors.purple,
          child: CustomScrollView(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: widget.heroItems.isEmpty
                    ? SizedBox(height: topInset + (wide ? 110 : 90))
                    : SizedBox(
                        height: heroHeight,
                        child: _Hero(
                          items: widget.heroItems,
                          pages: _pages,
                          index: _index,
                          wide: wide,
                          topInset: topInset,
                          onPage: (i) {
                            setState(() => _index = i);
                            _arm();
                          },
                        ),
                      ),
              ),
              if (widget.loading && rows.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(child: CircularProgressIndicator(color: AstraColors.purple)),
                  ),
                ),
              SliverList.list(children: rows),
              SliverToBoxAdapter(child: SizedBox(height: pad.bottom + 40)),
            ],
          ),
        ),
        // Frosted band behind the clock and the service pills.
        Positioned(top: 0, left: 0, right: 0, child: AstraEdgeBlur(height: topInset + (wide ? 110 : 84), top: true)),
        // Frosted band behind the tab bar.
        if (!wide) Positioned(bottom: 0, left: 0, right: 0, child: AstraEdgeBlur(height: pad.bottom + 28, top: false, tint: 0.55)),
        Positioned(
          top: topInset + (wide ? 14 : 2),
          left: 0,
          right: wide ? 140 : 0,
          child: AstraServicePill(
            compact: !wide,
            padding: EdgeInsets.symmetric(horizontal: wide ? rowInset : 16),
          ),
        ),
        if (wide)
          Positioned(
            top: topInset + 22,
            right: 34,
            height: 50,
            child: Row(
              children: [
                _TopIcon(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
                ),
                const SizedBox(width: 14),
                Semantics(
                  button: true,
                  label: 'Profile and settings',
                  child: GestureDetector(
                    onTap: () => MainScreenFocusScope.of(context, listen: false)?.openSettings?.call(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x66FFFFFF), width: 2),
                        gradient: const LinearGradient(colors: [Color(0xFF8D6BFF), Color(0xFF4A2BB8)]),
                      ),
                      child: const Icon(Icons.person_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- hero

class _Hero extends StatelessWidget {
  const _Hero({
    required this.items,
    required this.pages,
    required this.index,
    required this.wide,
    required this.topInset,
    required this.onPage,
  });
  final List<MediaItem> items;
  final PageController pages;
  final int index;
  final bool wide;
  final double topInset;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: pages,
          itemCount: items.length,
          onPageChanged: onPage,
          itemBuilder: (context, i) => wide ? _WideHeroPage(item: items[i]) : _PhoneHeroPage(item: items[i], topInset: topInset),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: wide ? 26 : 24,
          child: IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: i == index ? 1 : 0.35),
                      borderRadius: const BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Phone hero: art framed so faces end above the logo slot, then the logo,
/// the meta line with badges, genres, and Play + the watchlist check.
class _PhoneHeroPage extends StatelessWidget {
  const _PhoneHeroPage({required this.item, required this.topInset});
  final MediaItem item;
  final double topInset;

  static const _logoW = 230.0;
  static const _logoH = 150.0;

  /// Everything from the top of the logo slot down to the dots.
  static const _belowLogoTop = _logoH + 14 + 42 + 18 + 48 + 50;

  @override
  Widget build(BuildContext context) {
    final client = context.getMediaClientForItemOrNull(item);
    final art = item.artPath ?? item.grandparentArtPath ?? item.thumbPath;
    final title = item.grandparentTitle ?? item.title ?? '';
    final logo = item.clearLogoPath;

    return LayoutBuilder(
      builder: (context, c) {
        final logoTop = c.maxHeight - _belowLogoTop;
        return GestureDetector(
          onTap: () => navigateToMediaItem(context, item),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AstraFramedArt(
                  imagePath: art,
                  client: client,
                  zoneHeight: logoTop + 70,
                  limitY: logoTop - 4,
                  topOffset: 20,
                  minTop: topInset + 56,
                ),
              ),
              Positioned(
                top: logoTop,
                left: 20,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (logo != null && logo.isNotEmpty)
                      ClearLogoImage(
                        client: logo.startsWith('http') ? null : client,
                        logoPath: logo,
                        width: _logoW,
                        height: _logoH,
                        fallbackWidth: c.maxWidth - 40,
                        alignment: Alignment.bottomCenter,
                        fallbackBuilder: (_) => _FallbackTitle(title),
                      )
                    else
                      SizedBox(height: _logoH, child: _FallbackTitle(title)),
                    const SizedBox(height: 14),
                    SizedBox(height: 42, child: Align(alignment: Alignment.topCenter, child: AstraHeroMeta.forItem(item))),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AstraWhitePlay(
                          width: 200,
                          height: 48,
                          onTap: () => navigateToMediaItem(context, item, playDirectly: !item.isCatalogItem),
                        ),
                        const SizedBox(width: 20),
                        AstraWatchlistCircle(item: item, size: 48),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FallbackTitle extends StatelessWidget {
  const _FallbackTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.bottomCenter, child: AstraTitleText(title, wide: false));
}

/// Mac / iPad hero: wide art with the copy on the left.
class _WideHeroPage extends StatelessWidget {
  const _WideHeroPage({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final client = context.getMediaClientForItemOrNull(item);
    final art = item.artPath ?? item.grandparentArtPath ?? item.thumbPath;
    final title = item.grandparentTitle ?? item.title ?? '';
    final logo = item.clearLogoPath;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (logo != null && logo.isNotEmpty)
          ClearLogoImage(
            client: logo.startsWith('http') ? null : client,
            logoPath: logo,
            width: 460,
            height: 150,
            fallbackWidth: 460,
            alignment: Alignment.bottomLeft,
            fallbackBuilder: (_) => AstraTitleText(title, wide: true),
          )
        else
          AstraTitleText(title, wide: true),
        const SizedBox(height: 16),
        AstraHeroMeta.forItem(item, center: false),
        if ((item.summary ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              item.summary!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AstraColors.ink.withValues(alpha: 0.85), fontSize: 14.5, height: 1.55),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AstraWhitePlay(width: 170, height: 48, onTap: () => navigateToMediaItem(context, item, playDirectly: !item.isCatalogItem)),
            const SizedBox(width: 18),
            AstraWatchlistCircle(item: item, size: 48),
          ],
        ),
      ],
    );

    return GestureDetector(
      onTap: () => navigateToMediaItem(context, item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art != null)
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (b) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.62, 1],
                colors: [Colors.black, Colors.black, Colors.transparent],
              ).createShader(b),
              child: OptimizedMediaImage(
                client: art.startsWith('http') ? null : client,
                imagePath: art,
                imageType: ImageType.art,
                fit: BoxFit.cover,
                alignment: const Alignment(0.4, -0.3),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                stops: [0, 0.38, 0.7],
                colors: [Color(0xCC0B0912), Color(0x660B0912), Color(0x000B0912)],
              ),
            ),
          ),
          Positioned(left: 156, bottom: 86, right: 40, child: Align(alignment: Alignment.bottomLeft, child: content)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- watchlist

/// The glass ✓ / + circle: adds or removes a title from the watchlist.
/// Titles that can't be matched to a watchlist open their details instead.
class AstraWatchlistCircle extends StatefulWidget {
  const AstraWatchlistCircle({super.key, required this.item, this.size = 48});
  final MediaItem item;
  final double size;

  @override
  State<AstraWatchlistCircle> createState() => _AstraWatchlistCircleState();
}

class _AstraWatchlistCircleState extends State<AstraWatchlistCircle> {
  CatalogSource? _src;

  @override
  void initState() {
    super.initState();
    _src = context.read<CatalogSourcesProvider>().watchlistCapableSource;
    _src?.watchlistChanges.addListener(_changed);
    if (_src != null) unawaited(_src!.ensureWatchlistLoaded());
  }

  @override
  void dispose() {
    _src?.watchlistChanges.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  MediaKind get _kind => widget.item.kind == MediaKind.show || widget.item.kind == MediaKind.season ? MediaKind.show : MediaKind.movie;

  Future<void> _toggle() async {
    final src = _src;
    final ids = widget.item.catalogItem?.ids;
    if (src == null || ids == null) {
      unawaited(navigateToMediaItem(context, widget.item));
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final ids = widget.item.catalogItem?.ids;
    final on = ids != null && _src?.isOnWatchlist(_kind, ids) == true;
    return AstraCircleButton(
      icon: on ? Icons.check_rounded : Icons.add_rounded,
      label: on ? 'Remove from My List' : 'Add to My List',
      size: widget.size,
      iconSize: widget.size * 0.46,
      onTap: _toggle,
    );
  }
}

// ---------------------------------------------------------------- rows & cards

class _RowHeader extends StatelessWidget {
  const _RowHeader({required this.title, required this.inset, this.trailing});
  final String title;
  final double inset;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AstraColors.ink, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
          ),
          if (trailing == null) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, color: AstraColors.ink, size: 24),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.inset, required this.height, required this.children});
  final String title;
  final double inset;
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RowHeader(title: title, inset: inset),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: inset),
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ],
      ),
    );
  }
}

/// Top 10 posters with big outlined rank numbers and a Movies / Series switch.
class _RankedRow extends StatefulWidget {
  const _RankedRow({required this.hub, required this.title, required this.inset, required this.wide});
  final MediaHub hub;
  final String title;
  final double inset;
  final bool wide;

  @override
  State<_RankedRow> createState() => _RankedRowState();
}

class _RankedRowState extends State<_RankedRow> {
  bool _shows = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.hub.items;
    final movies = all.where((i) => i.kind == MediaKind.movie).toList();
    final shows = all.where((i) => i.kind == MediaKind.show).toList();
    final hasBoth = movies.isNotEmpty && shows.isNotEmpty;
    final items = (hasBoth ? (_shows ? shows : movies) : all).take(10).toList();
    final posterW = widget.wide ? 132.0 : 104.0;
    final posterH = posterW * 1.5;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RowHeader(
            title: widget.title,
            inset: widget.inset,
            trailing: hasBoth
                ? AstraGlassSurface(
                    radius: 17,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Seg(label: 'Movies', on: !_shows, onTap: () => setState(() => _shows = false)),
                          _Seg(label: 'Series', on: _shows, onTap: () => setState(() => _shows = true)),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          SizedBox(
            height: posterH + 4,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: widget.inset - 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, i) => _RankedPoster(rank: i + 1, item: items[i], width: posterW, height: posterH),
            ),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFF4F2F8) : Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
        ),
        child: Text(
          label,
          style: TextStyle(color: on ? const Color(0xFF0B0912) : const Color(0xBFFFFFFF), fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

class _RankedPoster extends StatelessWidget {
  const _RankedPoster({required this.rank, required this.item, required this.width, required this.height});
  final int rank;
  final MediaItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final client = context.getMediaClientForItemOrNull(item);
    final poster = item.thumbPath;
    final numSize = height * 0.62;
    return _Pressable(
      semanticLabel: '$rank. ${item.title ?? ''}',
      onTap: () => navigateToMediaItem(context, item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Transform.translate(
            offset: Offset(12, numSize * 0.1),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: numSize,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -4,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2
                  ..color = const Color(0xD9FFFFFF),
              ),
            ),
          ),
          Container(
            width: width,
            height: height,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              child: poster == null
                  ? const ColoredBox(color: AstraColors.surface2)
                  : OptimizedMediaImage(
                      client: poster.startsWith('http') ? null : client,
                      imagePath: poster,
                      imageType: ImageType.poster,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child, this.semanticLabel});
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = _down = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.96 : (_hover ? 1.03 : 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Continue Watching: art with a glass play button, the title, what's left,
/// and a white progress bar.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.width, required this.height});
  final MediaItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final client = context.getMediaClientForItemOrNull(item);
    final art = item.grandparentArtPath ?? item.artPath ?? item.thumbPath;
    final progress = item.hasActiveProgress ? (item.viewOffsetMs! / item.durationMs!).clamp(0.0, 1.0) : 0.0;
    final title = item.grandparentTitle ?? item.title ?? '';
    final sub = _subtitle(item);
    return _Pressable(
      semanticLabel: title,
      onTap: () => navigateToMediaItem(context, item, playDirectly: true),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0x14FFFFFF)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (art != null)
                OptimizedMediaImage(client: client, imagePath: art, imageType: ImageType.art, fit: BoxFit.cover)
              else
                const ColoredBox(color: AstraColors.surface),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xC7000000)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              const Align(
                alignment: Alignment(0, -0.18),
                child: AstraGlassSurface(
                  radius: 20,
                  child: SizedBox(width: 40, height: 40, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24)),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: sub.isEmpty ? 22 : 38,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (sub.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 21,
                  child: Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 12),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(MediaItem item) {
    if (item.kind == MediaKind.episode && item.parentIndex != null && item.index != null) {
      final ep = 'S${item.parentIndex} · E${item.index}';
      final name = item.title ?? '';
      return name.isEmpty ? ep : '$ep · $name';
    }
    return astraContinueSubtitle(item);
  }
}

class _ArtCard extends StatelessWidget {
  const _ArtCard({required this.item, required this.width, required this.height});
  final MediaItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final client = context.getMediaClientForItemOrNull(item);
    final art = item.artPath ?? item.grandparentArtPath ?? item.thumbPath;
    final title = item.grandparentTitle ?? item.title ?? '';
    return _Pressable(
      semanticLabel: title,
      onTap: () => navigateToMediaItem(context, item),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              child: SizedBox(
                width: width,
                height: height,
                child: art != null
                    ? OptimizedMediaImage(client: client, imagePath: art, imageType: ImageType.art, fit: BoxFit.cover)
                    : const ColoredBox(color: AstraColors.surface),
              ),
            ),
            const SizedBox(height: 7),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AstraColors.ink, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 26)),
    ),
  );
}
