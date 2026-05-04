import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_helpers.dart';

void main() {
  const urlA = 'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Ffirst.jpg';
  const urlB =
      'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fsecond_hq.jpg';
  const oldPng =
      'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fimg_1777327271112.png';
  const thumbStorage =
      'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fthumbnails%2Fphoto.webp';

  group('selectCatalogCoverImageUrl / capa', () {
    test('A: primeira na lista vence mesmo se a segunda parece HQ', () {
      expect(
        selectCatalogCoverImageUrl(imagens: [urlA, urlB]),
        urlA,
      );
    });

    test('B: PNG antigo primeiro e JPG HQ segundo — capa continua o primeiro', () {
      expect(
        selectCatalogCoverImageUrl(imagens: [oldPng, urlB]),
        oldPng,
      );
    });

    test('C: imagens vazias — usa imageUrl', () {
      expect(
        selectCatalogCoverImageUrl(
          imagens: const [],
          imageUrl: urlA,
        ),
        urlA,
      );
    });

    test('D: imagens[0] normal e campo thumbnail separado — capa é imagens[0]', () {
      const thumbField = 'https://x.com/thumb-only.jpg';
      expect(
        selectCatalogCoverImageUrl(
          imagens: [urlA],
          thumbnail: thumbField,
        ),
        urlA,
      );
    });

    test(
        'E: imagens[0] é /thumbnails/ e [1] é normal — capa salta só o prefixo thumb Storage',
        () {
      expect(
        selectCatalogCoverImageUrl(
          imagens: [thumbStorage, urlA],
        ),
        urlA,
      );
    });

    test('imagens vazias: imageUrl antes de thumbnail no fallback solto', () {
      expect(
        selectCatalogCoverImageUrl(
          imagens: const [],
          imageUrl: urlA,
          thumbnail: 'https://x.com/t.jpg',
        ),
        urlA,
      );
    });
  });

  group('selectCatalogPrimaryImageUrlFromProdutoMap', () {
    test('delega à mesma regra de capa (listas + map)', () {
      expect(
        selectCatalogPrimaryImageUrlFromProdutoMap({
          'imagens': [urlA, urlB],
        }),
        urlA,
      );
    });
  });

  group('catalogProductImageUrlsForDisplay / galeria', () {
    test('preserva ordem; não move thumbnail para o fim', () {
      const full =
          'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fphoto.jpg';
      const thumb =
          'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fthumbnails%2Fphoto.webp';
      final urls = catalogProductImageUrlsForDisplay({
        'imagens': [thumb, full],
      });
      expect(urls, [thumb, full]);
    });

    test('usa fotoThumbUrl só se não houver outra', () {
      const thumb =
          'https://x.firebasestorage.app/o/lojas%2Fa%2Fprodutos%2Fp%2Fthumbnails%2Fx.webp';
      final urls = catalogProductImageUrlsForDisplay({
        'fotoThumbUrl': thumb,
      });
      expect(urls, [thumb]);
    });

    test('dedupe sem mudar ordem do primeiro visto', () {
      const u = 'https://example.com/a.jpg';
      final urls = catalogProductImageUrlsForDisplay({
        'imageUrl': u,
        'imagens': [u],
        'imagem_principal': u,
      });
      expect(urls, [u]);
    });

    test('catalogProductImagesForHeroAndGallery espelha a galeria', () {
      final urls = catalogProductImagesForHeroAndGallery({
        'imagens': [oldPng, urlB],
      });
      expect(urls, [oldPng, urlB]);
    });
  });
}
