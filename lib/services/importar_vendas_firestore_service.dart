// lib/services/importar_vendas_firestore_service.dart
//
// Serviço dedicado para importar vendas do Firestore para o Hive
// SEM duplicar e SEM recalcular as já existentes.
// Importa APENAS as vendas que não estão no aparelho.
//
// Uso: ImportarVendasFirestoreService.importar(lojaId, vendasBox)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../models/venda.dart';
import 'firestore_paths.dart';
import '../models/venda_item.dart';
import 'vendas_firestore_service.dart';

/// Resultado da importação
class ImportarVendasResultado {
  final int totalNoFirestore;
  final int jaExistentes;
  final int importadas;
  final int erros;
  /// Mensagem de erro se a query falhou (ex: índice Firestore ausente)
  final String• erroMensagem;

  ImportarVendasResultado({
    required this.totalNoFirestore,
    required this.jaExistentes,
    required this.importadas,
    required this.erros,
    this.erroMensagem,
  });

  @override
  String toString() =>
      'ImportarVendasResultado(total=$totalNoFirestore, existentes=$jaExistentes, importadas=$importadas, erros=$erros)';
}

/// Serviço para importar vendas do Firestore sem duplicar.
/// Usa idFirebase como chave primária e (clienteNome, data, total) como fallback.
class ImportarVendasFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Importa vendas do Firestore para o Hive.
  /// - Não duplica: ignora vendas já existentes (por idFirebase ou por cliente+data+total)
  /// - Não recalcula: não altera vendas existentes, apenas adiciona novas
  /// - Retorna relatório com total no Firestore, quantas já existiam, quantas foram importadas
  /// - Fallback: se orderBy('data') falhar (ex: índice ausente), tenta get() sem orderBy
  static Future<ImportarVendasResultado> importar({
    required String lojaId,
    required Box<Venda> vendasBox,
  }) async {
    int totalNoFirestore = 0;
    int jaExistentes = 0;
    int importadas = 0;
    int erros = 0;
    String• erroMensagem;

    try {
      logD('📥 [IMPORT-VENDAS] Iniciando importação (lojaId=$lojaId, locais=${vendasBox.length})');

      const batchSize = 200;
      DocumentSnapshot• lastDoc;
      bool usarOrderBy = true;

      // Loop: com orderBy ou fallback sem orderBy (se índice Firestore faltar)
      while (true) {
        Query<Map<String, dynamic>> query;
        if (usarOrderBy) {
          query = _db
              .collection('lojas')
              .doc(lojaId)
              .collection(FSPaths.estoqueVendasCol)
              .orderBy('data', descending: true)
              .limit(batchSize);
          if (lastDoc != null) {
            query = query.startAfterDocument(lastDoc);
          }
        } else {
          // Fallback: get sem orderBy — startAfter não funciona sem orderBy, então só na 1ª página
          if (lastDoc != null) break; // já paginamos o que deu
          query = _db
              .collection('lojas')
              .doc(lojaId)
              .collection(FSPaths.estoqueVendasCol)
              .limit(500);
        }

        QuerySnapshot<Map<String, dynamic>> snapshot;
        try {
          snapshot = await query.get();
        } catch (e) {
          if (usarOrderBy) {
            logW('⚠️ [IMPORT-VENDAS] Query com orderBy falhou (índice?), tentando get() simples (erro: $e)');
            usarOrderBy = false;
            lastDoc = null;
            erroMensagem = e.toString();
            continue;
          }
          rethrow;
        }
        totalNoFirestore += snapshot.docs.length;

        if (snapshot.docs.isEmpty) break;

        for (final doc in snapshot.docs) {
          final vendaId = doc.id;
          try {
            final data = doc.data();
            final dataFirestore = (data['data'] as Timestamp?)?.toDate() ??
                (data['createdAt'] as Timestamp?)?.toDate() ??
                DateTime.now();
            final totalFirestore = (data['total'] as num?)?.toDouble() ?• 0.0;
            final clienteNome = (data['clienteNome'] ?• '').toString().trim();

            // 1) Verificar por idFirebase (funciona para UUID e IDs numéricos "0","1","74" etc)
            final existentePorId = vendasBox.values.firstWhereOrNull((v) => v.idFirebase == vendaId);
            if (existentePorId != null) {
              jaExistentes++;
              if (existentePorId.lojaId == null || existentePorId.lojaId!.isEmpty) {
                existentePorId.lojaId = lojaId;
                await existentePorId.save();
                logD('🔧 [IMPORT-VENDAS] Venda $vendaId: lojaId corrigido (legado)');
              }
              logD('⏭️ [IMPORT-VENDAS] Venda $vendaId já existe (idFirebase), pulando');
              continue;
            }

            // 2) IDs numéricos/legados: existePorDados pode dar falso positivo (duas vendas diferentes
            //    com mesmo cliente+total+segundo). Só usar para IDs não-UUID e com cuidado.
            final isUuid = vendaId.contains('-') && vendaId.length >= 36;
            if (!isUuid) {
              final existentePorDados = vendasBox.values.firstWhereOrNull((v) {
                if (v.clienteNome.trim() != clienteNome) return false;
                if ((v.total - totalFirestore).abs() > 0.01) return false;
                final d = v.data;
                return d.year == dataFirestore.year &&
                    d.month == dataFirestore.month &&
                    d.day == dataFirestore.day &&
                    d.hour == dataFirestore.hour &&
                    d.minute == dataFirestore.minute &&
                    d.second == dataFirestore.second;
              });

              if (existentePorDados != null) {
                jaExistentes++;
                // Atualizar idFirebase para que futuras importações usem idFirebase (mais confiável)
                if (existentePorDados.idFirebase != vendaId) {
                  existentePorDados.idFirebase = vendaId;
                  await existentePorDados.save();
                  logD('🔧 [IMPORT-VENDAS] Venda $vendaId: idFirebase atualizado (era ${existentePorDados.idFirebase})');
                }
                if (existentePorDados.lojaId == null || existentePorDados.lojaId!.isEmpty) {
                  existentePorDados.lojaId = lojaId;
                  await existentePorDados.save();
                }
                logD('⏭️ [IMPORT-VENDAS] Venda $vendaId já existe (cliente+data+total), pulando');
                continue;
              }
            }

            // 3) Converter e salvar (venda nova)
            final itensRaw = data['itens'] as List• ?• [];
            final itens = itensRaw.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              final pid = m['productId'] as String?;
              return VendaItem(
                produtoNome: m['produtoNome'] as String• ?• '',
                quantidade: (m['quantidade'] as num?)?.toInt() ?• 0,
                precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?• 0.0,
                tamanho: m['tamanho'] as String• ?• '',
                cor: m['cor'] as String• ?• '',
                productId: pid != null && pid.trim().isNotEmpty • pid : null,
              );
            }).toList();

            final venda = Venda(
              clienteNome: data['clienteNome'] ?• '',
              produtosDescricao: data['produtosDescricao'] ?• '',
              quantidade: (data['quantidade'] as num?)?.toInt() ?• itens.length,
              preco: (data['preco'] as num?)?.toDouble() ?• 0.0,
              total: (data['total'] as num?)?.toDouble() ?• 0.0,
              formasPagamento: data['formasPagamento'] ?• '',
              data: dataFirestore,
              tamanho: data['tamanho'] ?• '',
              vendedor: data['vendedor'] ?• '',
              frete: (data['frete'] as num?)?.toDouble() ?• 0.0,
              desconto: (data['desconto'] as num?)?.toDouble() ?• 0.0,
              observacao: data['observacao'] ?• '',
              itens: itens.isNotEmpty • itens : null,
              pagamentoDinheiro: (data['pagamentoDinheiro'] as num?)?.toDouble() ?• 0.0,
              pagamentoPix: (data['pagamentoPix'] as num?)?.toDouble() ?• 0.0,
              pagamentoCartao: (data['pagamentoCartao'] as num?)?.toDouble() ?• 0.0,
              taxas: (data['taxas'] as num?)?.toDouble() ?• 0.0,
              custoProdutos: (data['custoProdutos'] as num?)?.toDouble() ?• 0.0,
              descontoValor: (data['descontoValor'] as num?)?.toDouble() ?• 0.0,
              lojaId: lojaId,
              idFirebase: vendaId,
              clienteId: data['clienteId'] as String?,
            );

            await vendasBox.add(venda);
            importadas++;
            logD('✅ [IMPORT-VENDAS] Venda $vendaId importada (cliente=${venda.clienteNome}, total=R\$${venda.total.toStringAsFixed(2)})');
          } catch (e, st) {
            erros++;
            logE('❌ [IMPORT-VENDAS] Erro ao importar venda $vendaId (type=${e.runtimeType})', error: e, st: st);
          }
        }

        if (snapshot.docs.length < batchSize) break;
        lastDoc = snapshot.docs.last;
      }

      logD('📦 [IMPORT-VENDAS] Concluído: Firestore=$totalNoFirestore | já existentes=$jaExistentes | importadas=$importadas | erros=$erros');
      return ImportarVendasResultado(
        totalNoFirestore: totalNoFirestore,
        jaExistentes: jaExistentes,
        importadas: importadas,
        erros: erros,
        erroMensagem: erroMensagem,
      );
    } catch (e, st) {
      logE('❌ [IMPORT-VENDAS] Erro geral (type=${e.runtimeType})', error: e, st: st);
      return ImportarVendasResultado(
        totalNoFirestore: totalNoFirestore,
        jaExistentes: jaExistentes,
        importadas: importadas,
        erros: erros + 1,
        erroMensagem: e.toString(),
      );
    }
  }

  /// Wrapper que usa o serviço padrão (VendasFirestoreService.syncFirestoreToHive)
  /// e retorna no formato ImportarVendasResultado.
  /// Use este se preferir a lógica original (apenas idFirebase).
  static Future<ImportarVendasResultado> importarViaSyncPadrao({
    required String lojaId,
    required Box<Venda> vendasBox,
  }) async {
    final localAntes = vendasBox.length;
    final importadas = await VendasFirestoreService.syncFirestoreToHive(
      lojaId: lojaId,
      vendasBox: vendasBox,
    );
    return ImportarVendasResultado(
      totalNoFirestore: localAntes + importadas, // aproximado
      jaExistentes: 0,
      importadas: importadas,
      erros: 0,
    );
  }
}
