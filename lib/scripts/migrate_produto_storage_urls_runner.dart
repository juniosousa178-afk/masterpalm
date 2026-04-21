// lib/scripts/migrate_produto_storage_urls_runner.dart
// Lógica de migração de URLs de imagens (Storage) em produtos.
// Executar via: fvm flutter test test/migrate_produto_storage_urls_test.dart
// ou (Firebase real, embedder): fvm flutter run -t lib/migrate_produto_storage_urls_entry.dart
// (não use `dart run` puro — cloud_firestore exige o runtime Flutter.)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:master_palm/firebase_options.dart';
import 'package:master_palm/scripts/migrate_log.dart';
import 'package:master_palm/scripts/migration_env.dart';
import 'package:master_palm/screens/public_catalog/catalog_storage_image_url_resolver.dart';

const _liveCol = 'produtos';
const _draftCol = 'draft_produtos';

class MigrateProdutoUrlsResult {
  MigrateProdutoUrlsResult({
    required this.lojasProcessed,
    required this.documentsWouldChange,
    required this.writesApplied,
  });

  final int lojasProcessed;
  final int documentsWouldChange;
  final int writesApplied;
}

class MigrateProdutoUrlsOptions {
  MigrateProdutoUrlsOptions({
    required this.allLojas,
    this.singleLojaId,
    required this.includeDraft,
    required this.commit,
    required this.limitPerCollection,
  });

  /// Percorre todos os documentos em [lojas].
  final bool allLojas;

  /// Ignorado quando [allLojas] é true.
  final String? singleLojaId;

  final bool includeDraft;
  final bool commit;

  /// Máximo de produtos por coleção por loja (0 = sem limite).
  final int limitPerCollection;
}

Future<List<String>> _listAllLojaIds(FirebaseFirestore db) async {
  const page = 200;
  final ids = <String>[];
  DocumentSnapshot<Map<String, dynamic>>? cursor;
  while (true) {
    Query<Map<String, dynamic>> q = db
        .collection('lojas')
        .orderBy(FieldPath.documentId)
        .limit(page);
    final prev = cursor;
    if (prev != null) {
      q = q.startAfterDocument(prev);
    }
    final snap = await q.get();
    if (snap.docs.isEmpty) break;
    for (final d in snap.docs) {
      ids.add(d.id);
    }
    cursor = snap.docs.last;
    if (snap.docs.length < page) break;
  }
  return ids;
}

