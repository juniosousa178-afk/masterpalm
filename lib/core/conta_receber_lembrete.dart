// Avaliação do lembrete de cobrança da Home (fiado / contas a receber).
// Hive só gera candidatos; a decisão de alertar valida o remoto (servidor).

import 'package:flutter/foundation.dart';

import '../models/conta_receber.dart';
import '../services/conta_receber_firestore_service.dart';
import '../services/conta_receber_service.dart';
import 'conta_receber_identity.dart';

class ContaReceberLembreteResultado {
  final List<ContaReceber> vencidas;
  final List<ContaReceber> vencendo;

  const ContaReceberLembreteResultado({
    required this.vencidas,
    required this.vencendo,
  });

  bool get deveAlertar => vencidas.isNotEmpty || vencendo.isNotEmpty;

  double get valorTotal =>
      (vencidas + vencendo).fold<double>(0, (s, c) => s + c.valor);

  static const ContaReceberLembreteResultado vazio =
      ContaReceberLembreteResultado(vencidas: [], vencendo: []);
}

/// Home: candidatos no Hive + validação server-backed antes do alerta.
/// Política de falha remota: [SUPPRESS_ALERT] — não cobra com cache stale.
abstract final class ContaReceberLembreteCobranca {
  ContaReceberLembreteCobranca._();

  static const String falhaRemotaPolicy = 'SUPPRESS_ALERT';

  static final Map<String, Future<ContaReceberLembreteResultado>> _inFlight =
      <String, Future<ContaReceberLembreteResultado>>{};

  @visibleForTesting
  static Future<void> Function()? debugForcarFalhaValidacaoRemota;

  @visibleForTesting
  static Duration? debugAtrasoValidacaoRemota;

  @visibleForTesting
  static void resetPullSessaoParaTeste() => invalidarSessao();

  /// Logout / novo login: descarta in-flight e qualquer estado de sessão.
  static void invalidarSessao() {
    _inFlight.clear();
  }

  @visibleForTesting
  static bool temAvaliacaoEmVoo(String lojaId) =>
      _inFlight.containsKey(lojaId.trim());

  /// Compat 040B: não é autoridade do alerta. Preferir [avaliarComValidacaoRemota].
  static Future<bool> garantirPullSessao(String lojaId) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return false;
    final pull =
        await ContaReceberFirestoreService.pullContasReceberRemotas(loja);
    if (pull.erros > 0 && pull.importados == 0 && pull.atualizados == 0) {
      return false;
    }
    return true;
  }

  static ContaReceberLembreteResultado avaliar({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    DateTime? agora,
  }) {
    final agoraBase = agora ?? DateTime.now();
    final hojeBase = DateTime(agoraBase.year, agoraBase.month, agoraBase.day);
    final pendentes = ContaReceberService.listar(
      contas: contas,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    final vencidas = pendentes.where((c) {
      final d = DateTime(
        c.dataVencimento.year,
        c.dataVencimento.month,
        c.dataVencimento.day,
      );
      return d.isBefore(hojeBase);
    }).toList();
    final vencendo = pendentes.where((c) {
      final d = DateTime(
        c.dataVencimento.year,
        c.dataVencimento.month,
        c.dataVencimento.day,
      );
      final dias = d.difference(hojeBase).inDays;
      return dias >= 0 && dias <= 2;
    }).toList();
    return ContaReceberLembreteResultado(
      vencidas: vencidas,
      vencendo: vencendo,
    );
  }

  /// Candidatos Hive → confirma no servidor. Hive nunca é autoridade final.
  static Future<ContaReceberLembreteResultado> avaliarComValidacaoRemota({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    DateTime? agora,
  }) {
    final loja = lojaId.trim();
    if (loja.isEmpty) {
      return Future.value(ContaReceberLembreteResultado.vazio);
    }
    final existente = _inFlight[loja];
    if (existente != null) return existente;

    late final Future<ContaReceberLembreteResultado> tracked;
    tracked = _avaliarComValidacaoRemotaImpl(
      contas: contas,
      lojaId: loja,
      agora: agora,
    ).whenComplete(() {
      if (identical(_inFlight[loja], tracked)) {
        _inFlight.remove(loja);
      }
    });
    _inFlight[loja] = tracked;
    return tracked;
  }

  static Future<ContaReceberLembreteResultado> _avaliarComValidacaoRemotaImpl({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    DateTime? agora,
  }) async {
    final candidatos = avaliar(contas: contas, lojaId: lojaId, agora: agora);
    if (!candidatos.deveAlertar) {
      return ContaReceberLembreteResultado.vazio;
    }

    try {
      final atraso = debugAtrasoValidacaoRemota;
      if (atraso != null && atraso > Duration.zero) {
        await Future<void>.delayed(atraso);
      }
      final hook = debugForcarFalhaValidacaoRemota;
      if (hook != null) {
        await hook();
      }

      final contasAlvo = <ContaReceber>[];
      final docIds = <String>[];
      for (final c in [...candidatos.vencidas, ...candidatos.vencendo]) {
        final docId = resolveContaReceberDocId(c);
        if (docId.isEmpty) continue;
        contasAlvo.add(c);
        docIds.add(docId);
      }

      // O(N) gets em paralelo — não trunca candidatos (correctness > custo).
      final remotos = await Future.wait(
        docIds.map(
          (id) => ContaReceberFirestoreService.buscarContaReceberRemotaServidor(
            lojaId: lojaId,
            contaReceberId: id,
          ),
        ),
      );

      final confirmadas = <ContaReceber>[];
      for (var i = 0; i < contasAlvo.length; i++) {
        final remoto = remotos[i];
        if (remoto == null) continue;
        if (ContaReceberFirestoreService.isDocRemotoEncerrado(remoto)) {
          continue;
        }
        confirmadas.add(contasAlvo[i]);
      }

      return avaliar(contas: confirmadas, lojaId: lojaId, agora: agora);
    } catch (e) {
      debugPrint(
        '[CR-LEMBRETE] validação remota falhou type=${e.runtimeType} — alerta suprimido',
      );
      return ContaReceberLembreteResultado.vazio;
    }
  }
}
