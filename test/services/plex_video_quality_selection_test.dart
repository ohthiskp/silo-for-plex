import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/transcode_quality_preset.dart';
import 'package:plezy/models/video_quality_preference.dart';
import 'package:plezy/services/playback_initialization_types.dart';
import 'package:plezy/services/playback_quality_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// End to end through the real Plex client: which file URL or transcode
/// request actually goes out for each Video Quality setting. Checks the
/// source that is selected, not a label.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> media(
    int id, {
    required int width,
    required int height,
    required int kbps,
    String codec = 'h264',
  }) => {
    'id': id,
    'container': 'mkv',
    'bitrate': kbps,
    'width': width,
    'height': height,
    'videoResolution': height >= 2000 ? '4k' : '$height',
    'videoCodec': codec,
    'Part': [
      {'id': id * 10, 'key': '/library/parts/${id * 10}/file.mkv', 'exists': true, 'accessible': true},
    ],
  };

  final hd1080 = media(1, width: 1920, height: 1080, kbps: 12000);
  final uhd = media(2, width: 3840, height: 2160, kbps: 60000, codec: 'hevc');
  final hd720 = media(3, width: 1280, height: 720, kbps: 4000);
  final remux1080 = media(4, width: 1920, height: 1080, kbps: 40000);

  Future<({String? url, bool transcoding, Uri? decision, int index})> play(
    List<Map<String, dynamic>> versions,
    VideoQualityPreference preference, {
    bool autoSelect = true,
    bool cellular = false,
  }) async {
    Uri? decision;
    final client = testPlexClient(
      serverId: ServerId('server-id'),
      handler: (request) async {
        if (request.url.path == '/library/metadata/42') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'Metadata': [
                  {'ratingKey': '42', 'type': 'movie', 'title': 'Movie', 'Media': versions},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/video/:/transcode/universal/decision') {
          decision = request.url;
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'transcodeDecisionCode': 1001,
                'Metadata': [
                  {
                    'Media': [
                      {'container': 'mp4', 'protocol': 'hls', 'selected': true},
                    ],
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('unexpected request', 500);
      },
    );
    try {
      final result = await client.getPlaybackInitialization(
        PlaybackInitializationOptions(
          metadata: testMediaItem(id: '42', backend: MediaBackend.plex, kind: MediaKind.movie, serverId: 'server-id'),
          selectedMediaIndex: 0,
          qualityPreset: PlaybackQualityManager.startupPreset(
            preference,
            serverSupportsTranscoding: true,
            onCellularOnly: cellular,
          ),
          autoSelectVersionFor: autoSelect ? preference : null,
          onCellularOnly: cellular,
          sessionIdentifier: 'session-id',
          transcodeSessionId: 'transcode-id',
        ),
      );
      return (
        url: result.videoUrl,
        transcoding: result.isTranscoding,
        decision: decision,
        index: result.selectedMediaIndex,
      );
    } finally {
      client.close();
    }
  }

  group('multiple versions of one title', () {
    final versions = [hd1080, uhd, hd720];

    test('Auto plays the 4K file directly', () async {
      final r = await play(versions, VideoQualityPreference.auto);
      expect(r.url, contains('/library/parts/20/file.mkv'));
      expect(r.transcoding, isFalse);
      expect(r.index, 1);
    });

    test('4K plays the 4K file directly', () async {
      final r = await play(versions, VideoQualityPreference.uhd);
      expect(r.url, contains('/library/parts/20/file.mkv'));
      expect(r.transcoding, isFalse);
    });

    test('HD plays the 1080p file directly', () async {
      final r = await play(versions, VideoQualityPreference.hd);
      expect(r.url, contains('/library/parts/10/file.mkv'));
      expect(r.transcoding, isFalse);
      expect(r.index, 0);
    });

    test('Auto on cellular picks 1080p, and 8 Mbps caps the 12 Mbps file', () async {
      final r = await play(versions, VideoQualityPreference.auto, cellular: true);
      expect(r.index, 0);
      expect(r.transcoding, isTrue);
      expect(r.decision?.queryParameters['X-Plex-Client-Profile-Extra'], contains('name=video.bitrate&value=8000'));
    });

    test('an explicit or remembered version is never overridden', () async {
      final r = await play(versions, VideoQualityPreference.uhd, autoSelect: false);
      expect(r.url, contains('/library/parts/10/file.mkv'));
    });
  });

  group('a single file', () {
    test('1080p file: every setting plays it as it is', () async {
      for (final q in VideoQualityPreference.values) {
        final r = await play([remux1080], q);
        expect(r.url, contains('/library/parts/40/file.mkv'), reason: q.name);
        expect(r.transcoding, isFalse, reason: '${q.name}: a 40 Mbps 1080p remux is not re-encoded');
      }
    });

    test('4K file on Auto and 4K plays as it is', () async {
      for (final q in [VideoQualityPreference.auto, VideoQualityPreference.uhd]) {
        final r = await play([uhd], q);
        expect(r.url, contains('/library/parts/20/file.mkv'), reason: q.name);
        expect(r.transcoding, isFalse);
      }
    });

    test('4K file on HD asks the Plex transcoder for 1080p', () async {
      final r = await play([uhd], VideoQualityPreference.hd);
      expect(r.transcoding, isTrue);
      expect(r.url, contains('/video/:/transcode/universal/start'));
      expect(r.decision?.queryParameters['videoResolution'], '1920x1080');
    });

    test('no 4K available: the 4K setting falls back to the best file', () async {
      final r = await play([hd720, hd1080], VideoQualityPreference.uhd);
      expect(r.url, contains('/library/parts/10/file.mkv'));
      expect(r.transcoding, isFalse);
    });
  });

  test('the setting persists and is device-local (not exported)', () async {
    await SettingsService.instance.write(SettingsService.videoQualityPreference, VideoQualityPreference.hd);
    SettingsService.resetForTesting();
    final reloaded = await SettingsService.getInstance();
    expect(reloaded.read(SettingsService.videoQualityPreference), VideoQualityPreference.hd);
    expect(PlaybackQualityManager.readPreference(reloaded), VideoQualityPreference.hd);
    expect(SettingsService.portablePrefs, isNot(contains(SettingsService.videoQualityPreference)));
  });

  test('legacy presets stay out of the picker', () {
    expect(TranscodeQualityPreset.displayOrder, isNot(contains(TranscodeQualityPreset.upTo1080p)));
  });
}
