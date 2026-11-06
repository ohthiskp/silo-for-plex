import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../navigation/main_screen_scope.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';

/// Astra's floating pill switcher over the home hero: "For You" plus the
/// movie and TV libraries, glass over the artwork. "For You" is the page
/// it sits on, so it is always the selected pill; the others open their
/// library through the main screen's [MainScreenFocusScope.selectLibrary].
class AstraTopTabs extends StatelessWidget {
  const AstraTopTabs({super.key, required this.forYouLabel, this.maxLibraries = 4});

  final String forYouLabel;
  final int maxLibraries;

  @override
  Widget build(BuildContext context) {
    final libraries = context.watch<LibrariesProvider>().libraries;
    final hidden = context.watch<HiddenLibrariesProvider>().hiddenLibraryKeys;
    final visible = <MediaLibrary>[
      for (final lib in libraries)
        if (!hidden.contains(lib.globalKey) && (lib.kind == MediaKind.movie || lib.kind == MediaKind.show)) lib,
    ].take(maxLibraries).toList();
    final selectLibrary = MainScreenFocusScope.of(context, listen: false)?.selectLibrary;

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AstraPill(label: forYouLabel, selected: true, onTap: null),
                  for (final lib in visible)
                    _AstraPill(
                      label: lib.title,
                      selected: false,
                      onTap: selectLibrary == null ? null : () => selectLibrary(lib.globalKey),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AstraPill extends StatefulWidget {
  const _AstraPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_AstraPill> createState() => _AstraPillState();
}

class _AstraPillState extends State<_AstraPill> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? Colors.white
        : _hovered
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.transparent;
    final fg = selected
        ? const Color(0xFF05070D)
        : Colors.white.withValues(alpha: _hovered ? 1.0 : 0.78);

    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: MouseRegion(
        cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(999))),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
