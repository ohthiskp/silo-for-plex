/// The one video quality choice Astra shows: Settings → Playback → Video
/// Quality. Saved per device (see `SettingsService.videoQualityPreference`)
/// and applied to every playback on that device by
/// `PlaybackQualityManager`; playback never asks again.
///
/// The names are what is stored, so keep them stable.
enum VideoQualityPreference {
  /// Best compatible source. On a cellular-only connection it caps like [hd]
  /// with a bitrate limit, the way streaming apps save data.
  auto,

  /// Best compatible source up to 1920×1080.
  hd,

  /// Prefer a 3840×2160 source, falling back to the best lower one.
  uhd;

  /// Label shown in Settings.
  String get label => switch (this) {
    VideoQualityPreference.auto => 'Auto',
    VideoQualityPreference.hd => 'HD',
    VideoQualityPreference.uhd => '4K',
  };

  /// One-line explanation under each choice.
  String get detail => switch (this) {
    VideoQualityPreference.auto => 'Best quality this device can play',
    VideoQualityPreference.hd => 'Up to 1080p',
    VideoQualityPreference.uhd => 'Up to 2160p',
  };

  /// Height ceiling in the "p" sense (1080, 2160), or null for no ceiling.
  int? get maxTierHeight => switch (this) {
    VideoQualityPreference.auto => null,
    VideoQualityPreference.hd => 1080,
    VideoQualityPreference.uhd => 2160,
  };
}
