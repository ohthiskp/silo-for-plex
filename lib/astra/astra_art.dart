import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../utils/media_image_helper.dart';
import '../widgets/optimized_media_image.dart';
import 'art_focus.dart';
import 'astra_style.dart';

// ---------------------------------------------------------------- art

/// The sharp backdrop at the top of Home and Details. It is framed so the
/// faces (or main subject) end above the title logo, and fades out at the
/// bottom into the frosted page background.
class AstraFramedArt extends StatefulWidget {
  const AstraFramedArt({
    super.key,
    required this.imagePath,
    required this.client,
    required this.zoneHeight,
    required this.limitY,
    this.topOffset = 20,
    this.minTop = 40,
    this.fadeStart = 0.64,
  });

  final String? imagePath;
  final MediaServerClient? client;

  /// Height of the art area.
  final double zoneHeight;

  /// The faces must end above this y (the top of the logo slot).
  final double limitY;

  /// Where the image starts by default (leaves room for the top blur).
  final double topOffset;

  /// How far the image may slide up while keeping faces on screen.
  final double minTop;

  /// Fraction of [zoneHeight] where the fade to the background starts.
  final double fadeStart;

  @override
  State<AstraFramedArt> createState() => _AstraFramedArtState();
}

class _AstraFramedArtState extends State<AstraFramedArt> {
  ArtFocus? _focus;
  String? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant AstraFramedArt old) {
    super.didUpdateWidget(old);
    if (old.imagePath != widget.imagePath) _resolve();
  }

  void _resolve() {
    final path = widget.imagePath;
    if (path == null || path.isEmpty) return;
    final url = MediaImageHelper.getOptimizedImageUrl(
      client: widget.client,
      thumbPath: path,
      maxWidth: 780,
      maxHeight: 440,
      pixelRatio: 1,
      imageType: ImageType.art,
    );
    if (url == _url) return;
    _url = url;
    final service = ArtFocusService.instance;
    _focus = service.peek(url);
    if (_focus == null) {
      unawaited(
        service.focusFor(url).then((f) {
          if (mounted && f != null && _url == url) setState(() => _focus = f);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.imagePath;
    if (path == null || path.isEmpty) return SizedBox(height: widget.zoneHeight);
    return SizedBox(
      height: widget.zoneHeight,
      child: LayoutBuilder(
        builder: (context, c) {
          final rect = frameArt(
            boxWidth: c.maxWidth,
            zoneHeight: widget.zoneHeight,
            aspect: _focus?.aspect ?? 16 / 9,
            limitY: widget.limitY,
            topOffset: widget.topOffset,
            minTop: widget.minTop,
            focus: _focus?.focus,
            fallbackX: 0.5,
          );
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, widget.fadeStart, (widget.fadeStart + 1) / 2, 1],
              colors: const [Colors.black, Colors.black, Color(0x8C000000), Colors.transparent],
            ).createShader(bounds),
            child: ClipRect(
              child: Stack(
                children: [
                  AnimatedPositioned.fromRect(
                    rect: rect,
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    child: OptimizedMediaImage(
                      client: widget.client,
                      imagePath: path,
                      imageType: ImageType.art,
                      fit: BoxFit.cover,
                      width: rect.width,
                      height: rect.height,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The page background: the same artwork, heavily blurred and darkened, so
/// everything below the hero sits on frosted glass instead of flat black.
class AstraFrostedBackground extends StatelessWidget {
  const AstraFrostedBackground({super.key, required this.imagePath, required this.client});
  final String? imagePath;
  final MediaServerClient? client;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF100C1C)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          child: path == null || path.isEmpty
              ? const SizedBox.expand()
              : ImageFiltered(
                  key: ValueKey(path),
                  imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.clamp),
                  child: Transform.scale(
                    scale: 1.3,
                    child: OptimizedMediaImage(
                      client: client,
                      imagePath: path,
                      imageType: ImageType.art,
                      fit: BoxFit.cover,
                      width: 320,
                      height: 180,
                      alignment: const Alignment(0, -0.4),
                    ),
                  ),
                ),
        ),
        // Darken and keep the glass calm toward the bottom.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x4D0E0A1A), Color(0x8C0E0A1A), Color(0xB30A0812)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment(0.2, 0.2),
              colors: [Color(0x0FFFFFFF), Color(0x00FFFFFF)],
            ),
          ),
        ),
      ],
    );
  }
}

/// A soft, progressive blur along the top or bottom edge, so floating
/// controls stay readable over busy art and scrolling content.
class AstraEdgeBlur extends StatelessWidget {
  const AstraEdgeBlur({super.key, required this.height, this.top = true, this.tint = 0.6});
  final double height;
  final bool top;

  /// Opacity of the dark tint at the edge.
  final double tint;

  @override
  Widget build(BuildContext context) {
    // Stacked bands, strongest at the edge, approximate a gradient blur.
    const bands = [(1.0, 5.0), (0.7, 7.0), (0.42, 9.0)];
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            for (final (f, sigma) in bands)
              Positioned(
                left: 0,
                right: 0,
                top: top ? 0 : null,
                bottom: top ? null : 0,
                height: height * f,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                    end: top ? Alignment.bottomCenter : Alignment.topCenter,
                    colors: [
                      Color.fromRGBO(8, 6, 14, tint),
                      Color.fromRGBO(8, 6, 14, tint * 0.65),
                      const Color.fromRGBO(8, 6, 14, 0),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- meta

/// "4K" / "HD" for a server copy, from its Plex media info.
String? astraResolution(MediaItem? item) {
  final media = item?.raw?['Media'];
  if (media is! List) return null;
  var best = 0;
  for (final m in media.whereType<Map>()) {
    final r = '${m['videoResolution']}'.toLowerCase();
    final v = r == '4k' ? 2160 : int.tryParse(r) ?? 0;
    if (v > best) best = v;
  }
  if (best >= 2000) return '4K';
  if (best >= 720) return 'HD';
  return best > 0 ? 'SD' : null;
}

bool _streamsMatch(MediaItem? item, bool Function(Map s) test) {
  final media = item?.raw?['Media'];
  if (media is! List) return false;
  for (final m in media.whereType<Map>()) {
    final parts = m['Part'];
    if (parts is! List) continue;
    for (final p in parts.whereType<Map>()) {
      final streams = p['Stream'];
      if (streams is List && streams.whereType<Map>().any(test)) return true;
    }
  }
  return false;
}

bool astraHasAtmos(MediaItem? item) =>
    _streamsMatch(item, (s) => '${s['displayTitle'] ?? ''} ${s['extendedDisplayTitle'] ?? ''}'.toLowerCase().contains('atmos'));

bool astraHasDolbyVision(MediaItem? item) => _streamsMatch(item, (s) => s['DOVIPresent'] == true || s['DOVIPresent'] == '1');

String astraRuntime(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  return minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m';
}

/// Small box badge: grey filled for the content rating, outlined for the rest.
class AstraBadge extends StatelessWidget {
  const AstraBadge(this.label, {super.key, this.filled = false, this.atmos = false});
  final String label;
  final bool filled;
  final bool atmos;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? const Color(0x38FFFFFF) : null,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        border: filled ? null : Border.all(color: const Color(0x80FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (atmos) ...[
            const Icon(Icons.view_agenda_rounded, size: 10, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: filled ? const Color(0xE6F4F2F8) : Colors.white,
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// "2026 • 1h 41m • [PG] [HD]" with the genres on a line below, centered.
class AstraHeroMeta extends StatelessWidget {
  const AstraHeroMeta({
    super.key,
    this.year,
    this.length,
    this.rating,
    this.resolution,
    this.atmos = false,
    this.dolbyVision = false,
    this.genres = const [],
    this.center = true,
  });

  final int? year;
  final String? length;
  final String? rating;
  final String? resolution;
  final bool atmos;
  final bool dolbyVision;
  final List<String> genres;
  final bool center;

  factory AstraHeroMeta.forItem(MediaItem item, {MediaItem? library, bool center = true}) {
    final minutes = item.durationMs == null ? null : (item.durationMs! / 60000).round();
    return AstraHeroMeta(
      year: item.year,
      length: item.kind == MediaKind.show ? null : astraRuntime(minutes),
      rating: item.contentRating,
      resolution: astraResolution(library ?? item),
      atmos: astraHasAtmos(library ?? item),
      dolbyVision: astraHasDolbyVision(library ?? item),
      genres: item.genres ?? const [],
      center: center,
    );
  }

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x80000000), blurRadius: 8)];
    const style = TextStyle(color: Color(0xD9F4F2F8), fontSize: 13, fontWeight: FontWeight.w500, shadows: shadow);
    const dot = Text('•', style: TextStyle(color: Color(0x80F4F2F8), fontSize: 13));
    final text = <Widget>[
      if (year != null) Text('$year', style: style),
      if ((length ?? '').isNotEmpty) Text(length!, style: style),
    ];
    final badges = <Widget>[
      if ((rating ?? '').isNotEmpty) AstraBadge(rating!, filled: true),
      if (resolution != null) AstraBadge(resolution!),
      if (dolbyVision) const AstraBadge('DOLBY VISION'),
      if (atmos) const AstraBadge('DOLBY ATMOS', atmos: true),
    ];
    final line = <Widget>[];
    for (var i = 0; i < text.length; i++) {
      if (i > 0) line.add(dot);
      line.add(text[i]);
    }
    if (badges.isNotEmpty) {
      if (line.isNotEmpty) line.add(dot);
      line.addAll(badges);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: center ? WrapAlignment.center : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 7,
          runSpacing: 6,
          children: line,
        ),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            genres.take(3).join(' · '),
            textAlign: center ? TextAlign.center : TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0x9EF4F2F8), fontSize: 13, shadows: shadow),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- controls

/// Round frosted-glass icon button (✓, ↓, back, more).
class AstraCircleButton extends StatefulWidget {
  const AstraCircleButton({super.key, required this.icon, required this.label, required this.onTap, this.size = 48, this.iconSize = 22});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  State<AstraCircleButton> createState() => _AstraCircleButtonState();
}

class _AstraCircleButtonState extends State<AstraCircleButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.92 : 1,
            duration: const Duration(milliseconds: 120),
            child: AstraGlassSurface(
              radius: s / 2,
              child: SizedBox(width: s, height: s, child: Icon(widget.icon, color: Colors.white, size: widget.iconSize)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Light frosted glass with a bright top rim, used by pills and circles.
class AstraGlassSurface extends StatelessWidget {
  const AstraGlassSurface({super.key, required this.child, this.radius = 999, this.strong = false});
  final Widget child;
  final double radius;

  /// Brighter fill and a white ring (the selected state).
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.all(Radius.circular(radius));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: strong ? const [Color(0x57FFFFFF), Color(0x29FFFFFF)] : const [Color(0x33FFFFFF), Color(0x17FFFFFF)],
              ),
              border: Border.all(color: strong ? const Color(0x8CFFFFFF) : const Color(0x24FFFFFF), width: strong ? 1.5 : 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// White pill Play button.
class AstraWhitePlay extends StatelessWidget {
  const AstraWhitePlay({super.key, required this.onTap, this.label = 'Play', this.icon = Icons.play_arrow_rounded, this.width, this.height = 48});
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AstraPlayButton(label: label, icon: icon, purple: false, width: width, height: height, onTap: onTap);
  }
}
