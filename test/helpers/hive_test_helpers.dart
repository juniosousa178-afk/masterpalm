// test/helpers/hive_test_helpers.dart
// Helpers compartilhados para testes com Hive (registro de adapters, setup/teardown).

import 'dart:io';

import 'package:hive/hive.dart';

import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';

/// Registra adapters Hive necessários para testes de vendas/produtos/migração.
void registerHiveAdaptersForTests() {
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
}

/// Cria diretório temporário para Hive e inicializa. Retorna o path.
Future<String> initHiveForTests() async {
  final dir = await Directory.systemTemp.createTemp('hive_test_');
  Hive.init(dir.path);
  return dir.path;
}
