import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_helpers.dart';

void main() {
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
