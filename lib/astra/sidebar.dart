import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/media_kind.dart';
import '../navigation/navigation_tabs.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import 'astra_style.dart';

/// Astra 3.0 Mac/iPad sidebar from the approved prototype: a floating glass
/// column of icons that widens on hover to show labels. Content runs under it.
class AstraSidebar extends StatefulWidget {
  const AstraSidebar({
    super.key,
    required this.currentTab,
    required this.selectedLibraryKey,
    required this.onSelectTab,
    required this.onSelectLibrary,
    required this.hasExplore,
  });

  final NavigationTabId currentTab;
  final String? selectedLibraryKey;
  final ValueChanged<NavigationTabId> onSelectTab;
  final ValueChanged<String> onSelectLibrary;
  final bool hasExplore;

  static const double collapsedWidth = 72;
  static const double expandedWidth = 220;

  @override
  State<AstraSidebar> createState() => _AstraSidebarState();
}

class _AstraSidebarState extends State<AstraSidebar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final libraries = context.watch<LibrariesProvider>().libraries;
    final hidden = context.watch<HiddenLibrariesProvider>().hiddenLibraryKeys;
    String? firstOf(MediaKind kind) {
      for (final l in libraries) {
        if (l.kind == kind && !hidden.contains(l.globalKey)) return l.globalKey;
      }
      return null;
    }

    bool isLibraryKind(MediaKind kind) {
      if (widget.currentTab != NavigationTabId.libraries) return false;
      for (final l in libraries) {
        if (l.globalKey == widget.selectedLibraryKey) return l.kind == kind;
      }
      return false;
    }

    final movies = firstOf(MediaKind.movie);
    final shows = firstOf(MediaKind.show);

    final items = <_Item>[
      _Item(Icons.search_rounded, 'Search', widget.currentTab == NavigationTabId.search, () => widget.onSelectTab(NavigationTabId.search)),
      _Item(Icons.home_rounded, 'Home', widget.currentTab == NavigationTabId.discover, () => widget.onSelectTab(NavigationTabId.discover)),
      if (widget.hasExplore)
        _Item(Icons.explore_outlined, 'Discover', widget.currentTab == NavigationTabId.explore, () => widget.onSelectTab(NavigationTabId.explore)),
      if (movies != null) _Item(Icons.movie_outlined, 'Movies', isLibraryKind(MediaKind.movie), () => widget.onSelectLibrary(movies)),
      if (shows != null) _Item(Icons.tv_rounded, 'TV Shows', isLibraryKind(MediaKind.show), () => widget.onSelectLibrary(shows)),
      _Item(
        Icons.layers_outlined,
        'Library',
        widget.currentTab == NavigationTabId.libraries && !isLibraryKind(MediaKind.movie) && !isLibraryKind(MediaKind.show),
        () => widget.onSelectTab(NavigationTabId.libraries),
      ),
      _Item(Icons.download_outlined, 'Downloads', widget.currentTab == NavigationTabId.downloads, () => widget.onSelectTab(NavigationTabId.downloads)),
    ];
    final settings = _Item(Icons.settings_outlined, 'Settings', widget.currentTab == NavigationTabId.settings, () => widget.onSelectTab(NavigationTabId.settings));

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: _hover ? AstraSidebar.expandedWidth : AstraSidebar.collapsedWidth,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(36)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 18))],
        ),
        child: AstraGlass(
          radius: 36,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final i in items) _NavButton(item: i, expanded: _hover),
              const SizedBox(height: 40),
              _NavButton(item: settings, expanded: _hover),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item {
  const _Item(this.icon, this.label, this.selected, this.onTap);
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

class _NavButton extends StatefulWidget {
  const _NavButton({required this.item, required this.expanded});
  final _Item item;
  final bool expanded;
  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.item.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Semantics(
        button: true,
        selected: sel,
        label: widget.item.label,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.item.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 46,
              decoration: BoxDecoration(
                color: sel
                    ? const Color(0x2BFFFFFF)
                    : _hover
                    ? const Color(0x14FFFFFF)
                    : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(15)),
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: AstraSidebar.expandedWidth - 24,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Icon(widget.item.icon, size: 23, color: sel || _hover ? Colors.white : AstraColors.muted),
                      ),
                      AnimatedOpacity(
                        opacity: widget.expanded ? 1 : 0,
                        duration: Duration(milliseconds: widget.expanded ? 220 : 90),
                        child: Text(
                          widget.item.label,
                          maxLines: 1,
                          style: TextStyle(
                            color: sel ? Colors.white : AstraColors.ink.withValues(alpha: 0.85),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
