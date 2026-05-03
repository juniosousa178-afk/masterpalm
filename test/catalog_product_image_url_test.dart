import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_helpers.dart';

void main() {
  group('selectCatalogPrimaryImageUrl', () {
    const oldPipelinePng =
        'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fimg_1777327271112.png';
    const hqJpg =
        'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fphoto_hq.jpg';
    const thumbStorage =
        'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fthumbnails%2Fphoto.webp';

    test('fotoOriginalUrl válida ganha de thumbnail', () {
      expect(
        selectCatalogPrimaryImageUrl(
          imagens: const [],
          fotoOriginalUrl: hqJpg,
          thumbnail: 'https://x.com/thumb.jpg',
        ),
        hqJpg,
      );
    });

    test('thumbnail não ganha de imagens nem fotoOriginalUrl', () {
      expect(
        selectCatalogPrimaryImageUrl(
          imagens: [hqJpg],
          fotoOriginalUrl: null,
          thumbnail: 'https://x.com/some-thumb.jpg',
        ),
        hqJpg,
      );
    });

    test('PNG legado img_*.png depois de JPG HQ — escolhe JPG (ordem lista)', () {
      expect(
        selectCatalogPrimaryImageUrl(imagens: [oldPipelinePng, hqJpg]),
        hqJpg,
      );
    });

    test('JPG HQ primeiro na lista — mantém JPG', () {
      expect(
        selectCatalogPrimaryImageUrl(imagens: [hqJpg, oldPipelinePng]),
        hqJpg,
      );
    });

    test('só entradas /thumbnails/ em imagens — usa imageUrl', () {
      const full =
          'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fbig.jpg';
      expect(
        selectCatalogPrimaryImageUrl(
          imagens: [thumbStorage],
          imageUrl: full,
        ),
        full,
      );
    });

    test('fotoOriginalUrl em pasta thumbnails ignora e usa imagens', () {
      expect(
        selectCatalogPrimaryImageUrl(
          imagens: [hqJpg],
          fotoOriginalUrl: thumbStorage,
        ),
        hqJpg,
      );
    });

    test('catalogProductImagesForHeroAndGallery coloca principal escolhida em [0]', () {
      final urls = catalogProductImagesForHeroAndGallery({
        'imagens': [oldPipelinePng, hqJpg],
      });
      expect(urls.first, hqJpg);
      expect(urls.length, 2);
    });
  });

  group('catalogProductImageUrlsForDisplay', () {
    test('prioriza URL principal antes de thumb no Storage', () {
      const full =
          'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fphoto.jpg';
      const thumb =
          'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fthumbnails%2Fphoto.webp';
      final urls = catalogProductImageUrlsForDisplay({
        'imagens': [thumb, full],
      });
      expect(urls.first, full);
      expect(urls.length, 2);
    });

    test('usa fotoThumbUrl só se não houver outra', () {
      const thumb =
          'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fthumbnails%2Fx.webp';
      final urls = catalogProductImageUrlsForDisplay({
        'fotoThumbUrl': thumb,
      });
      expect(urls, [thumb]);
    });

    test('dedupe e ordem dos campos', () {
      const u = 'https://example.com/a.jpg';
      final urls = catalogProductImageUrlsForDisplay({
        'imageUrl': u,
        'imagens': [u],
        'imagem_principal': u,
      });
      expect(urls, [u]);
    });
  });
}
