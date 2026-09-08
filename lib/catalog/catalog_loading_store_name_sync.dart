import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/catalog_loading_store_name.dart';
import '../core/store_display_name_resolver.dart';
import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as plat;

/// Atualiza a pill HTML com o nome comercial, sem bloquear first paint.
///
/// Falha de rede/Firestore: mantém o fallback já pintado. Nunca lança.
Future<void> syncCatalogLoaderStoreName({
  required String lojaIdOrSlug,
  void Function(String? nomeLoja)? updateNomeLoja,
  FirebaseFirestore? firestore,
}) async {
  final lid = lojaIdOrSlug.trim();
  if (lid.isEmpty) return;

  try {
    final db = firestore ?? FirebaseFirestore.instance;
    String? commercial;

    try {
      final lojaSnap = await db.collection('lojas').doc(lid).get().timeout(
            const Duration(seconds: 3),
          );
      commercial = CatalogLoadingStoreName.pickCommercialName(lojaSnap.data());
    } catch (_) {}

    if (commercial == null ||
        StoreDisplayNameResolver.isWeakPlaceholder(commercial)) {
      try {
        final cfgSnap = await db
            .collection('lojas')
            .doc(lid)
            .collection('config')
            .doc('config')
            .get()
            .timeout(const Duration(seconds: 2));
        commercial = CatalogLoadingStoreName.pickCommercialName(cfgSnap.data());
      } catch (_) {}
    }

    if (commercial == null ||
        StoreDisplayNameResolver.isWeakPlaceholder(commercial)) {
      return;
    }

    plat.Web.setCatalogLoaderStoreName(commercial);
    updateNomeLoja?.call(commercial);
  } catch (e) {
    if (kDebugMode) {
      debugPrint(
        '[CATALOG_LOADER_NAME] sync falhou (fallback preservado) type=${e.runtimeType}',
      );
    }
  }
}
