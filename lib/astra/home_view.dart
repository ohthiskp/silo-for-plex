import 'dart:async';

import 'package:flutter/material.dart';

import '../media/catalog_item_ref.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../widgets/optimized_media_image.dart';
import 'astra_style.dart';
import 'service_pill.dart';

/// Astra 3.0 home (iPhone, iPad and Mac): full-bleed hero with title logo,
/// the streaming switcher on top, then Continue Watching and artwork rows.
/// Apple TV keeps its own leanback home.
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
    final topInset = MediaQuery.paddingOf(context).top;
    final heroHeight = wide ? (size.height * 0.68).clamp(520.0, 760.0) : (size.height * 0.64).clamp(460.0, 620.0);
    final rowInset = wide ? 130.0 : 20.0;

    final rows = <Widget>[
      if (widget.continueWatching.isNotEmpty)
        _Row(
          title: 'Continue Watching',
          inset: rowInset,
          height: wide ? 168 : 132,
          children: [
            for (final item in widget.continueWatching)
              _ContinueCard(item: item, width: wide ? 262 : 214, height: wide ? 118 : 96),
          ],
        ),
      for (final hub in widget.hubs)
        if (hub.items.isNotEmpty)
          _Row(
            title: hub.title,
            inset: rowInset,
            height: wide ? 150 : 128,
            children: [for (final item in hub.items) _ArtCard(item: item, width: wide ? 180 : 150, height: wide ? 112 : 92)],
          ),
    ];

    return ColoredBox(
      color: AstraColors.bg,
      child: Stack(
        children: [
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
                SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 120)),
              ],
            ),
          ),
          // Top fade so the switcher stays readable over art while scrolling.
          IgnorePointer(
            child: Container(
              height: topInset + 90,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB307060B), Color(0x0007060B)],
                ),
              ),
            ),
          ),
          Positioned(
            top: topInset + (wide ? 22 : 8),
            left: wide ? 0 : 14,
            right: wide ? 0 : 14,
            child: wide
                ? const Center(child: AstraServicePill())
                : const AstraServicePill(compact: true),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- hero

class _Hero extends StatelessWidget {
  const _Hero({required this.items, required this.pages, required this.index, required this.wide, required this.onPage});
  final List<MediaItem> items;
  final PageController pages;
  final int index;
  final bool wide;
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
          itemBuilder: (context, i) => _HeroPage(item: items[i], wide: wide),
        ),
        Positioned(
          left: wide ? 130 : 0,
          right: wide ? null : 0,
          bottom: wide ? 48 : 18,
          child: IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3.5),
                    width: i == index ? 20 : 6,
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

class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.item, required this.wide});
  final MediaItem item;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final client = context.getMediaClientForItemOrNull(item);
    final art = item.artPath ?? item.grandparentArtPath ?? item.thumbPath;
    final title = item.grandparentTitle ?? item.title ?? '';
    final meta = astraMetaLine(item);
    final logo = item.clearLogoPath;
    final logoW = wide ? 460.0 : 290.0;
    final logoH = wide ? 150.0 : 104.0;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (logo != null && logo.isNotEmpty)
          ClearLogoImage(
            client: client,
            logoPath: logo,
            width: logoW,
            height: logoH,
            fallbackWidth: logoW,
            alignment: wide ? Alignment.bottomLeft : Alignment.bottomCenter,
            fallbackBuilder: (_) => AstraTitleText(title, wide: wide),
          )
        else
          AstraTitleText(title, wide: wide),
        const SizedBox(height: 16),
        if (meta.isNotEmpty)
          Text(
            meta,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: TextStyle(color: AstraColors.ink.withValues(alpha: 0.88), fontSize: wide ? 14 : 13, fontWeight: FontWeight.w500),
          ),
        if (wide && (item.summary ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              item.summary!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AstraColors.ink.withValues(alpha: 0.82), fontSize: 14.5, height: 1.55),
            ),
          ),
        ],
        SizedBox(height: wide ? 22 : 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AstraPlayButton(
              label: 'Play',
              purple: wide,
              width: wide ? null : 140,
              onTap: () => navigateToMediaItem(context, item, playDirectly: !item.isCatalogItem),
            ),
            const SizedBox(width: 12),
            AstraGlassButton(
              label: 'Details',
              icon: wide ? Icons.info_outline_rounded : null,
              width: wide ? null : 130,
              outlined: wide,
              onTap: () => navigateToMediaItem(context, item),
            ),
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
            OptimizedMediaImage(
              client: client,
              imagePath: art,
              imageType: ImageType.art,
              fit: BoxFit.cover,
              alignment: wide ? const Alignment(0.4, -0.3) : const Alignment(0.2, -0.4),
            )
          else
            const ColoredBox(color: AstraColors.surface),
          // Readability gradients: bottom on phones, left + bottom on wide.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0, 0.32, 0.62],
                colors: [AstraColors.bg, AstraColors.bg.withValues(alpha: wide ? 0.55 : 0.7), AstraColors.bg.withValues(alpha: 0)],
              ),
            ),
          ),
          if (wide)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, 0.38, 0.7],
                  colors: [AstraColors.bg.withValues(alpha: 0.92), AstraColors.bg.withValues(alpha: 0.5), AstraColors.bg.withValues(alpha: 0)],
                ),
              ),
            ),
          if (wide)
            Positioned(left: 130, bottom: 92, right: 40, child: Align(alignment: Alignment.bottomLeft, child: content))
          else
            Positioned(left: 20, right: 20, bottom: 40, child: content),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- rows & cards

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.inset, required this.height, required this.children});
  final String title;
  final double inset;
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 10),
            child: Row(
              children: [
                Text(title, style: const TextStyle(color: AstraColors.ink, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AstraColors.ink, size: 22),
              ],
            ),
          ),
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

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.width, required this.height});
  final MediaItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final client = context.getMediaClientForItemOrNull(item);
    final art = item.grandparentArtPath ?? item.artPath ?? item.thumbPath;
    final progress = item.hasActiveProgress ? item.viewOffsetMs! / item.durationMs! : 0.0;
    final title = item.grandparentTitle ?? item.title ?? '';
    final sub = astraContinueSubtitle(item);
    return _Pressable(
      semanticLabel: title,
      onTap: () => navigateToMediaItem(context, item, playDirectly: true),
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
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC000000), Color(0x00000000)],
                          stops: [0, 0.6],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.22),
                          color: AstraColors.purple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AstraColors.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AstraColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
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
              borderRadius: const BorderRadius.all(Radius.circular(10)),
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
