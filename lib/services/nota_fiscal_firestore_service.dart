// lib/services/nota_fiscal_firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/nota_fiscal.dart';
import 'nota_fiscal_service.dart';
import 'store_resolver_facade.dart';

/// Serviço para sincronizar notas fiscais com Firestore
class NotaFiscalFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sincroniza uma nota fiscal para o Firestore
  static Future<void> syncNotaFiscal(NotaFiscal nota, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) {
        debugPrint('❌ [NF-SYNC] LojaId vazio, não pode sincronizar');
        return;
      }

      // Usar idFirebase se existir, senão gerar novo
      final notaId = nota.idFirebase ?? nota.key?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

      // Salvar o idFirebase na nota
      if (nota.idFirebase != notaId) {
        nota.idFirebase = notaId;
        await nota.save();
      }

      final notaData = nota.toMap();
      notaData['id'] = notaId;

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notas_fiscais')
          .doc(notaId)
          .set(notaData, SetOptions(merge: true));

      debugPrint('✅ [NF-SYNC] Nota fiscal $notaId sincronizada');
    } catch (e) {
      debugPrint('❌ [NF-SYNC] Erro ao sincronizar nota (type=${e.runtimeType})');
    }
  }

  /// Sincroniza notas do Firestore para o Hive
  static Future<int> syncFirestoreToHive({
    required String lojaId,
    required Box<NotaFiscal> notasBox,
  }) async {
    try {
      debugPrint('🔄 [NF-SYNC] Sincronizando notas do Firestore → Hive...');

      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('notas_fiscais')
          .orderBy('dataEmissao', descending: true)
          .limit(100)
          .get();

      debugPrint('📦 [NF-SYNC] Encontradas ${snapshot.docs.length} notas no Firestore');

      int sincronizadas = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final notaId = doc.id;

          // Verificar se já existe pelo idFirebase
          final existe = notasBox.values.any((n) => n.idFirebase == notaId);
          if (existe) {
            debugPrint('⏭️  Nota $notaId já existe no Hive, pulando...');
            continue;
          }

          // Converter itens
          final itensData = data['itens'] as List? ?? [];
          final itens = itensData.map((i) {
            return NotaFiscalItem(
              produtoNome: i['produtoNome'] ?? '',
              codigoProduto: i['codigoProduto'],
              quantidade: (i['quantidade'] as num?)?.toInt() ?? 0,
              valorUnitario: (i['valorUnitario'] as num?)?.toDouble() ?? 0.0,
              valorTotal: (i['valorTotal'] as num?)?.toDouble() ?? 0.0,
              unidade: i['unidade'] ?? 'UN',
              ncm: i['ncm'],
              cfop: i['cfop'],
              aliquotaIcms: (i['aliquotaIcms'] as num?)?.toDouble(),
            );
          }).toList();

          // Criar nota
          final nota = NotaFiscal(
            numero: data['numero'] ?? '',
            serie: data['serie'] ?? '1',
            chaveAcesso: data['chaveAcesso'],
            status: NotaFiscalService.normalizarStatusApiParaApp(
              (data['status'] ?? 'pendente').toString(),
            ),
            vendaId: data['vendaId'],
            clienteNome: data['clienteNome'] ?? '',
            clienteCpfCnpj: data['clienteCpfCnpj'] ?? '',
            clienteEndereco: data['clienteEndereco'],
            clienteCidade: data['clienteCidade'],
            clienteEstado: data['clienteEstado'],
            clienteCep: data['clienteCep'],
            dataEmissao: DateTime.parse(data['dataEmissao']),
            valorTotal: (data['valorTotal'] as num?)?.toDouble() ?? 0.0,
            valorProdutos: (data['valorProdutos'] as num?)?.toDouble() ?? 0.0,
            valorFrete: (data['valorFrete'] as num?)?.toDouble() ?? 0.0,
            valorDesconto: (data['valorDesconto'] as num?)?.toDouble() ?? 0.0,
            itens: itens,
            baseCalculoIcms: (data['baseCalculoIcms'] as num?)?.toDouble() ?? 0.0,
            valorIcms: (data['valorIcms'] as num?)?.toDouble() ?? 0.0,
            protocoloAutorizacao: data['protocoloAutorizacao'],
            dataAutorizacao: data['dataAutorizacao'] != null
                ? DateTime.parse(data['dataAutorizacao'])
                : null,
            xmlUrl: data['xmlUrl'],
            pdfUrl: data['pdfUrl'],
            lojaId: lojaId,
            idFirebase: notaId,
            observacoes: data['observacoes'],
          );

          await notasBox.add(nota);
          sincronizadas++;

          debugPrint('✅ [NF-SYNC] Nota $notaId sincronizada do Firestore');
        } catch (e) {
          debugPrint('❌ [NF-SYNC] Erro ao sincronizar nota (type=${e.runtimeType})');
        }
      }

      debugPrint('✅ [NF-SYNC] $sincronizadas notas sincronizadas do Firestore → Hive');
      return sincronizadas;
    } catch (e) {
      debugPrint('❌ [NF-SYNC] Erro ao sincronizar do Firestore (type=${e.runtimeType})');
      return 0;
    }
  }

  /// Deleta uma nota fiscal do Firestore
  static Future<void> deleteNotaFiscal(String notaId, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notas_fiscais')
          .doc(notaId)
          .delete();

      debugPrint('🗑️ [NF-SYNC] Nota fiscal $notaId deletada do Firestore');
    } catch (e) {
      debugPrint('❌ [NF-SYNC] Erro ao deletar nota (type=${e.runtimeType})');
    }
  }

  /// Stream de notas fiscais
  static Stream<List<Map<String, dynamic>>> streamNotas({String? lojaId}) async* {
    final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
    if (storeId == null || storeId.isEmpty) {
      yield [];
      return;
    }

    yield* _db
        .collection('lojas')
        .doc(storeId)
        .collection('notas_fiscais')
        .orderBy('dataEmissao', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
