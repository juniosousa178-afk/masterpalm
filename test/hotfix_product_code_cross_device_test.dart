// RECOVERY.2.1 — código de produto cross-device (FakeFirestore + Hive).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/firestore_access_guard.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-cross-device-code';
const _pid = 'product-cross-device-001';
const _code = '000ABC123';

Future<void> _seedDeviceA(FakeFirebaseFirestore db) async {
  await db
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(_pid)
      .set({
    'nome': 'Produto Cross Device',
    'quantidade': 10,
    'slug': _pid,
    'codigoBarras': _code,
    'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 20, 10)),
    'stockRevision': 0,
  });
}

Future<Box<Produto>> _openEmptyHiveBox() async {
  final name = 'prod_cross_${DateTime.now().microsecondsSinceEpoch}';
  return Hive.openBox<Produto>(name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cross_code_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    FirestoreAccessGuard.forbidAccess = false;
  });

  tearDown(() {
    ProdutosFirestoreService.debugFirestoreOverride = null;
  });

  test('Device B pull preenche codigoBarras vazio a partir do Firestore', () async {
    await _seedDeviceA(firestore);
    final boxB = await _openEmptyHiveBox();

    final n = await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _lojaId,
      produtosBox: boxB,
    );
    expect(n, greaterThanOrEqualTo(0));

    final p = boxB.values.firstWhere((x) => x.idFirebase == _pid);
    expect(p.codigoBarras, _code);
    expect(p.nome, 'Produto Cross Device');

    await boxB.close();
  });

  test('mergeRemoteCodigoBarras preenche local vazio sob preserveLocalEdits', () {
    final p = Produto.vazio()
      ..codigoBarras = ''
      ..updatedAt = DateTime(2026, 8, 1);
    ProdutosFirestoreService.mergeRemoteCodigoBarrasWhenPreservingLocalEdits(
      local: p,
      remoteData: {'codigoBarras': _code},
    );
    expect(p.codigoBarras, _code);
  });

  test('mergeRemoteCodigoBarras não apaga código local válido se remoto ausente', () {
    final p = Produto.vazio()..codigoBarras = 'LOCAL123';
    ProdutosFirestoreService.mergeRemoteCodigoBarrasWhenPreservingLocalEdits(
      local: p,
      remoteData: {},
    );
    expect(p.codigoBarras, 'LOCAL123');
  });
}
