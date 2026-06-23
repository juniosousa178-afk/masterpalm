// Mensagens amigáveis — Tela Mestre de planos (sem códigos técnicos).

String masterPlanAdminErrorMessage(Object? error) {
  final raw = error?.toString() ?? '';
  final lower = raw.toLowerCase();

  if (lower.contains('permission-denied') ||
      lower.contains('acesso restrito')) {
    return 'Acesso restrito à administração Mestre.';
  }
  if (lower.contains('unauthenticated') || lower.contains('faça login')) {
    return 'Faça login para continuar.';
  }
  if (lower.contains('unavailable') ||
      lower.contains('network') ||
      lower.contains('connection')) {
    return 'Não foi possível conectar ao servidor. Verifique sua internet e tente novamente.';
  }
  if (lower.contains('invalid-argument') ||
      lower.contains('obrigatório') ||
      lower.contains('inválido')) {
    if (lower.contains('requestid')) {
      return 'Identificador da solicitação inválido. Tente novamente.';
    }
    if (lower.contains('motivo')) {
      return 'Informe um motivo válido para esta ação.';
    }
    if (lower.contains('data')) {
      return 'Informe uma data final válida para a cortesia temporária.';
    }
    if (lower.contains('plano')) {
      return 'Selecione um plano válido para a cortesia.';
    }
    return 'Verifique os dados informados e tente novamente.';
  }
  if (lower.contains('not-found')) {
    return 'Usuário não encontrado.';
  }
  if (lower.contains('failed-precondition')) {
    if (lower.contains('mais de um cadastro') || lower.contains('consulte pelo uid')) {
      return 'Há mais de um cadastro com este e-mail. Consulte pelo UID.';
    }
    if (lower.contains('cortesia')) {
      return 'A cortesia não está disponível para esta ação no momento.';
    }
    return 'Esta ação não pode ser concluída no estado atual do usuário.';
  }

  return 'Não foi possível concluir a operação. Tente novamente em instantes.';
}

/// Mensagens da tela de detalhe do usuário (Mestre).
String masterPlanUserDetailErrorMessage(Object? error) {
  final raw = error?.toString() ?? '';
  final lower = raw.toLowerCase();

  if (lower.contains('permission-denied') ||
      lower.contains('acesso restrito')) {
    return 'Acesso restrito à administração Mestre.';
  }
  if (lower.contains('not-found')) {
    return 'Não encontramos este usuário. Atualize a lista e tente novamente.';
  }
  if (lower.contains('failed-precondition') &&
      (lower.contains('mais de um cadastro') || lower.contains('consulte pelo uid'))) {
    return 'Há mais de um cadastro com este e-mail. Consulte pelo UID.';
  }
  if (lower.contains('invalid-argument')) {
    return 'Não foi possível identificar o usuário selecionado. Atualize a lista e tente novamente.';
  }

  return 'Não foi possível carregar os detalhes deste usuário. Tente novamente em instantes.';
}

String masterPlanAccessSourceLabel(String? source) {
  switch (source) {
    case 'paid_subscription':
      return 'Assinatura paga';
    case 'manual_courtesy':
      return 'Cortesia manual';
    case 'manual_grant_legacy':
      return 'Liberação legada';
    case 'manual_override_legacy':
      return 'Override legado';
    case 'trial':
      return 'Trial';
    case 'free_limited':
      return 'Gratuito limitado';
    case 'root_lifetime':
      return 'Root vitalício';
    case 'blocked':
      return 'Bloqueado';
    case 'expired':
      return 'Expirado';
    default:
      return source ?? '—';
  }
}

String masterPlanIdLabel(String? planId) {
  switch (planId) {
    case 'basic_monthly':
      return 'Básico';
    case 'intermediate_monthly':
      return 'Intermediário';
    case 'pro_monthly':
      return 'Pro mensal';
    case 'pro_yearly':
      return 'Pro anual';
    case 'free_limited':
      return 'Gratuito limitado';
    case 'free_trial_30d':
      return 'Trial 30 dias';
    case 'free_trial_90d':
      return 'Trial 90 dias';
    case 'lifetime':
      return 'Vitalício';
    default:
      return planId ?? '—';
  }
}
