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

  static const double collapsedWidth = 96;
  static const double expandedWidth = 220;

  @override
  State<AstraSidebar> createState() => _AstraSidebarState();
}

class _AstraSidebarState extends State<AstraSidebar> {

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

    // Exactly the prototype: Home, Discover, Movies, TV Shows, Watchlist,
    // Library, then Settings at the bottom.
    final items = <_Item>[
      _Item(Icons.search_rounded, 'Search', widget.currentTab == NavigationTabId.search, () => widget.onSelectTab(NavigationTabId.search)),
      _Item(Icons.home_outlined, 'Home', widget.currentTab == NavigationTabId.discover, () => widget.onSelectTab(NavigationTabId.discover)),
      _Item(
        Icons.explore_outlined,
        'Discover',
        widget.currentTab == NavigationTabId.explore,
        () => widget.onSelectTab(widget.hasExplore ? NavigationTabId.explore : NavigationTabId.search),
      ),
      _Item(Icons.movie_outlined, 'Movies', isLibraryKind(MediaKind.movie), () {
        if (movies != null) widget.onSelectLibrary(movies);
      }),
      _Item(Icons.tv_rounded, 'TV Shows', isLibraryKind(MediaKind.show), () {
        if (shows != null) widget.onSelectLibrary(shows);
      }),
      _Item(
        Icons.bookmark_border_rounded,
        'Watchlist',
        widget.hasExplore && widget.currentTab == NavigationTabId.explore,
        () => widget.onSelectTab(widget.hasExplore ? NavigationTabId.explore : NavigationTabId.discover),
      ),
      _Item(
        Icons.layers_outlined,
        'Library',
        widget.currentTab == NavigationTabId.libraries && !isLibraryKind(MediaKind.movie) && !isLibraryKind(MediaKind.show),
        () => widget.onSelectTab(NavigationTabId.libraries),
      ),
    ];
    final settings = _Item(Icons.settings_outlined, 'Settings', widget.currentTab == NavigationTabId.settings, () => widget.onSelectTab(NavigationTabId.settings));

    // Docked dark panel, icons only, exactly like the approved Mac design.
    return Container(
      width: AstraSidebar.collapsedWidth,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16141E), Color(0xFF0E0D14)],
        ),
        borderRadius: BorderRadius.horizontal(right: Radius.circular(30)),
        border: Border(right: BorderSide(color: Color(0x14FFFFFF))),
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(6, 0))],
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 70, 11, 24),
          child: Column(
            children: [
              for (final i in items) _NavButton(item: i, expanded: false),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                child: Divider(height: 1, thickness: 1, color: Color(0x24FFFFFF)),
              ),
              _NavButton(item: settings, expanded: false),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        button: true,
        selected: sel,
        label: widget.item.label,
        excludeSemantics: true,
        child: Tooltip(
          message: widget.item.label,
          waitDuration: const Duration(milliseconds: 600),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: widget.item.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 74,
                height: 58,
                decoration: BoxDecoration(
                  color: sel
                      ? const Color(0x29FFFFFF)
                      : _hover
                      ? const Color(0x12FFFFFF)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                ),
                child: Icon(widget.item.icon, size: 26, color: Colors.white.withValues(alpha: sel || _hover ? 1 : 0.82)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
