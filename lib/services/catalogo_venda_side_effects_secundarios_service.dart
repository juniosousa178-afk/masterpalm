// Side-effects secundários do catálogo (denorm, admin, cupom, origem, campanha).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'campaign_engine_service.dart';
import 'firestore_paths.dart';
import 'notificacao_vendas_service.dart';
import 'produto_vendas_catalogo_denorm_service.dart';
import 'vendas_firestore_service.dart';

/// Restaura efeitos de `CatalogoVendaService.registrarVendaCatalogo` ausentes
/// no fluxo admin `pre_pedidos` + Sale Intent.
class CatalogoVendaSideEffectsSecundariosService {
  static const String _markerCollection = 'catalogo_side_effects_secundarios';

  static FirebaseFirestore? debugFirestoreOverride;
  static Future<void> Function({
    required String lojaId,
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
  })? debugDenormOverride;
  static Future<void> Function({
    required String storeId,
    required String pedidoId,
    required String clienteNome,
    required double valorTotal,
    required String origem,
    String? vendedorNome,
    bool pagamentoConfirmado,
  })? debugNotificacaoOverride;
  static Future<void> Function({
    required FirebaseFirestore db,
    required String lojaId,
    required String emailNorm,
    required String cupomCodigo,
    required String descricao,
    required double valor,
  })? debugCupomOverride;
  static Future<ParticipacaoResult> Function({
    required String lojaId,
    required Venda venda,
    required String vendaId,
    required String clienteNome,
    String? clienteId,
    String? telefone,
    String? email,
    required double valorTotal,
  })? debugCampaignOverride;
  static Future<bool> Function(Venda venda, {String? lojaId})?
      debugSyncVendaOverride;

  FirebaseFirestore get _db => debugFirestoreOverride ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _markerRef(String lojaId, String vendaId) =>
      _db.collection('lojas').doc(lojaId).collection(_markerCollection).doc(vendaId);

  /// Não propaga exceção: efeitos secundários não devem bloquear confirmação.
  Future<void> aplicarAposVendaCatalogoAdmin({
    required String lojaId,
    required Venda venda,
    required String vendaId,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
    required double total,
    Map<String, dynamic>? premioRoletaRaw,
    String? vendedorNome,
  }) async {
    await _aplicarOrigemVenda(lojaId: lojaId, venda: venda);

    final markerSnap = await _markerRef(lojaId, vendaId).get();
    final marker = markerSnap.data() ?? <String, dynamic>{};

    await _aplicarDenorm(
      lojaId: lojaId,
      vendaId: vendaId,
      items: items,
      produtosBox: produtosBox,
      jaAplicado: marker['denormAplicado'] == true,
    );

    await _aplicarNotificacaoAdmin(
      lojaId: lojaId,
      vendaId: vendaId,
      customer: customer,
      total: total,
      vendedorNome: vendedorNome,
      jaEnviada: marker['notificacaoAdminEnviada'] == true,
    );

    await _aplicarCupomRoletaPerfil(
      lojaId: lojaId,
      vendaId: vendaId,
      customer: customer,
      premioRoletaRaw: premioRoletaRaw,
      jaSalvo: marker['cupomSalvo'] == true,
    );

    await _aplicarCampanha(
      lojaId: lojaId,
      venda: venda,
      vendaId: vendaId,
      customer: customer,
      total: total,
      jaRegistrada: marker['campanhaRegistrada'] == true,
    );
  }

