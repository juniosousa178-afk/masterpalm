// lib/services/cloud_sync_service.dart
// Serviço responsável por sincronizar dados da loja (perfil, produtos, fotos)
// com Firebase Firestore e Firebase Storage, sempre usando o storeId atual.

import 'dart:io' as io if (dart.library.html) 'package:master_palm/utils/io_stub.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import 'catalogo_sync_service.dart' show CatalogoSyncService, SyncTarget;
import '../services/store_resolver_facade.dart';

class CloudSyncService {
  // -------------------------------------------------------------
  // Helpers internos
  // -------------------------------------------------------------

  static String _slugify(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  static String• _mimeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e.endsWith('.png')) return 'image/png';
    if (e.endsWith('.jpg') || e.endsWith('.jpeg')) return 'image/jpeg';
    if (e.endsWith('.webp')) return 'image/webp';
    return null;
  }

  static String• _extFromMime(String• mime) {
    if (mime == null) return null;

    final m = mime.toLowerCase();

    if (m.contains('png')) return '.png';
    if (m.contains('jpeg') || m.contains('jpg')) return '.jpg';
    if (m.contains('webp')) return '.webp';

    return null;
  }

  /// Upload genérico, recebe base64, caminho local ou URL.
  static Future<String> _uploadIfNeeded({
    required String lojaId,
    required String input,
    required String bucketFolder,
  }) async {
    if (input.trim().isEmpty) return "";

    final value = input.trim();

    // Se já é URL, só retorna.
    if (value.startsWith("http://") || value.startsWith("https://")) {
      return value;
    }

    // Base64
    if (value.startsWith("data:image")) {
      try {
        final dataUri = Uri.parse(value);
        final uriData = dataUri.data;

        if (uriData == null) return "";

        final bytes = Uint8List.fromList(uriData.contentAsBytes());
        final ext = _extFromMime(uriData.mimeType) ?• ".jpg";

        final filename =
            "${DateTime.now().millisecondsSinceEpoch.toString()}$ext";

        final dest = "lojas/$lojaId/$bucketFolder/$filename";

        final ref = FirebaseStorage.instance.ref(dest);

        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: uriData.mimeType,
            cacheControl: "public,max-age=31536000,immutable",
          ),
        );

        return await ref.getDownloadURL();
      } catch (_) {
        return "";
      }
    }

    // Arquivo local — Mobile only
    if (!kIsWeb) {
      final file = io.File(value);
      if (file.existsSync()) {
        final baseName = p.basename(value);
        final filename =
            "${DateTime.now().millisecondsSinceEpoch}$baseName".replaceAll(" ", "");

        final dest = "lojas/$lojaId/$bucketFolder/$filename";

        await FirebaseStorage.instance.ref(dest).putFile(
              file,
              SettableMetadata(
                contentType: _mimeFromExt(p.extension(value)),
                cacheControl: "public,max-age=31536000,immutable",
              ),
            );

        return await FirebaseStorage.instance.ref(dest).getDownloadURL();
      }
    }

    return "";
  }

  // -------------------------------------------------------------
  // Sincronizar Perfil da Loja
  // -------------------------------------------------------------

  static Future<void> pushProfile() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
