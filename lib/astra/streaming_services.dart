/// The streaming services Astra's top switcher offers, with their TMDB
/// watch-provider ids for the US region.
///
/// Browsing a service shows what TMDB says streams there. That is catalog
/// data only: a title is playable in Astra only when it is on the user's own
/// media server, which the detail screen resolves separately.
class StreamingService {
  const StreamingService({
    required this.id,
    required this.label,
    required this.logoAsset,
    required this.tmdbProviderIds,
    this.logoHeight = 18,
    this.brandColor = 0xFFFFFFFF,
  });

  /// Stable key, persisted as the user's selection.
  final String id;
  final String label;

  /// Monochrome-tintable logo (SVG, or PNG for Crunchyroll).
  final String logoAsset;

  /// TMDB watch-provider ids, OR-ed together (a service can have several
  /// tiers, e.g. Paramount+ and Paramount+ Premium).
  final List<int> tmdbProviderIds;

  /// Visual height of the logo inside the pill, tuned per wordmark.
  final double logoHeight;

  /// The logo's real color, shown when this service is selected.
  final int brandColor;

  bool get isSvg => logoAsset.endsWith('.svg');

  String get tmdbFilter => tmdbProviderIds.join('|');
}

const String tmdbWatchRegion = 'US';

const List<StreamingService> streamingServices = [
  StreamingService(
    id: 'netflix',
    label: 'Netflix',
    logoAsset: 'assets/providers/netflix.svg',
    tmdbProviderIds: [8],
    logoHeight: 15,
    brandColor: 0xFFE50914,
  ),
  StreamingService(
    id: 'appletv',
    label: 'Apple TV+',
    logoAsset: 'assets/providers/appletv.svg',
    tmdbProviderIds: [350],
    logoHeight: 17,
  ),
  StreamingService(
    id: 'prime',
    label: 'Prime Video',
    logoAsset: 'assets/providers/prime.svg',
    tmdbProviderIds: [9],
    logoHeight: 20,
    brandColor: 0xFF1FA8F0,
  ),
  StreamingService(
    id: 'disney',
    label: 'Disney+',
    logoAsset: 'assets/providers/disney.svg',
    tmdbProviderIds: [337],
    logoHeight: 24,
    brandColor: 0xFF4AA8FF,
  ),
  StreamingService(
    id: 'max',
    label: 'HBO Max',
    logoAsset: 'assets/providers/max.svg',
    tmdbProviderIds: [1899],
    logoHeight: 22,
  ),
  StreamingService(
    id: 'hulu',
    label: 'Hulu',
    logoAsset: 'assets/providers/hulu.svg',
    tmdbProviderIds: [15],
    logoHeight: 15,
    brandColor: 0xFF1CE783,
  ),
  StreamingService(
    id: 'paramount',
    label: 'Paramount+',
    logoAsset: 'assets/providers/paramount.svg',
    tmdbProviderIds: [531, 2303],
    logoHeight: 18,
    brandColor: 0xFF3A86FF,
  ),
  StreamingService(
    id: 'peacock',
    label: 'Peacock',
    logoAsset: 'assets/providers/peacock.svg',
    tmdbProviderIds: [386, 387],
    logoHeight: 17,
  ),
  StreamingService(
    id: 'crunchyroll',
    label: 'Crunchyroll',
    logoAsset: 'assets/providers/crunchyroll.png',
    tmdbProviderIds: [283],
    logoHeight: 14,
    brandColor: 0xFFF47521,
  ),
];

StreamingService? streamingServiceById(String? id) {
  if (id == null) return null;
  for (final s in streamingServices) {
    if (s.id == id) return s;
  }
  return null;
}
