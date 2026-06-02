// Mensagens sanitizadas de falha de sync de produto (UI / fila / logs).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'produtos_firestore_service.dart';

/// Converte exceções/status de sync em texto curto, sem dados sensíveis.
class ProdutoSyncErroUtil {
  ProdutoSyncErroUtil._();

  /// Último erro sanitizado do ciclo de [ProdutosFirestoreService.syncProdutoComStatus].
  static String? sanitizar(Object? error, {ProdutoSyncRemotoStatus? status}) {
    if (error is FirebaseException) {
      return _firebaseCodeLabel(error.code);
    }
    if (error is FirebaseAuthException) {
      return _firebaseCodeLabel(error.code);
    }
    if (status != null) {
      final fromStatus = _statusLabel(status);
      if (fromStatus != null) return fromStatus;
    }
    final raw = error?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.length > 120) return '${raw.substring(0, 120)}…';
    return raw;
  }

  static String? _statusLabel(ProdutoSyncRemotoStatus status) {
    switch (status) {
      case ProdutoSyncRemotoStatus.lojaInvalida:
        return 'lojaId ausente';
      case ProdutoSyncRemotoStatus.produtoInvalido:
        return 'chave local do produto inválida';
      case ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone:
        return 'identificador-excluido (tombstone)';
      case ProdutoSyncRemotoStatus.falhaRemota:
        return 'falha-remota-sem-enfileirar';
      case ProdutoSyncRemotoStatus.pendenteFila:
        return 'pendente-na-fila';
      case ProdutoSyncRemotoStatus.confirmado:
      case ProdutoSyncRemotoStatus.semMudancas:
        return null;
    }
  }

  static String _firebaseCodeLabel(String code) {
    switch (code) {
      case 'permission-denied':
        return 'permission-denied (sem permissão na loja)';
      case 'unauthenticated':
        return 'unauthenticated (sessão expirada)';
      case 'failed-precondition':
        return 'failed-precondition';
      case 'invalid-argument':
        return 'invalid-argument (dados inválidos)';
      case 'unavailable':
        return 'unavailable (serviço indisponível)';
      case 'deadline-exceeded':
        return 'deadline-exceeded (tempo esgotado)';
      case 'resource-exhausted':
        return 'resource-exhausted';
      case 'app-check-token-invalid':
      case 'app-check-failed':
        return 'app-check (verificação do app)';
      default:
        return code.isEmpty ? 'erro-firestore' : code;
    }
  }

  static String mensagemCadastroPendenteFila({String? detalheErro}) {
    final base =
        'Produto salvo no aparelho e colocado na fila de sincronização. '
        'Quando a conexão estabilizar, ele será enviado para a nuvem automaticamente.';
    final d = detalheErro?.trim();
    if (d == null || d.isEmpty) return base;
    return '$base\n\nFalha ao sincronizar produto: $d';
  }

  static String mensagemCadastroFalhaRemota({String? detalheErro}) {
    final base =
        'Produto salvo no aparelho, mas a sincronização com a nuvem falhou agora. '
        'Tente novamente em instantes.';
    final d = detalheErro?.trim();
    if (d == null || d.isEmpty) return base;
    return '$base\n\nFalha ao sincronizar produto: $d';
  }
}
