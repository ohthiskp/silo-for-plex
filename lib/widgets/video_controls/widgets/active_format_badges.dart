import 'dart:async';

import 'package:flutter/material.dart';

import '../../../mpv/mpv.dart';
import '../../../services/playback_quality_manager.dart';

/// HD / 4K UHD and HDR badges for what is really playing, never for what was
/// asked for. Reads mpv's decoded frame size and colour tags plus the native
/// player's `astra-output-range` report every few seconds while the controls
/// are on screen, so a version switch, a transcode or an HDR→SDR fallback
/// shows up without a restart. Shows nothing until mpv reports a frame.
///
/// Dolby Vision is a plain text label: Astra ships no Dolby logo artwork,
/// and the official logo needs Dolby's licence and brand guidelines.
class ActiveFormatBadges extends StatefulWidget {
  const ActiveFormatBadges({super.key, required this.player});

  final Player player;

  @override
  State<ActiveFormatBadges> createState() => _ActiveFormatBadgesState();
}

class _ActiveFormatBadgesState extends State<ActiveFormatBadges> {
  static const _interval = Duration(seconds: 3);

  Timer? _timer;
  ActivePlaybackFormat _format = const ActivePlaybackFormat();
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(_interval, (_) => unawaited(_refresh()));
  }

  @override
  void didUpdateWidget(covariant ActiveFormatBadges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) unawaited(_refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String?> _read(String name) async {
    try {
      final value = await widget.player.getProperty(name);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final player = widget.player;
      final results = await Future.wait([
        _read('video-params/w'),
        _read('video-params/h'),
        _read('video-params/gamma'),
        _read('current-tracks/video/dolby-vision-profile'),
        _read('astra-output-range'),
      ]);
      if (!mounted || player != widget.player) return;
      final next = PlaybackQualityManager.describeActive(
        width: int.tryParse(results[0] ?? ''),
        height: int.tryParse(results[1] ?? ''),
        sourceGamma: results[2],
        doviProfile: int.tryParse(results[3] ?? ''),
        outputRange: results[4],
      );
      if (next != _format) setState(() => _format = next);
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = _format;
    if (format.isEmpty) return const SizedBox.shrink();
    final resolution = format.resolution;
    final range = format.dynamicRange;
    return Semantics(
      label: [resolution?.label, range?.label].whereType<String>().join(', '),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (resolution != null) _QualityBadge(resolution.label),
            if (resolution != null && range != null) const SizedBox(width: 8),
            if (range != null) _QualityBadge(range.label),
          ],
        ),
      ),
    );
  }
}

/// Conventional outlined format badge, as on a disc case or a store page.
class _QualityBadge extends StatelessWidget {
  const _QualityBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        border: Border.all(color: const Color(0xB3FFFFFF), width: 1.2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          height: 1.1,
        ),
      ),
    );
  }
}
