// Erros sanitizados da fundação PDV V1 interna (Fase 7A-A).
// Sem dependência de Firebase, UI ou serviços de produção.

class PdvV1InternalError implements Exception {
  PdvV1InternalError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PdvV1InternalError($code): $message';
}

class PdvV1ScopeNotSupportedError extends PdvV1InternalError {
  PdvV1ScopeNotSupportedError(String detail)
      : super('scope_not_supported', detail);
}

class PdvV1ValidationError extends PdvV1InternalError {
  PdvV1ValidationError(String detail) : super('validation_failed', detail);
}

class PdvV1InvalidTransitionError extends PdvV1InternalError {
  PdvV1InvalidTransitionError(String from, String to, {String? detail})
      : super(
          'invalid_transition',
          detail ?? 'Transição proibida: $from → $to',
        );
}

class PdvV1MalformedJournalError extends PdvV1InternalError {
  PdvV1MalformedJournalError(String detail)
      : super('malformed_journal', detail);
}

class PdvV1ExecutionNotIntegratedError extends PdvV1InternalError {
  PdvV1ExecutionNotIntegratedError([String? detail])
      : super(
          'execution_not_integrated',
          detail ??
              'Integração externa PDV V1 não habilitada nesta fase (7A-A).',
        );
}
