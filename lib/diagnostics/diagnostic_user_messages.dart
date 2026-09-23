import 'diagnostic_enums.dart';

class DiagnosticUserCopy {
  const DiagnosticUserCopy({
    required this.title,
    required this.message,
    required this.safeNextAction,
  });

  final String title;
  final String message;
  final String safeNextAction;
}

/// User-facing copy — never includes stack traces.
abstract final class DiagnosticUserMessages {
  static DiagnosticUserCopy forClassification(String code) {
    switch (code) {
      case DiagnosticClassification.networkOffline:
        return const DiagnosticUserCopy(
          title: 'Sem conexão',
          message: 'Não foi possível contactar o servidor.',
          safeNextAction: 'Verifique a internet e tente novamente.',
        );
      case DiagnosticClassification.firebasePermissionDenied:
        return const DiagnosticUserCopy(
          title: 'Permissão insuficiente',
          message: 'Esta operação não foi autorizada para o seu utilizador.',
          safeNextAction: 'Peça acesso ao administrador da loja.',
        );
      case DiagnosticClassification.firebaseFailedPrecondition:
        return const DiagnosticUserCopy(
          title: 'Operação bloqueada',
          message: 'O servidor recusou a operação no estado atual dos dados.',
          safeNextAction: 'Atualize os dados e tente de novo.',
        );
      case DiagnosticClassification.firebaseUnavailable:
      case DiagnosticClassification.functionTimeout:
        return const DiagnosticUserCopy(
          title: 'Serviço indisponível',
          message: 'O servidor demorou ou não respondeu a tempo.',
          safeNextAction: 'Aguarde alguns segundos e tente novamente.',
        );
      case DiagnosticClassification.stockLocalRemoteMismatch:
        return const DiagnosticUserCopy(
          title: 'Estoque não sincronizado',
          message: 'O estoque deste produto está diferente do servidor.',
          safeNextAction: 'Atualize os dados antes de vender este produto.',
        );
      case DiagnosticClassification.stockPendingOperation:
      case DiagnosticClassification.stockOrphanPending:
      case DiagnosticClassification.stockDuplicatePending:
      case DiagnosticClassification.stockInvalidPending:
        return const DiagnosticUserCopy(
          title: 'Operação de estoque pendente',
          message: 'Há uma alteração de estoque ainda não confirmada.',
          safeNextAction: 'Aguarde a sincronização ou atualize os dados.',
        );
      case DiagnosticClassification.stockAggregateMismatch:
      case DiagnosticClassification.stockCanonicalCellMismatch:
        return const DiagnosticUserCopy(
          title: 'Divergência de estoque por variação',
          message:
              'A quantidade total não coincide com a soma das variações no servidor.',
          safeNextAction:
              'Não invente quantidades. Contacte suporte com o diagnóstico exportado.',
        );
      case DiagnosticClassification.stockRevisionMismatch:
      case DiagnosticClassification.stockOperationIdMismatch:
        return const DiagnosticUserCopy(
          title: 'Conflito de revisão de estoque',
          message: 'Outra alteração já atualizou este produto no servidor.',
          safeNextAction: 'Atualize o produto e reaplique a alteração.',
        );
      case DiagnosticClassification.stockEditorialLineageAnomaly:
        return const DiagnosticUserCopy(
          title: 'Marcador de estoque inconsistente',
          message:
              'O histórico técnico do produto aponta para uma operação não-estoque.',
          safeNextAction: 'Exporte o diagnóstico e envie ao suporte.',
        );
      case DiagnosticClassification.saleMissingStockOperationBinding:
        return const DiagnosticUserCopy(
          title: 'Venda sem vínculo de estoque',
          message:
              'Esta venda não tem o identificador de operação de estoque necessário para exclusão segura.',
          safeNextAction: 'Não force a exclusão. Contacte suporte.',
        );
      case DiagnosticClassification.saleSourceOperationNotFound:
        return const DiagnosticUserCopy(
          title: 'Operação de origem não encontrada',
          message: 'Não foi possível localizar a operação de estoque da venda.',
          safeNextAction: 'Exporte o diagnóstico antes de tentar novamente.',
        );
      case DiagnosticClassification.saleRestoreAlreadyApplied:
        return const DiagnosticUserCopy(
          title: 'Estoque já restaurado',
          message: 'O servidor indica que esta restauração já foi aplicada.',
          safeNextAction: 'Atualize os dados e confirme o estoque.',
        );
      case DiagnosticClassification.saleRestoreFailed:
        return const DiagnosticUserCopy(
          title: 'Falha ao restaurar estoque',
          message: 'Não foi possível devolver o estoque da venda.',
          safeNextAction: 'Não repita a exclusão. Exporte o diagnóstico.',
        );
      case DiagnosticClassification.salePersistAfterStockFailure:
        return const DiagnosticUserCopy(
          title: 'Venda interrompida',
          message: 'O estoque remoto falhou antes de gravar a venda.',
          safeNextAction: 'Verifique o estoque e não reenvie a mesma venda às cegas.',
        );
      case DiagnosticClassification.staleTombstoneLiveRemoteCell:
        return const DiagnosticUserCopy(
          title: 'Marcador antigo de exclusão',
          message:
              'Existe um marcador histórico que poderia ocultar estoque ainda positivo no servidor.',
          safeNextAction:
              'Com o build atual o estoque vivo deve continuar visível. Exporte se notar falta.',
        );
      case DiagnosticClassification.cacheLocalUntrackedMutation:
      case DiagnosticClassification.cacheRemoteNewer:
      case DiagnosticClassification.cacheHydrationFailed:
        return const DiagnosticUserCopy(
          title: 'Cache local desatualizado',
          message: 'Os dados locais podem não refletir o estoque canónico remoto.',
          safeNextAction: 'Faça atualização/sincronização antes de vender.',
        );
      case DiagnosticClassification.buildIdentityMismatch:
        return const DiagnosticUserCopy(
          title: 'Versão do aplicativo',
          message: 'A identidade da build não corresponde ao esperado.',
          safeNextAction: 'Atualize o aplicativo para a versão recomendada.',
        );
      default:
        return const DiagnosticUserCopy(
          title: 'Problema não identificado',
          message: 'Ocorreu um erro que ainda não tem classificação confirmada.',
          safeNextAction: 'Exporte o diagnóstico e contacte o suporte.',
        );
    }
  }
}
