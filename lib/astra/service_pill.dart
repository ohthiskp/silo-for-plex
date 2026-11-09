import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'astra_art.dart';
import 'astra_home.dart';
import 'streaming_services.dart';

/// The row of separate glass pills at the top of Home: "For You" plus each
/// streaming service. Logos are white; the selected service shows its logo
/// in its real color on brighter glass. Scrolls sideways when it doesn't fit.
class AstraServicePill extends StatelessWidget {
  const AstraServicePill({super.key, this.compact = false, this.padding = EdgeInsets.zero});

  /// Phone sizing.
  final bool compact;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final home = AstraHome.instance;
    final h = compact ? 38.0 : 42.0;
    return ListenableBuilder(
      listenable: home,
      builder: (context, _) {
        final pills = <Widget>[
          _Pill(
            selected: home.isForYou,
            white: true,
            height: h,
            semanticLabel: 'For You',
            onTap: () => home.select(null),
            padding: EdgeInsets.symmetric(horizontal: compact ? 17 : 20),
            child: Text(
              'For You',
              style: TextStyle(
                color: home.isForYou ? const Color(0xFF0B0912) : Colors.white,
                fontSize: compact ? 14.5 : 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ),
          for (final s in streamingServices)
            _Pill(
              selected: home.serviceId == s.id,
              height: h,
              minWidth: compact ? 82 : 96,
              semanticLabel: s.label,
              onTap: () => home.select(s.id),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _Logo(
                service: s,
                color: home.serviceId == s.id ? Color(s.brandColor) : Colors.white,
                scale: compact ? 0.86 : 1,
              ),
            ),
        ];
        return SizedBox(
          height: h + 16,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            padding: padding.add(const EdgeInsets.symmetric(vertical: 8)),
            itemCount: pills.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => pills[i],
          ),
        );
      },
    );
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

class _Pill extends StatefulWidget {
  const _Pill({
    required this.selected,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
    required this.height,
    required this.padding,
    this.minWidth = 0,
    this.white = false,
  });
  final bool selected;

  /// Selected look is a solid white pill ("For You") instead of bright glass.
  final bool white;
  final VoidCallback onTap;
  final Widget child;
  final String semanticLabel;
  final double height;
  final double minWidth;
  final EdgeInsets padding;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final content = ConstrainedBox(
      constraints: BoxConstraints(minWidth: widget.minWidth, minHeight: widget.height, maxHeight: widget.height),
      child: Padding(
        padding: widget.padding,
        child: Center(widthFactor: 1, child: widget.child),
      ),
    );
    return Semantics(
      button: true,
      selected: sel,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
            child: widget.white && sel
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F2F8),
                      borderRadius: BorderRadius.all(Radius.circular(widget.height / 2)),
                      boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    child: content,
                  )
                : AstraGlassSurface(radius: widget.height / 2, strong: sel, child: content),
          ),
        ),
      ),
    );
  }
}
