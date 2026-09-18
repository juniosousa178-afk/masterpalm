/** Sanitized restore-precondition telemetry. No PII, no payloads, no business-logic change. */

const FORBIDDEN_KEYS = Object.freeze([
  'customerName', 'customerUsername', 'nomeCliente', 'username', 'phone', 'telefone',
  'email', 'items', 'sale', 'payload', 'editorial', 'definition', 'payment',
  'formasPagamento', 'descricao', 'productName', 'nome',
]);

export function sanitizeRestorePreconditionLog(input = {}) {
  const lookupKey = typeof input.lookupKey === 'string' && input.lookupKey
    ? input.lookupKey
    : (typeof input.sourceOperationId === 'string' && input.sourceOperationId ? input.sourceOperationId : undefined);
  const out = {
    event: 'stock_restore_precondition',
    reason: 'applied_sale_required',
    operationType: 'restore',
  };
  if (typeof input.lojaId === 'string' && input.lojaId) out.lojaId = input.lojaId;
  if (typeof input.operationId === 'string' && input.operationId) out.operationId = input.operationId;
  if (lookupKey) out.lookupKey = lookupKey;
  if (typeof input.sourceExists === 'boolean') out.sourceExists = input.sourceExists;
  if (input.sourceKind === null || typeof input.sourceKind === 'string') out.sourceKind = input.sourceKind;
  if (input.sourceStatus === null || typeof input.sourceStatus === 'string') out.sourceStatus = input.sourceStatus;
  for (const key of FORBIDDEN_KEYS) {
    if (key in out) delete out[key];
  }
  return out;
}

export function emitRestoreAppliedSaleRequiredLog(input, logger = console) {
  const payload = sanitizeRestorePreconditionLog(input);
  logger.info(JSON.stringify(payload));
  return payload;
}
