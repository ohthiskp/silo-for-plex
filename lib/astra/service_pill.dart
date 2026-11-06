import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'astra_home.dart';
import 'streaming_services.dart';

/// The floating glass switcher at the top of Home: "For You" plus each
/// streaming service's logo. Logos are tinted white on the glass and dark on
/// the selected chip. Scrolls sideways when it doesn't fit (phones).
class AstraServicePill extends StatelessWidget {
  const AstraServicePill({super.key, this.compact = false});

  /// Smaller chips for phones.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final home = AstraHome.instance;
    return ListenableBuilder(
      listenable: home,
      builder: (context, _) {
        final chips = <Widget>[
          _Chip(
            selected: home.isForYou,
            compact: compact,
            semanticLabel: 'For You',
            onTap: () => home.select(null),
            builder: (color) => Text(
              'For You',
              style: TextStyle(color: color, fontSize: compact ? 14 : 15, fontWeight: FontWeight.w700, letterSpacing: -0.1),
            ),
          ),
          for (final s in streamingServices)
            _Chip(
              selected: home.serviceId == s.id,
              compact: compact,
              semanticLabel: s.label,
              onTap: () => home.select(s.id),
              builder: (color) => _Logo(service: s, color: color, scale: compact ? 0.86 : 1),
            ),
        ];
        return ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.04)],
                ),
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 4 : 5),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: _withDividers(chips, home)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _withDividers(List<Widget> chips, AstraHome home) {
    final out = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      if (i > 1) {
        // A hairline between services, hidden next to the selected chip.
        final prevSelected = i - 1 == 0 ? home.isForYou : home.serviceId == streamingServices[i - 2].id;
        final thisSelected = home.serviceId == streamingServices[i - 1].id;
        out.add(
          Container(
            width: 1,
            height: compact ? 16 : 20,
            color: Colors.white.withValues(alpha: prevSelected || thisSelected ? 0 : 0.16),
          ),
        );
      }
      out.add(chips[i]);
    }
    return out;
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.service, required this.color, required this.scale});
  final StreamingService service;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final h = service.logoHeight * scale;
    if (service.isSvg) {
      return SvgPicture.asset(
        service.logoAsset,
        height: h,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        excludeFromSemantics: true,
      );
    }
    return Image.asset(service.logoAsset, height: h, color: color, colorBlendMode: BlendMode.srcIn, excludeFromSemantics: true);
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.selected,
    required this.onTap,
    required this.builder,
    required this.semanticLabel,
    required this.compact,
  });
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget Function(Color color) builder;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final fg = sel ? const Color(0xFF0B0912) : Colors.white.withValues(alpha: _hover ? 1 : 0.9);
    return Semantics(
      button: true,
      selected: sel,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = _down = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.94 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              height: widget.compact ? 34 : 40,
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel
                    ? const Color(0xF0F4F2F8)
                    : _hover
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                boxShadow: sel
                    ? const [BoxShadow(color: Color(0x4D000000), blurRadius: 14, offset: Offset(0, 4))]
                    : const [],
              ),
              child: widget.builder(fg),
            ),
          ),
        ),
      ),
    );
  }
}
