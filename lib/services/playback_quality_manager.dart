import 'dart:math' as math;

import '../media/media_version.dart';
import '../models/video_quality_preference.dart';
import 'settings_service.dart';
import 'video_decode_capabilities.dart';

/// The single place Astra turns the device's Preferred Quality setting (Auto, HD,
/// 4K) into a playback decision. The rules are written up for the SwiftUI
/// port in `docs/playback-quality.md`; keep the two in step.
///
/// What it does, in order:
/// 1. Reads this device's saved preference ([readPreference]).
/// 2. Looks at the versions the server has for the title ([chooseVersionIndex]).
/// 3. Drops versions this device should not be sent (codec refused, or no
///    hardware decoder on a device that probes for one).
/// 4. Picks the best version under the preference's ceiling, falling back to
///    the nearest one above it when nothing fits.
/// 5. The chosen original file goes to mpv through the normal playback
///    pipeline, untouched: the setting never transcodes, re-encodes or
///    downscales. A title with one file plays that file whatever the setting.
/// 6. [describeActive] reports what is really playing, for the badges.
///
/// Astra plays everything through libmpv. There is no AVPlayer/HLS adaptive
/// path, so a file never changes quality by itself mid-play: quality only
/// changes by picking another existing version.
class PlaybackQualityManager {
  const PlaybackQualityManager._();

  /// This device's saved preference. Auto when settings are not loaded yet.
  static VideoQualityPreference readPreference([SettingsService? settings]) {
    final s = settings ?? SettingsService.instanceOrNull;
    return s?.read(SettingsService.videoQualityPreference) ?? VideoQualityPreference.auto;
  }

  /// Nominal tier of a version in "p" (720, 1080, 2160). A 2.39:1 film is
  /// 1920×800 or 3840×1600, so width counts as well as height: 1920 wide is
  /// 1080p whatever the crop.
  static int? tierHeight(MediaVersion v) => tierHeightOf(width: v.width, height: v.resolutionHeight);

  static int? tierHeightOf({int? width, int? height}) {
    final h = height != null && height > 0 ? height : null;
    final fromWidth = width != null && width > 0 ? (width * 9 / 16).round() : null;
    if (h == null && fromWidth == null) return null;
    final raw = math.max(h ?? 0, fromWidth ?? 0);
    // Snap to the conventional tiers so 3840×1600 reads as 2160 and a
    // 1916-wide encode still reads as 1080.
    const tiers = [480, 576, 720, 1080, 1440, 2160, 4320];
    for (final t in tiers) {
      if (raw <= t * 1.04) return t;
    }
    return raw;
  }

  /// Whether this device should be sent [v] as it is. Refused codecs and
  /// codecs the hardware probe reports no decoder for are out; codecs outside
  /// the ranked list (MPEG-2, VP9, …) and unprobed devices count as playable.
  static bool canDecode(MediaVersion v) {
    final codec = RankedVideoCodec.fromServerCodec(v.videoCodec);
    if (codec == null) return true;
    return VideoDecodeCapabilities.accepts(codec);
  }

  /// Index of the version to play for [preference], or null to keep the
  /// backend's default (one version, or nothing usable to compare).
  ///
  /// - Versions the device cannot play (missing file, refused or
  ///   undecodable codec) are skipped, unless that leaves nothing.
  /// - Under the ceiling, the tallest tier wins; ties go to the higher
  ///   bitrate, then the earlier entry.
  /// - When every version is above the ceiling (HD with only 4K and 1440p
  ///   files), the lowest one is picked and played as it is.
  static int? chooseVersionIndex(
    List<MediaVersion> versions,
    VideoQualityPreference preference, {
    bool Function(MediaVersion)? decodable,
  }) {
    if (versions.length < 2) return null;
    final canPlay = decodable ?? canDecode;
    final ceiling = preference.maxTierHeight;

    var candidates = [
      for (var i = 0; i < versions.length; i++)
        if (versions[i].isPlayable && canPlay(versions[i])) i,
    ];
    if (candidates.isEmpty) {
      candidates = [
        for (var i = 0; i < versions.length; i++)
          if (versions[i].isPlayable) i,
      ];
    }
    if (candidates.isEmpty) return null;

    int tier(int i) => tierHeight(versions[i]) ?? 0;
    int bitrate(int i) => versions[i].bitrate ?? 0;

    final fitting = ceiling == null ? candidates : candidates.where((i) => tier(i) <= ceiling).toList();
    if (fitting.isNotEmpty) {
      var best = fitting.first;
      for (final i in fitting.skip(1)) {
        if (tier(i) > tier(best) || (tier(i) == tier(best) && bitrate(i) > bitrate(best))) best = i;
      }
      return best;
    }
    var lowest = candidates.first;
    for (final i in candidates.skip(1)) {
      if (tier(i) < tier(lowest) || (tier(i) == tier(lowest) && bitrate(i) < bitrate(lowest))) lowest = i;
    }
    return lowest;
  }

