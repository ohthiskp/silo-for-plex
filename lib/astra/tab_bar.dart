import 'dart:ui';

import 'package:flutter/material.dart';

import '../navigation/navigation_tabs.dart';
import 'astra_style.dart';

/// Astra 3.0 iPhone tab bar: a floating liquid-glass capsule with Home,
/// Search and Downloads, and a Settings button at the far right.
class AstraTabBar extends StatelessWidget {
  const AstraTabBar({super.key, required this.current, required this.onSelect, required this.onSettings});

  final NavigationTabId current;
  final ValueChanged<NavigationTabId> onSelect;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final items = <(NavigationTabId, IconData, IconData, String)>[
      (NavigationTabId.discover, Icons.home_outlined, Icons.home_rounded, 'Home'),
      (NavigationTabId.search, Icons.search_rounded, Icons.search_rounded, 'Search'),
      (NavigationTabId.downloads, Icons.download_outlined, Icons.download_rounded, 'Downloads'),
    ];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: LiquidGlass(
              radius: 34,
              child: SizedBox(
                height: 66,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final (id, icon, iconOn, label) in items)
                      _Tab(
                        selected: current == id,
                        icon: current == id ? iconOn : icon,
                        label: label,
                        onTap: () => onSelect(id),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Settings',
            selected: current == NavigationTabId.settings,
            child: GestureDetector(
              onTap: onSettings,
              child: const LiquidGlass(
                radius: 33,
                child: SizedBox(width: 66, height: 66, child: Icon(Icons.settings_outlined, color: Colors.white, size: 26)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.selected, required this.icon, required this.label, required this.onTap});
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return Semantics(
      button: true,
      selected: sel,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: 88,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(27)),
              gradient: sel
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33FFFFFF), Color(0x14FFFFFF)],
                    )
                  : null,
              border: sel ? Border.all(color: const Color(0x2EFFFFFF)) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 24, color: sel ? Colors.white : AstraColors.muted),
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : AstraColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Liquid-glass material: strong blur with boosted saturation of what's
/// behind, a bright specular rim on top, a soft inner glow and a drop shadow.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({super.key, required this.child, this.radius = 999});
  final Widget child;
  final double radius;

  static final ImageFilter _filter = ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
    inner: const ColorFilter.matrix(<double>[
      // ~1.8x saturation
      1.5, -0.42, -0.08, 0, 0,
      -0.12, 1.24, -0.12, 0, 0,
      -0.12, -0.42, 1.54, 0, 0,
      0, 0, 0, 1, 0,
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.all(Radius.circular(radius));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: _filter,
          child: Stack(
            children: [
              // Body tint
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: r,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x38FFFFFF), Color(0x12FFFFFF), Color(0x1FFFFFFF)],
                      stops: [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              // Specular rim: bright on top, fading down the sides
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _RimPainter(radius)),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.6), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xB3FFFFFF), Color(0x26FFFFFF), Color(0x14FFFFFF), Color(0x40FFFFFF)],
        stops: [0, 0.35, 0.7, 1],
      ).createShader(rect);
    canvas.drawRRect(rr, paint);
    // Inner top glow
    final glow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(1.5), Radius.circular(radius)), glow);
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) => old.radius != radius;
}
