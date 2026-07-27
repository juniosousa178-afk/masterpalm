import 'package:path/path.dart' as p;

import 'package:masterpalm_platform/masterpalm_platform.dart';

import 'diff_analyzer.dart';
import 'guardian_config.dart';
import 'models/impact_result.dart';

class ImpactAnalyzer {
  ImpactAnalyzer({
    required this.config,
    required this.ast,
  });

  final GuardianConfig config;
  final AstProvider ast;

  static const _domainPatterns = <String, List<String>>{
    'Estoque': [
      'estoque_transaction',
      'estoque_service',
      'movimentacao_estoque',
      'estoque_produtos',
      'estoque_baixa_pagamento',
    ],
    'Financeiro': [
      'financeiro',
      'conta_receber',
      'conta_pagar',
      'lancamento_financeiro',
      'fechamento',
    ],
    'PDV': ['nova_venda', 'vendas_service', 'pdv_v1', 'sale_intent'],
    'Venda': ['vendas_service', 'vendas_firestore', 'nova_venda'],
    'Consignado': ['consignado', 'm39_consignado'],
    'Fiado': ['conta_receber', 'fiado', 'contas_receber'],
    'Compras': ['compra_fornecedor', 'compra_para_pipeline', 'compras/'],
    'Sync': [
      'sync_queue',
      'full_sync',
      'catalogo_sync',
      'firestore_critical_listener',
      'auto_sync',
    ],
    'Offline': ['venda_operation_journal', 'offline_recovery', 'sync_queue_replay'],
    'Firestore': ['firestore', '.collection(', 'runTransaction', '.batch('],
    'Hive': ['hive', 'HiveBoxNames', 'Hive.box', 'Hive.openBox'],
    'Auth': ['auth_service', 'cliente_auth', 'login_screen'],
    'Tenant': ['loja_id', 'store_resolver', 'tenant'],
    'Catálogo': [
      'public_catalog',
      'catalogo_venda',
      'catalog_publish',
      'pre_pedido',
    ],
    'Cloud Functions': ['functions/', 'mp_functions', 'cloud_functions'],
    'Segurança': ['firestore.rules', 'storage.rules', 'permissao'],
    'Performance': ['public_catalog_screen', 'listener', 'snapshots', 'Stream'],
  };

  static const _serviceScreens = <String, List<String>>{
    'estoque_transaction_service.dart': [
      'nova_venda_modal.dart',
      'estoque_screen.dart',
      'pre_pedidos_screen.dart',
      'public_catalog_screen.dart',
    ],
    'vendas_service.dart': [
      'nova_venda_modal.dart',
      'vendas_screen.dart',
    ],
    'loja_id_service.dart': [
      'main.dart',
      'home_screen.dart',
      'app_start_router.dart',
    ],
    'full_sync_service.dart': [
      'login_screen.dart',
      'app_start_router.dart',
    ],
  };

  static const _domainFlows = <String, List<String>>{
    'Estoque': ['flows/venda.md', 'flows/inventario.md'],
    'Financeiro': ['flows/financeiro.md', 'flows/consignado-fiado.md'],
    'PDV': ['flows/venda.md'],
    'Sync': ['flows/sync.md'],
    'Auth': ['flows/auth.md'],
    'Catálogo': ['flows/catalogo.md'],
  };

  static const _domainRcas = <String, List<String>>{
    'Estoque': ['docs/engineering/RCA/RCA-001-Thawana-LastWriteWins.md'],
    'Tenant': ['docs/engineering/RCA/RCA-001-Thawana-LastWriteWins.md'],
  };

  static const _domainRunbooks = <String, List<String>>{
    'Estoque': ['docs/engineering/Runbooks/'],
    'Sync': ['docs/engineering/Runbooks/'],
    'Financeiro': ['docs/engineering/Runbooks/'],
  };

  ImpactResult analyze(DiffAnalysis diff) {
    final domains = <String>{};
    final services = <String>{};
    final screens = <String>{};
    final collections = <String>{...diff.firestoreTouched};
    final boxes = <String>{...diff.hiveTouched};
    final flows = <String>{};
    final rcas = <String>{};
    final runbooks = <String>{};
    final callers = <String>{};

    for (final change in diff.changes) {
      final path = change.path.replaceAll('\\', '/');
      _matchDomains(path, domains);
      for (final line in change.addedLines) {
        if (path.startsWith('docs/') || path.startsWith('test/')) continue;
        if (path.contains('firestore.rules') || path.contains('storage.rules')) {
          continue;
        }
        _matchDomains(line, domains);
      }

      if (path.contains('lib/services/')) {
        services.add(p.basename(path));
      }
      if (path.contains('lib/screens/')) {
        screens.add(p.basename(path));
      }

      for (final entry in _serviceScreens.entries) {
        if (path.contains(entry.key)) {
          screens.addAll(entry.value);
        }
      }

      callers.addAll(ast.callersForFile(path));
    }

    for (final d in domains) {
      flows.addAll(_domainFlows[d] ?? []);
      rcas.addAll(_domainRcas[d] ?? []);
      runbooks.addAll(_domainRunbooks[d] ?? []);
    }

    for (final cf in config.criticalFiles) {
      for (final change in diff.changes) {
        if (!change.path.contains(cf.path)) continue;
        for (final domain in cf.domains) {
          if (_hunksMatchDomain(change, domain)) {
            domains.add(domain);
          }
        }
      }
    }

    return ImpactResult(
      domains: domains.toList()..sort(),
      services: services.toList()..sort(),
      screens: screens.toList()..sort(),
      firestoreCollections: collections.toList()..sort(),
      hiveBoxes: boxes.toList()..sort(),
      flows: flows.toList()..sort(),
      callers: callers.toList(),
      callees: const [],
      relatedRcas: rcas.toList()..sort(),
      relatedRunbooks: runbooks.toList()..sort(),
    );
  }

  void _matchDomains(String text, Set<String> domains) {
    for (final entry in _domainPatterns.entries) {
      for (final pattern in entry.value) {
        if (text.toLowerCase().contains(pattern.toLowerCase())) {
          domains.add(entry.key);
        }
      }
    }
  }

  bool _hunksMatchDomain(FileChange change, String domain) {
    final patterns = _domainPatterns[domain] ?? [];
    if (patterns.isEmpty) return false;
    final path = change.path.replaceAll('\\', '/');
    if (path.startsWith('docs/') ||
        path.startsWith('test/') ||
        path.contains('firestore.rules') ||
        path.contains('storage.rules')) {
      return false;
    }
    if (_matchAny(path, patterns)) return true;
    for (final line in [...change.addedLines, ...change.removedLines]) {
      if (_matchAny(line, patterns)) return true;
    }
    return false;
  }

  bool _matchAny(String text, List<String> patterns) {
    final lower = text.toLowerCase();
    for (final pattern in patterns) {
      if (lower.contains(pattern.toLowerCase())) return true;
    }
    return false;
  }
}
