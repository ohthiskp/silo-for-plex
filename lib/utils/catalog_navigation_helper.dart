import 'package:flutter/material.dart';

import '../astra/detail_screen.dart';
import '../models/catalog/catalog_item.dart';
import '../screens/catalog_item_detail_screen.dart';
import 'media_navigation_helper.dart';
import 'platform_detector.dart';

/// Open a catalog item (Explore tab tap sink, routed here by the catalog
/// branches in `navigateToMediaItem` / `navigateToMediaItemDetails`).
///
/// Astra 3.0: phones, tablets and Mac get the Astra details page; Apple TV
/// and the request flow keep [CatalogItemDetailScreen].
Future<void> navigateToCatalogItem(BuildContext context, CatalogItem item) async {
  if (!PlatformDetector.isTV()) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AstraDetailScreen(
          item: item.toMediaItem(),
          onLegacyDetails: (c, lib) async {
            await navigateToMediaItemDetails(c, lib, legacy: true);
          },
          onRequest: navigateToLegacyCatalogItem,
        ),
      ),
    );
    return;
  }
  await navigateToLegacyCatalogItem(context, item);
}

/// The classic catalog page, which hosts the Seerr request flow.
Future<void> navigateToLegacyCatalogItem(BuildContext context, CatalogItem item) async {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => CatalogItemDetailScreen(item: item)));
}