  Future<void> _aplicarOrigemVenda({
    required String lojaId,
    required Venda venda,
  }) async {
    try {
      if ((venda.origemVenda ?? '').trim() != 'catalogo_web') {
        venda.origemVenda = 'catalogo_web';
        await venda.save();
      }
      try {
        if (debugSyncVendaOverride != null) {
          await debugSyncVendaOverride!(venda, lojaId: lojaId);
        } else {
          await VendasFirestoreService.syncVenda(venda, lojaId: lojaId);
        }
      } catch (e, st) {
        logE(
          '⚠️ [CAT_SIDE] sync origemVenda não crítico (type=${e.runtimeType})',
          error: e,
          st: st,
        );
      }
    } catch (e, st) {
      logE(
        '⚠️ [CAT_SIDE] origemVenda não crítico (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }

  Future<void> _aplicarDenorm({
    required String lojaId,
    required String vendaId,
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
    required bool jaAplicado,
  }) async {
    if (jaAplicado) return;
    try {
      if (debugDenormOverride != null) {
        await debugDenormOverride!(
          lojaId: lojaId,
          items: items,
          produtosBox: produtosBox,
        );
      } else {
        await ProdutoVendasCatalogoDenormService.incrementarAposVendaCatalogo(
          lojaId: lojaId,
          items: items,
          produtosBox: produtosBox,
        );
      }
      await _markerRef(lojaId, vendaId).set(
        {'denormAplicado': true, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e, st) {
      logE(
        '⚠️ [CAT_SIDE] denorm não crítico (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }

  Future<void> _aplicarNotificacaoAdmin({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    required double total,
    String? vendedorNome,
    required bool jaEnviada,
  }) async {
    if (jaEnviada) return;
    try {
      final clienteNome = (customer['nome'] ?? 'Cliente').toString();
      if (debugNotificacaoOverride != null) {
        await debugNotificacaoOverride!(
          storeId: lojaId,
          pedidoId: vendaId,
          clienteNome: clienteNome,
          valorTotal: total,
          origem: 'catalogo_web',
          vendedorNome: vendedorNome,
          pagamentoConfirmado: true,
        );
      } else {
        await NotificacaoVendasService().notificarAdminNovaVenda(
          storeId: lojaId,
          pedidoId: vendaId,
          clienteNome: clienteNome,
          valorTotal: total,
          origem: 'catalogo_web',
          vendedorNome: vendedorNome,
          pagamentoConfirmado: true,
        );
      }
      await _markerRef(lojaId, vendaId).set(
        {
          'notificacaoAdminEnviada': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      logE(
        '⚠️ [CAT_SIDE] notificação admin não crítica (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }

  Future<void> _aplicarCupomRoletaPerfil({
    required String lojaId,
    required String vendaId,
    required Map<String, dynamic> customer,
    Map<String, dynamic>? premioRoletaRaw,
    required bool jaSalvo,
  }) async {
    if (jaSalvo) return;

    final cupomCodigo = premioRoletaRaw?['codigo']?.toString().trim() ?? '';
    final email = (customer['email'] ?? '').toString().trim();
    if (cupomCodigo.isEmpty || email.isEmpty) return;

    try {
      final emailNorm = email.toLowerCase();
      final cupomDesconto = (premioRoletaRaw?['valor'] as num?)?.toDouble();
      final descricaoRaw = premioRoletaRaw?['descricao']?.toString();
      final descricao = descricaoRaw != null && descricaoRaw.isNotEmpty
          ? descricaoRaw
          : '${(cupomDesconto ?? 0).toStringAsFixed(0)}% de desconto';
      final dataExpiracao = DateTime.now().add(const Duration(days: 60));

      if (debugCupomOverride != null) {
        await debugCupomOverride!(
          db: _db,
          lojaId: lojaId,
          emailNorm: emailNorm,
          cupomCodigo: cupomCodigo,
          descricao: descricao,
          valor: cupomDesconto ?? 0.0,
        );
      } else {
        await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.clientesCatalogoCol)
            .doc(emailNorm)
            .collection('cupons')
            .doc(cupomCodigo)
            .set({
          'codigo': cupomCodigo,
          'descricao': descricao,
          'tipo': 'desconto',
          'valor': cupomDesconto ?? 0.0,
          'dataGanho': FieldValue.serverTimestamp(),
          'dataExpiracao': Timestamp.fromDate(dataExpiracao),
          'usado': false,
          'ativo': true,
          'origem': 'roleta_sorte',
        });
      }

      await _markerRef(lojaId, vendaId).set(
        {'cupomSalvo': true, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      logD('🎁 [CAT_SIDE] Cupom roleta salvo no perfil: $cupomCodigo');
    } catch (e, st) {
      logE(
        '⚠️ [CAT_SIDE] cupom perfil não crítico (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }

  Future<void> _aplicarCampanha({
    required String lojaId,
    required Venda venda,
    required String vendaId,
    required Map<String, dynamic> customer,
    required double total,
    required bool jaRegistrada,
  }) async {
    if (jaRegistrada) return;
    try {
      final clienteNome = (customer['nome'] ?? venda.clienteNome).toString();
      final email = (customer['email'] ?? '').toString();
      final telefone =
          (customer['telefone'] ?? customer['tel'] ?? '').toString();
      final clienteId =
          customer['id']?.toString() ?? customer['clienteId']?.toString();

      ParticipacaoResult resultado;
      if (debugCampaignOverride != null) {
        resultado = await debugCampaignOverride!(
          lojaId: lojaId,
          venda: venda,
          vendaId: vendaId,
          clienteNome: clienteNome,
          clienteId: clienteId,
          telefone: telefone,
          email: email,
          valorTotal: total,
        );
      } else {
        resultado = await CampaignEngineService.onVendaConcluida(
          lojaId: lojaId,
          venda: venda,
          vendaId: vendaId,
          clienteNome: clienteNome,
          clienteId: clienteId,
          telefone: telefone,
          email: email,
          valorTotal: total,
          origem: 'catalogo',
          nomeLoja: lojaId,
        );
      }

      if (resultado.sucesso ||
          (resultado.erro ?? '').toLowerCase().contains('já gerou')) {
        await _markerRef(lojaId, vendaId).set(
          {
            'campanhaRegistrada': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (e, st) {
      logE(
        '⚠️ [CAT_SIDE] campanha não crítica (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }
}
