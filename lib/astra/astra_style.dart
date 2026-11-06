import 'dart:ui';

import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';

/// Astra 3.0 palette: near-black surfaces, soft white text, violet accent.
abstract final class AstraColors {
  static const bg = Color(0xFF07060B);
  static const surface = Color(0xFF15131D);
  static const surface2 = Color(0xFF1C1A26);
  static const ink = Color(0xFFF2F0F7);
  static const muted = Color(0xA8F2F0F7);
  static const purple = Color(0xFF7C4DFF);
  static const purpleLight = Color(0xFF9B74FF);
  static const hairline = Color(0x17FFFFFF);
}

String _runtime(int? ms) {
  if (ms == null || ms <= 0) return '';
  final m = (ms / 60000).round();
  final h = m ~/ 60;
  return h > 0 ? '${h}h ${m % 60}m' : '${m}m';
}

/// "2024 • PG-13 • 2h 46m • Sci-Fi, Adventure" (skips whatever is missing).
String astraMetaLine(MediaItem item, {int maxGenres = 2}) {
  final parts = <String>[
    if (item.year != null) '${item.year}',
    if ((item.contentRating ?? '').isNotEmpty) item.contentRating!,
    if (item.kind != MediaKind.show && _runtime(item.durationMs).isNotEmpty) _runtime(item.durationMs),
    if ((item.genres ?? const []).isNotEmpty) item.genres!.take(maxGenres).join(', '),
  ];
  return parts.join('  •  ');
}

/// "S2 • E4" or "1h 12m left".
String astraContinueSubtitle(MediaItem item) {
  if (item.kind == MediaKind.episode) {
    final s = item.parentIndex;
    final e = item.index;
    if (s != null && e != null) return 'S$s • E$e';
  }
  if (item.hasActiveProgress) {
    final left = _runtime(item.durationMs! - item.viewOffsetMs!);
    if (left.isNotEmpty) return '$left left';
  }
  return '';
}

/// Wide-tracked title used when a title has no logo artwork.
class AstraTitleText extends StatelessWidget {
  const AstraTitleText(this.title, {super.key, required this.wide});
  final String title;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      textAlign: wide ? TextAlign.start : TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AstraColors.ink,
        fontSize: wide ? 48 : 34,
        height: 1.05,
        fontWeight: FontWeight.w300,
        letterSpacing: wide ? 10 : 6,
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 3))],
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({required this.onTap, required this.child, required this.label});
  final VoidCallback onTap;
  final Widget child;
  final String label;
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Semantics(
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
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    ),
  );
}

/// Primary action: white pill on phones, violet pill on large screens.
class AstraPlayButton extends StatelessWidget {
  const AstraPlayButton({
    super.key,
    required this.label,
    required this.onTap,
    this.purple = true,
    this.width,
    this.icon = Icons.play_arrow_rounded,
    this.height = 46,
  });
  final String label;
  final VoidCallback onTap;
  final bool purple;
  final double? width;
  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = purple ? Colors.white : const Color(0xFF0B0912);
    return _PressScale(
      label: label,
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: purple
              ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8A5CFF), Color(0xFF7246F5)])
              : null,
          color: purple ? null : const Color(0xFFF4F2F8),
          borderRadius: BorderRadius.all(Radius.circular(height / 2)),
          boxShadow: [
            BoxShadow(
              color: purple ? const Color(0x667C4DFF) : const Color(0x55000000),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Secondary action: frosted glass pill (or outlined on large screens).
class AstraGlassButton extends StatelessWidget {
  const AstraGlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.width,
    this.outlined = false,
    this.height = 46,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final double? width;
  final bool outlined;
  final double height;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(height / 2)),
        border: Border.all(color: outlined ? const Color(0x52FFFFFF) : const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, color: Colors.white, size: 19), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return _PressScale(
      label: label,
      onTap: onTap,
      child: outlined
          ? inner
          : ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(height / 2)),
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: inner),
            ),
    );
  }
}

/// Frosted glass container for floating controls (tab bar, sidebar, pills).
class AstraGlass extends StatelessWidget {
  const AstraGlass({super.key, required this.child, this.radius = 999, this.padding = EdgeInsets.zero});
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x26FFFFFF), Color(0x0DFFFFFF)],
            ),
            color: const Color(0x66100E18),
            borderRadius: BorderRadius.all(Radius.circular(radius)),
            border: Border.all(color: const Color(0x24FFFFFF)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
