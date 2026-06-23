// Mensagens de cancelamento/reativação de renovação (testáveis, sem I/O).
library;

/// Erros funcionais conhecidos do backend — nunca exibir ao cliente como código cru.
const _internalPlanRenewalCodes = {
  'recurring_plan_billing_disabled',
  'assinatura_recorrente_nao_encontrada',
  'assinatura_ja_cancelada',
};

/// Mensagem amigável para falhas ao cancelar/reativar renovação.
String? planRenewalErrorMessage(Object e) {
  final full = e.toString();
  final s = full.toLowerCase();

  if (s.contains('recurring_plan_billing_disabled')) {
    return 'Não foi possível concluir o cancelamento agora. '
        'Tente atualizar a tela ou entre em contato com o suporte.';
  }
  if (s.contains('assinatura_recorrente_nao_encontrada')) {
    return 'Não encontramos uma renovação ativa para este plano.';
  }
  if (s.contains('assinatura_ja_cancelada')) {
    return 'A renovação já está cancelada. '
        'Seu acesso permanece ativo até a data informada.';
  }
  return null;
}

/// Indica se [errorText] é um código interno que não deve ser propagado cru à UI.
bool isInternalPlanRenewalErrorCode(String errorText) {
  final s = errorText.toLowerCase();
  return _internalPlanRenewalCodes.any(s.contains);
}

String formatPlanRenewalCancelSuccess({
  required String planLabel,
  required DateTime periodEnd,
}) {
  final lim = '${periodEnd.day.toString().padLeft(2, '0')}/'
      '${periodEnd.month.toString().padLeft(2, '0')}/${periodEnd.year}';
  return 'Renovação cancelada com sucesso.\n'
      'Seu plano $planLabel continua ativo até $lim.\n'
      'Após essa data, sua conta seguirá no plano gratuito limitado.';
}
