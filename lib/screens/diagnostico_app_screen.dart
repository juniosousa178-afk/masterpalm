// lib/screens/diagnostico_app_screen.dart
// Tela de diagnóstico do app – apenas para programador.
// Analisa erros, problemas e o que está 100% OK para facilitar correções.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/hive_box_names.dart';
import '../debug/bootstrap_diagnostics.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../services/remote_config_service.dart';
import '../services/sync_queue_service.dart';
import '../services/loja_id_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/planos_service.dart';
import '../services/license_manager.dart';
import '../services/venda_item_migration_service.dart';

class DiagnosticoAppScreen extends StatefulWidget {
  const DiagnosticoAppScreen({super.key});

  @override
  State<DiagnosticoAppScreen> createState() => _DiagnosticoAppScreenState();
}

class _DiagnosticoAppScreenState extends State<DiagnosticoAppScreen> {
  late Future<DiagnosticoReport> _future;

  @override
  void initState() {
    super.initState();
    _verificarAcesso();
    _future = _executarDiagnostico();
  }

  void _verificarAcesso() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final sessao = Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
        final tipo = (sessao.get('tipo_usuario') as String?) ?? '';
        if (tipo != 'programador' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Acesso restrito ao programador')),
          );
          Navigator.of(context).pop();
        }
      } catch (_) {}
    });
  }

  Future<DiagnosticoReport> _executarDiagnostico() async {
    final r = DiagnosticoReport();

    // 1. Verificação de acesso (programador)
    try {
      final sessao = Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
      final tipo = (sessao.get('tipo_usuario') as String?) ?? '';
      if (tipo != 'programador') {
        r.addProblema('Acesso', 'Tela restrita a programador. Tipo atual: $tipo');
      } else {
        r.addOk('Acesso', 'Programador – acesso liberado');
      }
    } catch (e, st) {
      r.addErro('Acesso', e, st);
    }

    // 2. Firebase
    try {
      final app = Firebase.app();
      r.addOk('Firebase', 'Conectado (${app.options.projectId})');
    } catch (e, st) {
      r.addErro('Firebase', e, st);
    }

    // 3. Auth
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        r.addOk('Auth', user.email ?? user.uid);
      } else {
        r.addProblema('Auth', 'Nenhum usuário logado');
      }
    } catch (e, st) {
      r.addErro('Auth', e, st);
    }

    // 4. App Check
    try {
      final token = await FirebaseAppCheck.instance.getToken(false);
      if (token != null && token.isNotEmpty) {
        r.addOk('AppCheck', 'Token OK');
      } else {
        r.addProblema('AppCheck', 'Token vazio – cadastre Debug Token no Console');
      }
    } catch (e, st) {
      final msg = e.toString();
      if (msg.contains('403') || msg.contains('attestation failed')) {
        r.addProblema('AppCheck', 'Configure Debug Token no Firebase Console');
      } else {
        r.addErro('AppCheck', e, st);
      }
    }

    // 5. Firestore
    try {
      final col = FirebaseFirestore.instance.collection('_healthcheck');
      await col.doc('diag').set({'ts': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      r.addOk('Firestore', 'Read/Write OK');
    } catch (e, st) {
      r.addErro('Firestore', e, st);
    }

    // 6. Storage
    try {
      final ref = FirebaseStorage.instance.ref().child('_healthcheck/ping.txt');
      final data = Uint8List.fromList(('ok-${DateTime.now().toIso8601String()}').codeUnits);
      await ref.putData(data, SettableMetadata(contentType: 'text/plain')).timeout(const Duration(seconds: 5));
      r.addOk('Storage', 'Upload OK');
    } on TimeoutException {
      r.addProblema('Storage', 'Timeout – verifique rede');
    } catch (e, st) {
      r.addErro('Storage', e, st);
    }

    // 7. Hive
    try {
      final boxes = <String>[];
      for (final name in ['sessao', 'config', 'licenca']) {
        if (Hive.isBoxOpen(name)) boxes.add(name);
      }
      r.addOk('Hive (básico)', 'Boxes abertas: ${boxes.join(", ")}');

      final sessao = Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
      final storeId = sessao.get('store_id')?.toString() ?? '';
      final usuario = sessao.get('usuario_logado')?.toString() ?? '';
      r.detalhes['sessao_store_id'] = storeId.isEmpty ? '(vazio)' : storeId;
      r.detalhes['sessao_usuario'] = usuario.isEmpty ? '(vazio)' : usuario;

      if (storeId.isNotEmpty) {
        final countProd = Hive.isBoxOpen(HiveBoxNames.produtos(storeId)) ? Hive.box<Produto>(HiveBoxNames.produtos(storeId)).length : 0;
        final countCli = Hive.isBoxOpen(HiveBoxNames.clientes(storeId)) ? Hive.box<Cliente>(HiveBoxNames.clientes(storeId)).length : 0;
        final countVen = Hive.isBoxOpen(HiveBoxNames.vendas(storeId)) ? Hive.box<Venda>(HiveBoxNames.vendas(storeId)).length : 0;
        r.detalhes[HiveBoxNames.produtos(storeId)] = countProd.toString();
        r.detalhes[HiveBoxNames.clientes(storeId)] = countCli.toString();
        r.detalhes[HiveBoxNames.vendas(storeId)] = countVen.toString();
      }
    } catch (e, st) {
      r.addErro('Hive', e, st);
    }

    // 8. Sync Queue
    try {
      final pendentes = await SyncQueueService.pendingCount();
      if (pendentes == 0) {
        r.addOk('Sync Queue', 'Nenhum item pendente');
      } else {
        r.addProblema('Sync Queue', '$pendentes item(ns) aguardando sincronização');
      }
      r.detalhes['sync_pendentes'] = pendentes.toString();
    } catch (e, st) {
      r.addErro('Sync Queue', e, st);
    }

    // 9. LojaId / Store
    try {
      final lojaId = await LojaIdService.get();
      final storeResolved = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId != null && lojaId.isNotEmpty) {
        r.addOk('LojaId', lojaId);
      } else {
        r.addProblema('LojaId', 'Não definido (store_id vazio)');
      }
      r.detalhes['store_resolver'] = storeResolved ?? '(null)';
    } catch (e, st) {
      r.addErro('LojaId', e, st);
    }

    // 10. Remote Config
    try {
      r.addOk('Remote Config', 'recaptcha_site_key, globo_sorte_api_key, plano_precos');
      r.detalhes['recaptcha_ok'] = RemoteConfigService.recaptchaSiteKey.isNotEmpty ? 'sim' : 'não';
      r.detalhes['globo_sorte_api'] = RemoteConfigService.globoSorteApiKey.isNotEmpty ? 'configurado' : 'vazio';
    } catch (e, st) {
      r.addErro('Remote Config', e, st);
    }

    // 11. Licença / Plano
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final ok = await LicenseManager.hasValidAccessFallbackLegacy();
        if (ok) {
          r.addOk('Licença', 'Válida');
        } else {
          r.addProblema('Licença', 'Sem acesso válido – verifique plano');
        }
        try {
          final plan = await PlanosService().fetchCurrentPlan(uid: user.uid, email: user.email ?? '');
          r.detalhes['plano'] = plan?.planId ?? 'n/a';
          r.detalhes['plano_status'] = plan?.status ?? 'n/a';
        } catch (_) {
          r.detalhes['plano'] = 'erro ao buscar';
        }
      }
    } catch (e, st) {
      r.addErro('Licença', e, st);
    }

    // 12. Conectividade
    try {
      final results = await Connectivity().checkConnectivity();
      final temRede = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
      if (temRede) {
        r.addOk('Rede', 'Conectado');
      } else {
        r.addProblema('Rede', 'Sem conexão');
      }
      r.detalhes['connectivity'] = results.map((e) => e.name).join(', ');
    } catch (e, st) {
      r.addErro('Rede', e, st);
    }

    // 13. Boot trace
    try {
      r.detalhes['boot_trace'] = boot.dump();
    } catch (_) {}

    // 14. TODOs conhecidos (para referência)
    r.todosConhecidos = [
      'estoque_screen:699 – Integração marketplaces (wired)',
      'globo_sorteio_screen:199,243 – Sons da roleta (documentado)',
      'catalogo_venda_service:1080 – Nome loja (implementado)',
      'globo_sorte_service:230 – API Key (Remote Config)',
      'StoreAccessGuard – validação lojaId e auditoria boxes (implementado)',
      'docs/SYNC_FLUXO.md – fluxo sync e conflitos (documentado)',
    ];

    return r;
  }

  void _copiarRelatorio(DiagnosticoReport r) {
    final buf = StringBuffer();
    buf.writeln('═══ DIAGNÓSTICO MasterPalm ${DateTime.now()} ═══');
    buf.writeln();
    for (final item in r.itens) {
      buf.writeln('${item.ok ? "✅" : "❌"} ${item.area}: ${item.mensagem}');
    }
    buf.writeln();
    buf.writeln('--- Detalhes ---');
    for (final e in r.detalhes.entries) {
      buf.writeln('${e.key}: ${e.value}');
    }
    buf.writeln();
    buf.writeln('--- Erros ---');
    for (final e in r.erros) {
      buf.writeln(e);
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relatório copiado para a área de transferência')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico do App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copiar relatório',
            onPressed: () async {
              final r = await _future;
              if (context.mounted) _copiarRelatorio(r);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: () => setState(() => _future = _executarDiagnostico()),
          ),
        ],
      ),
      body: FutureBuilder<DiagnosticoReport>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;
          final okCount = r.itens.where((x) => x.ok).length;
          final total = r.itens.length;
          final score = total > 0 ? (okCount / total * 100).round() : 0;

          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _executarDiagnostico()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: score == 100 ? Colors.green.shade50 : (score >= 80 ? Colors.amber.shade50 : Colors.red.shade50),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Status geral',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$okCount de $total checks OK ($score%)',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: score == 100 ? Colors.green.shade800 : (score >= 80 ? Colors.amber.shade900 : Colors.red.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...r.itens.map((i) => _ItemTile(item: i)),
                const Divider(height: 32),
                const Text('Detalhes', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...r.detalhes.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 140, child: Text('${e.key}:', style: const TextStyle(fontSize: 12, color: Colors.black54))),
                      Expanded(child: SelectableText(e.value.toString(), style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                    ],
                  ),
                )),
                if (r.detalhes.containsKey('boot_trace') && (r.detalhes['boot_trace'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('Boot trace'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(r.detalhes['boot_trace']!.toString(), style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                      ),
                    ],
                  ),
                ],
                if (r.erros.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Erros (stack)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 8),
                  ...r.erros.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: SelectableText(e, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                    ),
                  )),
                ],
                const SizedBox(height: 16),
                const Text('TODOs conhecidos (referência)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...r.todosConhecidos.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t, style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                )),
                const SizedBox(height: 24),
                const Text('Migração (somente programador)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Preencher productId em itens de vendas antigas (match por nome exato, 1 produto). Não altera valores nem estoque.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.upgrade, size: 18),
                          label: const Text('Migrar productId (vendas antigas)'),
                          onPressed: () async {
                            final lojaId = await LojaIdService.get();
                            if (lojaId == null || lojaId.isEmpty) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Loja não definida. Faça login na loja.')),
                                );
                              }
                              return;
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Migrando... (veja o console)')),
                              );
                            }
                            final res = await VendaItemMigrationService.migrarLoja(lojaId);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Migração: ${res.vendasAlteradas} vendas alteradas, ${res.itensMigrados} itens com productId. '
                                  'Skip: ${res.itensJaComId} já tinham ID, ${res.itensSemMatch} sem match, ${res.itensAmbiguos} ambíguos.',
                                ),
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final DiagnosticoItemResult item;

  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          item.ok ? Icons.check_circle : Icons.error,
          color: item.ok ? Colors.green : Colors.red,
          size: 28,
        ),
        title: Text(item.area),
        subtitle: SelectableText(item.mensagem),
      ),
    );
  }
}

class DiagnosticoItemResult {
  final String area;
  final bool ok;
  final String mensagem;
  DiagnosticoItemResult(this.area, this.ok, this.mensagem);
}

class DiagnosticoReport {
  final List<DiagnosticoItemResult> itens = [];
  final List<String> erros = [];
  final Map<String, String> detalhes = {};
  List<String> todosConhecidos = [];

  void addOk(String area, String msg) => itens.add(DiagnosticoItemResult(area, true, msg));
  void addProblema(String area, String msg) => itens.add(DiagnosticoItemResult(area, false, msg));
  void addErro(String area, Object e, StackTrace? st) {
    itens.add(DiagnosticoItemResult(area, false, e.toString()));
    erros.add('[$area] $e\n${st ?? ''}');
  }
}
