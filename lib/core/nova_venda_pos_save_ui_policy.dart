/// Política explícita pós-salvamento da Nova Venda — evita retorno silencioso na UI.

enum NovaVendaPosSaveUiAction {
  showSuccess,
  showErrorDialog,
  notifyParentError,
}

class NovaVendaPosSaveUiDecision {
  const NovaVendaPosSaveUiDecision({
    required this.action,
    this.errorMessage,
  });

  final NovaVendaPosSaveUiAction action;
  final String? errorMessage;
}

const novaVendaPosSaveFallbackError =
    'Não foi possível concluir a venda. Tente novamente.';

const kNovaVendaCloudCommittedLocalMirrorMensagem =
    'Venda salva com sucesso. Houve uma falha ao atualizar os dados locais. '
    'Atualize a tela para sincronizar.';

/// True when the backend sale already committed and only the local mirror failed.
bool isNovaVendaCloudCommittedLocalMirrorMessage(String? raw) {
  final m = raw?.trim() ?? '';
  if (m.isEmpty) return false;
  final lower = m.toLowerCase();
  return lower.contains('venda gravada na nuvem') ||
      lower.contains('espelho local falhou') ||
      lower.contains('conta a receber local falhou') ||
      lower.contains('falha ao atualizar os dados locais') ||
      lower.contains('conta a receber ficou pendente de sincronização');
}

/// Comportamento legado (pré-fix H1STUCK): retorno silencioso na UI.
bool legacyNovaVendaPosSaveUiIsSilent({
  required bool ok,
  required String? mensagemErro,
  required bool mounted,
}) {
  if (!mounted) return true;
  if (ok) return false;
  return mensagemErro == null || mensagemErro.isEmpty;
}

String novaVendaPosSaveErrorMessage(String? mensagemErro) {
  final trimmed = mensagemErro?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return novaVendaPosSaveFallbackError;
}

NovaVendaPosSaveUiDecision decideNovaVendaPosSaveUi({
  required bool ok,
  required String? mensagemErro,
  required bool mounted,
}) {
  final cloudCommittedLocalMirror =
      isNovaVendaCloudCommittedLocalMirrorMessage(mensagemErro);
  if (ok || cloudCommittedLocalMirror) {
    if (!mounted) {
      return NovaVendaPosSaveUiDecision(
        action: NovaVendaPosSaveUiAction.notifyParentError,
        errorMessage: cloudCommittedLocalMirror
            ? kNovaVendaCloudCommittedLocalMirrorMensagem
            : 'A venda pode ter sido concluída, mas a tela foi atualizada. '
                'Verifique o histórico de vendas.',
      );
    }
    return const NovaVendaPosSaveUiDecision(
      action: NovaVendaPosSaveUiAction.showSuccess,
    );
  }

  final msg = novaVendaPosSaveErrorMessage(mensagemErro);
  if (!mounted) {
    return NovaVendaPosSaveUiDecision(
      action: NovaVendaPosSaveUiAction.notifyParentError,
      errorMessage: msg,
    );
  }
  return NovaVendaPosSaveUiDecision(
    action: NovaVendaPosSaveUiAction.showErrorDialog,
    errorMessage: msg,
  );
}
