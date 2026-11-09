import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the important part of a backdrop is: the faces when Apple Vision
/// finds any, otherwise its most eye-catching subject.
@immutable
class ArtFocus {
  const ArtFocus({required this.aspect, this.focus, this.fromFaces = false});

  /// Image width / height.
  final double aspect;

  /// Normalized rect (0..1, top-left origin), or null when nothing was found.
  final Rect? focus;
  final bool fromFaces;

  Map<String, Object?> toJson() => {
    'a': aspect,
    if (focus != null) 'f': [focus!.left, focus!.top, focus!.width, focus!.height],
    'faces': fromFaces,
  };

  static ArtFocus? fromJson(Object? json) {
    if (json is! Map) return null;
    final a = (json['a'] as num?)?.toDouble();
    if (a == null || a <= 0) return null;
    final f = json['f'];
    Rect? rect;
    if (f is List && f.length == 4) {
      final v = [for (final n in f) (n as num).toDouble()];
      rect = Rect.fromLTWH(v[0], v[1], v[2], v[3]);
    }
    return ArtFocus(aspect: a, focus: rect, fromFaces: json['faces'] == true);
  }
}

/// Runs the native Vision analysis once per image and remembers the result,
/// so a title's art is framed the same way, instantly, every time after.
class ArtFocusService {
  ArtFocusService._();
  static final ArtFocusService instance = ArtFocusService._();

  static const _channel = MethodChannel('astra/art_focus');
  static const _prefsKey = 'astra_art_focus_v1';
  static const _maxEntries = 400;

  final Map<String, ArtFocus> _memory = {};
  final Map<String, Future<ArtFocus?>> _pending = {};
  Future<void>? _restored;
  bool _unsupported = false;

  bool get supported => !kIsWeb && (Platform.isIOS || Platform.isMacOS) && !_unsupported;

  /// Cached result for [url], if it has been analyzed before.
  ArtFocus? peek(String url) => _memory[_key(url)];

  /// A small copy of a TMDB image is plenty for finding faces.
  static String analysisUrl(String url) => url.replaceFirst(RegExp(r'/t/p/(original|w\d+)/'), '/t/p/w780/');

  static String _key(String url) {
    final m = RegExp(r'/t/p/[^/]+/(.+)$').firstMatch(url);
    if (m != null) return 'tmdb:${m.group(1)}';
    // Plex URLs carry tokens and sizes; key on the path only.
    final uri = Uri.tryParse(url);
    final inner = uri?.queryParameters['url'];
    return inner ?? uri?.path ?? url;
  }

  Future<void> _restore() => _restored ??= () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      for (final e in map.entries) {
        final f = ArtFocus.fromJson(e.value);
        if (f != null) _memory.putIfAbsent(e.key as String, () => f);
      }
    } catch (_) {}
  }();

  Timer? _saveTimer;
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final entries = _memory.entries.toList();
        final keep = entries.length > _maxEntries ? entries.sublist(entries.length - _maxEntries) : entries;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode({for (final e in keep) e.key: e.value.toJson()}));
      } catch (_) {}
    });
  }

  /// Analyzes [url] (an absolute image URL) or returns the cached result.
  Future<ArtFocus?> focusFor(String url) async {
    if (!supported || url.isEmpty || !url.startsWith('http')) return null;
    await _restore();
    final key = _key(url);
    final hit = _memory[key];
    if (hit != null) return hit;
    return _pending[key] ??= _analyze(analysisUrl(url), key).whenComplete(() => _pending.remove(key));
  }

  Future<ArtFocus?> _analyze(String url, String key) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>('analyze', {'url': url});
      if (res == null) return null;
      final w = (res['width'] as num?)?.toDouble() ?? 0;
      final h = (res['height'] as num?)?.toDouble() ?? 0;
      if (w <= 0 || h <= 0) return null;
      final faces = _rects(res['faces']);
      final salient = _rects(res['salient']);
      Rect? focus;
      var fromFaces = false;
      if (faces.isNotEmpty) {
        focus = faces.reduce((a, b) => a.expandToInclude(b));
        fromFaces = true;
      } else if (salient.isNotEmpty) {
        focus = salient.reduce((a, b) => a.expandToInclude(b));
      }
      final result = ArtFocus(aspect: w / h, focus: focus, fromFaces: fromFaces);
      _memory[key] = result;
      _scheduleSave();
      return result;
    } on MissingPluginException {
      _unsupported = true;
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<Rect> _rects(Object? raw) => [
    if (raw is List)
      for (final r in raw)
        if (r is List && r.length == 4)
          Rect.fromLTWH((r[0] as num).toDouble(), (r[1] as num).toDouble(), (r[2] as num).toDouble(), (r[3] as num).toDouble()),
  ];
}

/// Where to draw an image of [aspect] inside a box of [boxWidth] x [zoneHeight]
/// so the [focus] area ends above [limitY] (the top of the title logo) and is
/// centered across. Falls back to a plain top-anchored cover crop.
Rect frameArt({
  required double boxWidth,
  required double zoneHeight,
  required double aspect,
  required double limitY,
  double topOffset = 0,
  double minTop = -double.infinity,
  Rect? focus,
  double fallbackX = 0.5,
}) {
  // Cover the zone by default.
  var height = math.max(zoneHeight - topOffset, boxWidth / aspect);
  var top = topOffset;
  if (focus != null && focus.bottom > 0) {
    // Shrink (never below edge-to-edge width, or ~75% of the zone) so the
    // focus area ends above the logo.
    final minHeight = math.max(boxWidth / aspect, (zoneHeight - topOffset) * 0.75);
    final wanted = (limitY - top) / focus.bottom;
    height = wanted.clamp(minHeight, height).toDouble();
    // Still too low? Slide the image up, without cutting into the focus area.
    final bottom = top + focus.bottom * height;
    if (bottom > limitY) {
      final lift = bottom - limitY;
      final maxLift = top + focus.top * height - minTop;
      top -= math.min(lift, math.max(0, maxLift));
    }
  }
  final width = height * aspect;
  final cx = focus?.center.dx ?? fallbackX;
  final left = (boxWidth / 2 - cx * width).clamp(boxWidth - width, 0.0).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}