Future<MigrateProdutoUrlsResult> runMigrateProdutoStorageUrls(
  MigrateProdutoUrlsOptions options,
) async {
  if (!options.allLojas) {
    final id = options.singleLojaId?.trim() ?? '';
    if (id.isEmpty) {
      throw ArgumentError(
        'singleLojaId é obrigatório quando allLojas=false.',
      );
    }
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (options.commit) {
    final email = migrationEnvString('MP_MIGRATION_EMAIL').trim();
    final password = migrationEnvString('MP_MIGRATION_PASSWORD');
    if (email.isEmpty || password.isEmpty) {
      throw StateError(
        'Com commit=true defina MP_MIGRATION_EMAIL e MP_MIGRATION_PASSWORD.',
      );
    }
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    migrateLogOut('✅ Auth OK: ${FirebaseAuth.instance.currentUser?.email}');
  }

  final db = FirebaseFirestore.instance;
  var totalDocs = 0;
  var totalWrites = 0;
  var lojasCount = 0;

  final lojaIds = options.allLojas
      ? await _listAllLojaIds(db)
      : [(options.singleLojaId ?? '').trim()];

  migrateLogOut(
    options.allLojas
        ? '\n── Modo: TODAS AS LOJAS (${lojaIds.length} documentos em lojas/) ──'
        : '\n── Modo: loja única (${lojaIds.first}) ──',
  );

  for (final lojaId in lojaIds) {
    lojasCount++;
    migrateLogOut('\n▶ Loja $lojasCount/${lojaIds.length}: $lojaId');

    Future<void> runCol(String col) async {
      Query<Map<String, dynamic>> q =
          db.collection('lojas').doc(lojaId).collection(col);
      if (options.limitPerCollection > 0) {
        q = q.limit(options.limitPerCollection);
      }
      final snap = await q.get();
      migrateLogOut('  Coleção $col — ${snap.docs.length} docs');

      WriteBatch? batch;
      var batchCount = 0;

      Future<void> flushBatch() async {
        if (batch == null || batchCount == 0) return;
        if (options.commit) {
          await batch!.commit();
          totalWrites += batchCount;
        }
        batch = null;
        batchCount = 0;
      }

      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final patch = <String, dynamic>{};
        var touched = false;

        for (final key in ['imageUrl', 'imagem_principal']) {
          final v = data[key];
          if (v is! String || v.isEmpty) continue;
          if (!isCatalogFirebaseStorageMediaUrl(v)) continue;
          final next = await resolveCatalogFirebaseStorageDownloadUrl(v, lojaId);
          if (next != v) {
            patch[key] = next;
            touched = true;
            migrateLogOut('  [${doc.id}] $key');
            migrateLogOut(
                '    de: ${v.length > 120 ? "${v.substring(0, 120)}…" : v}');
            migrateLogOut(
                '    p/: ${next.length > 120 ? "${next.substring(0, 120)}…" : next}');
          }
        }

        final imgs = data['imagens'];
        if (imgs is List && imgs.isNotEmpty) {
          final out = <dynamic>[];
          var listChanged = false;
          for (final e in imgs) {
            final s = e?.toString() ?? '';
            if (s.isEmpty || !isCatalogFirebaseStorageMediaUrl(s)) {
              out.add(e);
              continue;
            }
            final next =
                await resolveCatalogFirebaseStorageDownloadUrl(s, lojaId);
            out.add(next);
            if (next != s) listChanged = true;
          }
          if (listChanged) {
            patch['imagens'] = out;
            touched = true;
            migrateLogOut(
                '  [${doc.id}] imagens (${imgs.length} itens, lista reescrita)');
          }
        }

        if (touched) {
          totalDocs++;
          if (options.commit) {
            batch ??= db.batch();
            batch!.update(doc.reference, patch);
            batchCount++;
            if (batchCount >= 400) {
              await batch!.commit();
              totalWrites += batchCount;
              batch = null;
              batchCount = 0;
            }
          }
        }
      }

      if (options.commit) {
        await flushBatch();
      }
    }

    await runCol(_liveCol);
    if (options.includeDraft) {
      await runCol(_draftCol);
    }
  }

  migrateLogOut('\n── Resumo ──');
  migrateLogOut('Lojas processadas: $lojasCount');
  migrateLogOut('Documentos de produto com alteração: $totalDocs');
  if (options.commit) {
    migrateLogOut('Updates aplicados (operações em batch): $totalWrites');
  } else {
    migrateLogOut(
        'Dry-run: nada foi gravado. commit=true + env admin para aplicar.');
  }

  if (FirebaseAuth.instance.currentUser != null) {
    await FirebaseAuth.instance.signOut();
  }

  return MigrateProdutoUrlsResult(
    lojasProcessed: lojasCount,
    documentsWouldChange: totalDocs,
    writesApplied: totalWrites,
  );
}

/// Lê opções (shell e/ou `--dart-define`) e executa a migração.
///
/// Lança [StateError] com mensagem legível se a configuração for inválida.
Future<MigrateProdutoUrlsResult> runMigrateProdutoStorageUrlsFromEnvironment() async {
  final all = migrationEnvFlag('MP_MIGRATION_ALL_LOJAS');
  final lojaRaw = migrationEnvString('MP_MIGRATION_LOJA_ID').trim();
  final lojaId = lojaRaw.isEmpty ? null : lojaRaw;
  if (!all && (lojaId == null || lojaId.isEmpty)) {
    throw StateError(
      'Defina MP_MIGRATION_ALL_LOJAS=true ou MP_MIGRATION_LOJA_ID=<id>. '
      'Na Web use também: flutter run ... --dart-define=MP_MIGRATION_ALL_LOJAS=true '
      '(variáveis do PowerShell não chegam ao browser). Ver test/migrate_produto_storage_urls_test.dart.',
    );
  }
  if (all && lojaId != null && lojaId.isNotEmpty) {
    migrateLogErr(
      'Aviso: MP_MIGRATION_ALL_LOJAS está ativo; MP_MIGRATION_LOJA_ID será ignorado.',
    );
  }

  final commit = migrationEnvFlag('MP_MIGRATION_COMMIT');
  if (commit) {
    final email = migrationEnvString('MP_MIGRATION_EMAIL').trim();
    final password = migrationEnvString('MP_MIGRATION_PASSWORD');
    if (email.isEmpty || password.isEmpty) {
      throw StateError(
        'Com MP_MIGRATION_COMMIT=true defina MP_MIGRATION_EMAIL e MP_MIGRATION_PASSWORD.',
      );
    }
  }

  final includeDraft = migrationEnvFlag('MP_MIGRATION_INCLUDE_DRAFT');
  final limit = int.tryParse(migrationEnvString('MP_MIGRATION_LIMIT').trim()) ?? 0;

  return runMigrateProdutoStorageUrls(
    MigrateProdutoUrlsOptions(
      allLojas: all,
      singleLojaId: lojaId,
      includeDraft: includeDraft,
      commit: commit,
      limitPerCollection: limit,
    ),
  );
}
