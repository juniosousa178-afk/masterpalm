// M3.8 S2-R6.2 — STORENAME: nome canônico da loja na Home.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/store_display_name_resolver.dart';

void main() {
  group('STORENAME', () {
    test('STORENAME-1 campo nome', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {'nome': 'Nathy Pratas e Folheados'},
      );
      expect(r.name, 'Nathy Pratas e Folheados');
      expect(r.source, 'firestore');
      expect(r.field, 'nome');
      expect(r.resolved, isTrue);
    });

    test('STORENAME-2 campo nomeLoja', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {'nomeLoja': 'Loja NomeLoja'},
      );
      expect(r.name, 'Loja NomeLoja');
      expect(r.field, 'nomeLoja');
      expect(r.resolved, isTrue);
    });

    test('STORENAME-3 campo nome_loja', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {'nome_loja': 'Loja Underscore'},
      );
      expect(r.name, 'Loja Underscore');
      expect(r.field, 'nome_loja');
      expect(r.resolved, isTrue);
    });

    test('STORENAME-4 campo nomeFantasia', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {'nomeFantasia': 'Fantasia Store'},
      );
      expect(r.name, 'Fantasia Store');
      expect(r.field, 'nomeFantasia');
      expect(r.resolved, isTrue);
    });

    test('STORENAME-5 Hive fallback', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        hiveConfigStoreName: 'Hive Config Store',
      );
      expect(r.name, 'Hive Config Store');
      expect(r.source, 'hive_config');
      expect(r.field, 'store_name');
      expect(r.resolved, isTrue);
    });

    test('STORENAME-6 slug formatado', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        slug: 'nathy-pratas-e-folheados',
      );
      expect(r.source, 'slug');
      expect(r.name, 'Nathy Pratas E Folheados');
      expect(r.resolved, isTrue);
    });

    test('STORENAME-7 nunca usa e-mail', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        hiveSessaoNome: 'admin@nathy.com',
        firestoreLoja: {'nome': 'admin@nathy.com', 'email': 'x@y.com'},
        slug: 'user@loja.com',
      );
      expect(r.name.contains('@'), isFalse);
      expect(StoreDisplayNameResolver.normalizeCandidate('admin@nathy.com'),
          isNull);
    });

    test('STORENAME-8 nunca usa UID', () {
      const uid = 'a1b2c3d4e5f6789012345678';
      final r = StoreDisplayNameResolver.resolveFromSources(
        hiveSessaoNome: uid,
        firestoreLoja: {'nome': uid},
        slug: uid,
      );
      expect(r.name, StoreDisplayNameResult.fallbackName);
      expect(r.resolved, isFalse);
      expect(StoreDisplayNameResolver.normalizeCandidate(uid), isNull);
    });

    test('STORENAME-9 ignora string vazia', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {
          'nome': '   ',
          'nomeLoja': '',
          'nome_loja': 'null',
        },
        hiveSessaoNome: '  ',
        slug: '',
      );
      expect(r.name, StoreDisplayNameResult.fallbackName);
      expect(r.resolved, isFalse);
      expect(StoreDisplayNameResolver.normalizeCandidate('  '), isNull);
      expect(StoreDisplayNameResolver.normalizeCandidate('null'), isNull);
    });

    test('STORENAME-10 Home mostra Nathy Pratas e Folheados com fixture realista',
        () {
      // Fixture alinhada a lojas/{id} + config V3 (identidade publicada).
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {
          'slug': 'nathy-pratas',
        },
        firestoreConfig: {
          'published': {
            'identidade': {
              'nome': 'Nathy Pratas e Folheados',
            },
          },
        },
        hiveSessaoNome: 'Minha Loja',
        slug: 'abc123def4567890abcdef12',
      );
      expect(r.name, 'Nathy Pratas e Folheados');
      expect(r.source, 'firestore');
      expect(r.resolved, isTrue);
      expect(
        StoreDisplayNameResolver.homeGreetingLabel(
          resolving: false,
          currentName: r.name,
        ),
        'Nathy Pratas e Folheados',
      );
    });

    test('STORENAME-11 fallback Minha Loja somente sem nenhuma fonte válida',
        () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {},
        firestoreConfig: null,
        hiveSessaoNome: null,
        hiveConfigStoreName: '',
        slug: 'ffffffffffffffffffffffff',
      );
      expect(r.name, 'Minha Loja');
      expect(r.source, 'fallback');
      expect(r.resolved, isFalse);
    });

    test('STORENAME-12 carregamento não pisca login', () {
      final during = StoreDisplayNameResolver.homeGreetingLabel(
        resolving: true,
        currentName: '',
      );
      expect(during, isNull);

      final emailFlash = StoreDisplayNameResolver.homeGreetingLabel(
        resolving: true,
        currentName: 'dono@loja.com',
      );
      expect(emailFlash, isNull);

      final uidFlash = StoreDisplayNameResolver.homeGreetingLabel(
        resolving: true,
        currentName: 'a1b2c3d4e5f6789012345678',
      );
      expect(uidFlash, isNull);

      final cachedOk = StoreDisplayNameResolver.homeGreetingLabel(
        resolving: true,
        currentName: 'Nathy Pratas e Folheados',
      );
      expect(cachedOk, 'Nathy Pratas e Folheados');

      final afterEmpty = StoreDisplayNameResolver.homeGreetingLabel(
        resolving: false,
        currentName: '',
      );
      expect(afterEmpty, 'Minha Loja');
    });

    test('ordem: firestore loja vence Hive e slug', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {'nome': 'Canônico FS'},
        hiveConfigStoreName: 'Hive Name',
        hiveSessaoNome: 'Sessao Name',
        slug: 'slug-name',
      );
      expect(r.name, 'Canônico FS');
      expect(r.source, 'firestore');
    });

    test('normaliza espaços extras', () {
      final r = StoreDisplayNameResolver.resolveFromSources(
        firestoreLoja: {'nome': '  Loja Trim  '},
      );
      expect(r.name, 'Loja Trim');
    });
  });
}
