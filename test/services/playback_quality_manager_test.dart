import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/models/video_quality_preference.dart';
import 'package:plezy/services/playback_quality_manager.dart';

MediaVersion v(String id, {int? w, int? h, String? res, String codec = 'hevc', int? kbps}) =>
    MediaVersion(id: id, width: w, height: h, videoResolution: res, videoCodec: codec, bitrate: kbps);

void main() {
  const auto = VideoQualityPreference.auto;
  const hd = VideoQualityPreference.hd;
  const uhd = VideoQualityPreference.uhd;

  // Plex lists versions in library order, not best-first.
  final multi = [
    v('1080', w: 1920, h: 1080, res: '1080', codec: 'h264', kbps: 12000),
    v('4k', w: 3840, h: 2160, res: '4k', kbps: 60000),
    v('720', w: 1280, h: 720, res: '720', codec: 'h264', kbps: 4000),
  ];

  group('tierHeight', () {
    test('scope crops count by width', () {
      expect(PlaybackQualityManager.tierHeightOf(width: 1920, height: 800), 1080);
      expect(PlaybackQualityManager.tierHeightOf(width: 3840, height: 1600), 2160);
      expect(PlaybackQualityManager.tierHeightOf(width: 1916, height: 796), 1080);
      expect(PlaybackQualityManager.tierHeightOf(width: 1280, height: 534), 720);
    });

    test('named Plex tiers without dimensions', () {
      expect(PlaybackQualityManager.tierHeight(v('a', res: '4k')), 2160);
      expect(PlaybackQualityManager.tierHeight(v('a', res: '1080')), 1080);
      expect(PlaybackQualityManager.tierHeight(v('a')), isNull);
    });
  });

  group('chooseVersionIndex', () {
    test('single version: leave it to the backend', () {
      expect(PlaybackQualityManager.chooseVersionIndex([multi[1]], hd), isNull);
    });

    test('Auto and 4K take the 4K version; HD the 1080p one', () {
      expect(PlaybackQualityManager.chooseVersionIndex(multi, auto, decodable: (_) => true), 1);
      expect(PlaybackQualityManager.chooseVersionIndex(multi, uhd, decodable: (_) => true), 1);
      expect(PlaybackQualityManager.chooseVersionIndex(multi, hd, decodable: (_) => true), 0);
    });

    test('4K without a 4K version falls back to the best lower one', () {
      final no4k = [multi[2], multi[0]];
      expect(PlaybackQualityManager.chooseVersionIndex(no4k, uhd, decodable: (_) => true), 1);
    });

    test('HD with only taller versions picks the lowest', () {
      final tall = [v('4k', w: 3840, h: 2160, kbps: 60000), v('1440', w: 2560, h: 1440, kbps: 20000)];
      expect(PlaybackQualityManager.chooseVersionIndex(tall, hd, decodable: (_) => true), 1);
    });

    test('a version the device cannot decode is skipped', () {
      // 4K is HEVC; a device without HEVC decode gets the 1080p H.264.
      expect(PlaybackQualityManager.chooseVersionIndex(multi, uhd, decodable: (x) => x.videoCodec == 'h264'), 0);
    });

    test('when nothing is decodable, still pick rather than fail', () {
      expect(PlaybackQualityManager.chooseVersionIndex(multi, uhd, decodable: (_) => false), 1);
    });

    test('same tier: the higher bitrate wins', () {
      final twins = [v('a', w: 1920, h: 1080, kbps: 8000), v('b', w: 1920, h: 1080, kbps: 30000)];
      expect(PlaybackQualityManager.chooseVersionIndex(twins, hd, decodable: (_) => true), 1);
    });
  });

  group('describeActive', () {
    ActivePlaybackFormat d({int? w, int? h, String? gamma, int? dovi, String? out}) =>
        PlaybackQualityManager.describeActive(
          width: w,
          height: h,
          sourceGamma: gamma,
          doviProfile: dovi,
          outputRange: out,
        );

    test('resolution from the decoded frame', () {
      expect(d(w: 3840, h: 1600).resolution, ActiveResolution.uhd4k);
      expect(d(w: 1920, h: 1080).resolution, ActiveResolution.hd);
      expect(d(w: 720, h: 480).resolution, isNull);
      expect(d().isEmpty, isTrue);
    });

    test('a 4K file transcoded to 1080p reads HD', () {
      expect(
        d(w: 1920, h: 1080, gamma: 'bt.1886', out: 'SDR'),
        const ActivePlaybackFormat(resolution: ActiveResolution.hd),
      );
    });

    test('Dolby Vision only when the display was really put in Dolby Vision', () {
      expect(
        d(w: 3840, h: 2160, gamma: 'pq', dovi: 8, out: 'Dolby Vision').dynamicRange,
        ActiveDynamicRange.dolbyVision,
      );
      // TV without Dolby Vision: tvOS narrowed the request to HDR10.
      expect(d(w: 3840, h: 2160, gamma: 'pq', dovi: 8, out: 'HDR10').dynamicRange, ActiveDynamicRange.hdr10);
      // Mac EDR showing a DV file is HDR, not Dolby Vision.
      expect(d(w: 3840, h: 2160, gamma: 'pq', dovi: 8, out: 'HDR').dynamicRange, ActiveDynamicRange.hdr);
    });

    test('HDR source on an SDR output shows no HDR badge', () {
      expect(d(w: 3840, h: 2160, gamma: 'pq', out: 'SDR').dynamicRange, isNull);
      expect(d(w: 3840, h: 2160, gamma: 'pq').dynamicRange, isNull, reason: 'unknown output is never guessed');
    });

    test('EDR output names the source transfer', () {
      expect(d(w: 3840, h: 2160, gamma: 'pq', out: 'HDR').dynamicRange, ActiveDynamicRange.hdr10);
      expect(d(w: 3840, h: 2160, gamma: 'hlg', out: 'HDR').dynamicRange, ActiveDynamicRange.hlg);
    });
  });
}