  /// What is really on screen, from mpv's decoded frame and the native
  /// player's report of the range the display receives.
  ///
  /// [outputRange] comes from the native `astra-output-range` property:
  /// "Dolby Vision", "HDR10" or "HLG" (Apple TV, from the display mode it
  /// asked for), "HDR" (Mac/iPhone, the video layer is in EDR on a screen
  /// with HDR headroom), "SDR", or null when the path cannot tell. Null and
  /// "SDR" show no HDR badge, so a badge is never a guess.
  ///
  /// HDR10+ is never shown: no Astra output path forwards HDR10+ dynamic
  /// metadata to the display, so an HDR10+ file presents as HDR10.
  static ActivePlaybackFormat describeActive({
    int? width,
    int? height,
    String? sourceGamma,
    int? doviProfile,
    String? outputRange,
  }) {
    final tier = tierHeightOf(width: width, height: height);
    final resolution = tier == null
        ? null
        : tier >= 2160
        ? ActiveResolution.uhd4k
        : tier >= 720
        ? ActiveResolution.hd
        : null;

    final gamma = (sourceGamma ?? '').toLowerCase();
    final isDovi = (doviProfile ?? 0) > 0;
    final range = switch (outputRange) {
      'Dolby Vision' => ActiveDynamicRange.dolbyVision,
      'HDR10' => ActiveDynamicRange.hdr10,
      'HLG' => ActiveDynamicRange.hlg,
      'HDR' =>
        isDovi
            ? ActiveDynamicRange.hdr
            : gamma == 'pq'
            ? ActiveDynamicRange.hdr10
            : gamma == 'hlg'
            ? ActiveDynamicRange.hlg
            : ActiveDynamicRange.hdr,
      _ => null,
    };
    return ActivePlaybackFormat(resolution: resolution, dynamicRange: range);
  }
}

enum ActiveResolution {
  hd('HD'),
  uhd4k('4K UHD');

  const ActiveResolution(this.label);
  final String label;
}

enum ActiveDynamicRange {
  dolbyVision('Dolby Vision'),
  hdr10('HDR10'),
  hlg('HLG'),

  /// HDR output whose exact format the path cannot name (a Dolby Vision file
  /// tone-mapped to the Mac's EDR, which is not Dolby Vision presentation).
  hdr('HDR');

  const ActiveDynamicRange(this.label);
  final String label;
}

/// The real format of the active playback, for the player badges.
class ActivePlaybackFormat {
  final ActiveResolution? resolution;

  /// Null when the output is SDR or the path cannot tell.
  final ActiveDynamicRange? dynamicRange;

  const ActivePlaybackFormat({this.resolution, this.dynamicRange});

  bool get isEmpty => resolution == null && dynamicRange == null;

  @override
  bool operator ==(Object other) =>
      other is ActivePlaybackFormat && other.resolution == resolution && other.dynamicRange == dynamicRange;

  @override
  int get hashCode => Object.hash(resolution, dynamicRange);

  @override
  String toString() => 'ActivePlaybackFormat(${resolution?.label}, ${dynamicRange?.label})';
}
