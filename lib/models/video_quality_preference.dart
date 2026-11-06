/// The one video quality choice Astra shows: Settings → Playback → Preferred
/// Quality. Saved per device (see `SettingsService.videoQualityPreference`)
/// and applied to every playback on that device by
/// `PlaybackQualityManager`; playback never asks again. It only chooses
/// between the original files a title already has: nothing is ever
/// transcoded, and a title with one file plays it whatever the setting.
///
/// The names are what is stored, so keep them stable.
enum VideoQualityPreference {
  /// Best compatible existing original.
  auto,

  /// Prefer an original at 1080p or below; otherwise play what exists.
  hd,

  /// Prefer a 4K original, falling back to the best lower one.
  uhd;

  /// Label shown in Settings.
  String get label => switch (this) {
    VideoQualityPreference.auto => 'Auto',
    VideoQualityPreference.hd => 'HD',
    VideoQualityPreference.uhd => '4K',
  };

  /// One-line explanation under each choice.
  String get detail => switch (this) {
    VideoQualityPreference.auto => 'Best original this device can play',
    VideoQualityPreference.hd => 'Prefer 1080p or lower',
    VideoQualityPreference.uhd => 'Prefer 4K',
  };

  /// Height ceiling in the "p" sense (1080, 2160), or null for no ceiling.
  int? get maxTierHeight => switch (this) {
    VideoQualityPreference.auto => null,
    VideoQualityPreference.hd => 1080,
    VideoQualityPreference.uhd => 2160,
  };
}