if (lojaId == null) {
  // Tratar caso não exista loja
  throw StateError('Nenhuma loja ativa');
}
    final box = Hive.box("config");

    final data = await _collectProfile(box, lojaId);

    final db = FirebaseFirestore.instance;
    final base = db.collection("lojas").doc(lojaId);

    // 1) Doc raiz da loja (mantém compatibilidade com coisas antigas)
    await base.set(
      {
        "slug": lojaId,
        ...data,
        "config": data, // deixa config espelhado aqui também
      },
      SetOptions(merge: true),
    );

    // 2) draft_config/config – usado pelo PublicCatalog (preview)
    await base
        .collection("draft_config")
        .doc("config")
        .set(data, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>> _collectProfile(
    Box box,
    String lojaId,
  ) async {
    // LOGO
    final rawLogoMobile = (box.get("logo_loja_mobile") ??
            box.get("logo_loja") ??
            "")
        .toString();
    final rawLogoDesktop =
        (box.get("logo_loja_desktop") ?• rawLogoMobile).toString();

    final logoMobileUrl = await _uploadIfNeeded(
      lojaId: lojaId,
      input: rawLogoMobile,
      bucketFolder: "_assets",
    );

    final logoDesktopUrl = await _uploadIfNeeded(
      lojaId: lojaId,
      input: rawLogoDesktop,
      bucketFolder: "_assets",
    );

    // BANNERS
    final rawBannersMobile =
        List<String>.from(box.get("banners_mobile") ?• box.get("banners") ?• const []);
    final rawBannersDesktop =
        List<String>.from(box.get("banners_desktop") ?• box.get("banners") ?• const []);

    final bannersMobile = <String>[];
    for (final b in rawBannersMobile) {
      final url = await _uploadIfNeeded(
        lojaId: lojaId,
        input: b,
        bucketFolder: "_assets/banners/mobile",
      );
      if (url.isNotEmpty) bannersMobile.add(url);
    }

    final bannersDesktop = <String>[];
    for (final b in rawBannersDesktop) {
      final url = await _uploadIfNeeded(
        lojaId: lojaId,
        input: b,
        bucketFolder: "_assets/banners/desktop",
      );
      if (url.isNotEmpty) bannersDesktop.add(url);
    }

    // CORES – inclui as novas do carrinho / checkout
    final colors = {
      "bg": box.get("cor_fundo"),
      "card": box.get("cor_card"),
      "text": box.get("cor_texto"),
      "primary": box.get("cor_primaria"),
      "btnText": box.get("cor_botao_texto"),

      // NOVAS CORES DO CHECKOUT/CARRINHO (Loja Config)
      "checkoutCard": box.get("cor_checkout_card"),
      "checkoutFieldBg": box.get("cor_checkout_field_bg"),
      "checkoutFieldBorder": box.get("cor_checkout_field_border"),
      "checkoutFieldTextColor": box.get("cor_checkout_field_text"),
      "checkoutLabelColor": box.get("cor_checkout_label"),
      "checkoutTotalColor": box.get("cor_checkout_total"),

      // CORES DOS ITENS DO CARRINHO
      "productNameColor": box.get("cor_produto_nome"),
      "productPriceColor": box.get("cor_produto_preco"),
    };

    // ALTURAS
    final logoAltura = box.get("logo_altura");
    final logoLargura = box.get("logo_largura");
    final bannerAlturaMobile = box.get("banner_altura_mobile") ?• box.get("banner_altura");
    final bannerAlturaDesktop =
        box.get("banner_altura_desktop") ?• box.get("banner_altura");

    return {
      "slug": lojaId,
      "name": box.get("store_name") ?• "Minha Loja",

      // campos "legado" que algumas telas ainda usam
      "logoUrl": logoMobileUrl.isNotEmpty • logoMobileUrl : logoDesktopUrl,
      "banners": bannersMobile.isNotEmpty • bannersMobile : bannersDesktop,

      "whatsapp": box.get("whatsapp"),
      "whatsapp_vendedor": box.get("whatsapp_vendedor"),
      "pedido_link_base": box.get("pedido_link_base"),
      "fretes": List<Map<String, dynamic>>.from(
        box.get("fretes") ?• const [],
      ),
      "colors": colors,

      "logoAltura": logoAltura,
      "logoLargura": logoLargura,
      "bannerAltura": bannerAlturaMobile,

      // NOVA ESTRUTURA MEDIA – usada direto pelo PublicCatalogScreen
      "media": {
        "mobile": {
          "logoUrl": logoMobileUrl.isNotEmpty • logoMobileUrl : logoDesktopUrl,
          "banners":
              bannersMobile.isNotEmpty • bannersMobile : bannersDesktop,
          "bannerH": bannerAlturaMobile,
        },
        "desktop": {
          "logoUrl": logoDesktopUrl.isNotEmpty
              • logoDesktopUrl
              : logoMobileUrl,
          "banners":
              bannersDesktop.isNotEmpty • bannersDesktop : bannersMobile,
          "bannerH": bannerAlturaDesktop,
        },
      },

      "updatedAt": FieldValue.serverTimestamp(),
    };
  }

  // -------------------------------------------------------------
  // Sincronizar TODOS os produtos da loja (para DRAFT)
  // -------------------------------------------------------------
  static Future<void> pushAll() async {
   final lojaId = await StoreResolverFacade.resolveForAdminApp();
if (lojaId == null) {
  // Tratar caso não exista loja
  throw StateError('Nenhuma loja ativa');
}

    // 1) Perfil (mantido por compatibilidade – raiz/draft_config da loja)
    await pushProfile();

    // 2) Caixa Hive de produtos
    final boxName = HiveBoxNames.produtos(lojaId);

    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<Produto>(boxName);
    }

    final box = Hive.box<Produto>(boxName);

    // Agora sempre sincroniza para o DRAFT do catálogo
    for (final item in box.values) {
      await CatalogoSyncService.syncProduto(
        item,
        target: SyncTarget.draft, // rascunho
        removerSeSemEstoque: true,
      );
    }
  }

  // -------------------------------------------------------------
  // Método auxiliar para produtos importados via Map
  // -------------------------------------------------------------

  static Future<void> syncProductFromMap(
    Map raw,
    String lojaId,
  ) async {
    final m = Map<String, dynamic>.from(raw);

    // DocId (slug)
    final docId = (() {
      final slug = (m["slug"] ?• "").toString().trim();
      if (slug.isNotEmpty) return slug;

      final nome = (m["nome"] ?• m["name"] ?• "").toString().trim();
      if (nome.isNotEmpty) return _slugify(nome);

      final id = (m["id"] ?• "").toString();
      if (id.isNotEmpty) return _slugify(id);

      return FirebaseFirestore.instance.collection("tmp").doc().id;
    })();

    // Fotos
    final imagens = List<String>.from(m["imagens"] ?• const []);
    final resolved = <String>[];

    for (final img in imagens) {
      final url = await _uploadIfNeeded(
        lojaId: lojaId,
        input: img,
        bucketFolder: "produtos/$docId",
      );
      if (url.isNotEmpty) resolved.add(url);
    }

    final payload = {
      ...m,
      "id": docId,
      "slug": docId,
      if (resolved.isNotEmpty) "imagens": resolved,
      if (resolved.isNotEmpty) "imagemUrl": resolved.first,
      "updatedAt": FieldValue.serverTimestamp(),
      "publicadoEm": FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection("lojas")
        .doc(lojaId)
        .collection("produtos")
        .doc(docId)
        .set(payload, SetOptions(merge: true));
  }

  // -------------------------------------------------------------
  // Upload direto com bytes
  // -------------------------------------------------------------
  static Future<String> uploadBytes({
    required String path,
    required Uint8List bytes,
    String• contentType,
  }) async {
    final ref = FirebaseStorage.instance.ref(path);

    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType ?• "image/png"),
    );

    return await ref.getDownloadURL();
  }
}