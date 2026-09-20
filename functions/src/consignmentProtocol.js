/** Consignment protocol constants, errors, money, and payload parsing. Isolated from PDV. */
import {createHash} from 'node:crypto';
import {documentId} from './stockCatalogAccess.js';
import {isMap} from './catalogStockProjection.js';

export const CONSIGNMENT_PROTOCOL_VERSION = 1;
export const CONSIGNMENT_SCHEMA_VERSION = 1;
export const MAX_LINES = 50;

export const STATUS = Object.freeze({
  DRAFT: 'DRAFT',
  ISSUED: 'ISSUED',
  SETTLED: 'SETTLED',
  CANCELLED: 'CANCELLED',
});

export const COMMISSION = Object.freeze({
  SEM_COMISSAO: 'SEM_COMISSAO',
  PERCENTUAL: 'PERCENTUAL',
  VALOR_FIXO_POR_UNIDADE: 'VALOR_FIXO_POR_UNIDADE',
});

export const CODES = Object.freeze({
  INSUFFICIENT_STOCK: 'INSUFFICIENT_STOCK',
  PRODUCT_NOT_FOUND: 'PRODUCT_NOT_FOUND',
  VARIATION_NOT_FOUND: 'VARIATION_NOT_FOUND',
  PRODUCT_STATE_UNSAFE: 'PRODUCT_STATE_UNSAFE',
  CONSIGNMENT_GRADE_NOT_SUPPORTED: 'CONSIGNMENT_GRADE_NOT_SUPPORTED',
  CONSIGNMENT_ALREADY_ISSUED: 'CONSIGNMENT_ALREADY_ISSUED',
  CONSIGNMENT_ALREADY_SETTLED: 'CONSIGNMENT_ALREADY_SETTLED',
  INVALID_SETTLEMENT_TOTAL: 'INVALID_SETTLEMENT_TOTAL',
  IDEMPOTENCY_CONFLICT: 'IDEMPOTENCY_CONFLICT',
  AUTH: 'AUTH',
  MODULE_DISABLED: 'MODULE_DISABLED',
  INVALID_ARGUMENT: 'INVALID_ARGUMENT',
  FAILED_PRECONDITION: 'FAILED_PRECONDITION',
  NOT_FOUND: 'NOT_FOUND',
  RESOURCE_EXHAUSTED: 'RESOURCE_EXHAUSTED',
  SERVER: 'SERVER',
});

const HTTP_BY_CODE = Object.freeze({
  [CODES.INSUFFICIENT_STOCK]: 'failed-precondition',
  [CODES.PRODUCT_NOT_FOUND]: 'not-found',
  [CODES.VARIATION_NOT_FOUND]: 'failed-precondition',
  [CODES.PRODUCT_STATE_UNSAFE]: 'failed-precondition',
  [CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED]: 'failed-precondition',
  [CODES.CONSIGNMENT_ALREADY_ISSUED]: 'failed-precondition',
  [CODES.CONSIGNMENT_ALREADY_SETTLED]: 'failed-precondition',
  [CODES.INVALID_SETTLEMENT_TOTAL]: 'failed-precondition',
  [CODES.IDEMPOTENCY_CONFLICT]: 'already-exists',
  [CODES.AUTH]: 'permission-denied',
  [CODES.MODULE_DISABLED]: 'failed-precondition',
  [CODES.INVALID_ARGUMENT]: 'invalid-argument',
  [CODES.FAILED_PRECONDITION]: 'failed-precondition',
  [CODES.NOT_FOUND]: 'not-found',
  [CODES.RESOURCE_EXHAUSTED]: 'resource-exhausted',
  [CODES.SERVER]: 'internal',
  unauthenticated: 'unauthenticated',
  'permission-denied': 'permission-denied',
});

export function consignmentError(code, message) {
  const error = new Error(message || code);
  error.consignmentCode = code;
  error.code = HTTP_BY_CODE[code] || 'failed-precondition';
  return error;
}

export function mapConsignmentHttp(error) {
  if (error?.consignmentCode) {
    return {
      http: HTTP_BY_CODE[error.consignmentCode] || error.code || 'internal',
      message: error.consignmentCode,
      details: {consignmentCode: error.consignmentCode, detail: error.message},
    };
  }
  const allowed = new Set(['unauthenticated','permission-denied','invalid-argument',
    'failed-precondition','aborted','already-exists','resource-exhausted','not-found']);
  if (allowed.has(error?.code)) {
    return {http: error.code, message: error.message, details: {consignmentCode: error.code}};
  }
  return {http: 'internal', message: 'SERVER', details: {consignmentCode: CODES.SERVER}};
}

const ordered = value => Array.isArray(value) ? value.map(ordered) : isMap(value)
  ? Object.fromEntries(Object.keys(value).sort().map(k => [k, ordered(value[k])])) : value;
export const requestFingerprint = value =>
  createHash('sha256').update(JSON.stringify(ordered(value))).digest('hex');

export function keysOnly(data, allowed) {
  if (!isMap(data) || Object.keys(data).some(k => !allowed.includes(k))) {
    throw consignmentError(CODES.INVALID_ARGUMENT, 'Unknown or protected command field');
  }
}

export function money(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw consignmentError(CODES.INVALID_ARGUMENT, 'Invalid money amount');
  }
  return Math.round(value * 100) / 100;
}

export function moneyCents(value) {
  return Math.round(money(value) * 100);
}

export function fromCents(cents) {
  if (!Number.isSafeInteger(cents) || cents < 0) throw consignmentError(CODES.INVALID_ARGUMENT, 'Invalid cents');
  return cents / 100;
}

export function lineAmounts(qty, unitPrice, commissionType, commissionValue) {
  const n = quantityNonNegative(qty);
  const price = money(unitPrice);
  const grossCents = n * moneyCents(price);
  let commissionCents = 0;
  if (commissionType === COMMISSION.PERCENTUAL) {
    const pct = money(commissionValue);
    if (pct > 100) throw consignmentError(CODES.INVALID_ARGUMENT, 'Commission percent cannot exceed 100');
    commissionCents = Math.round(grossCents * pct / 100);
  } else if (commissionType === COMMISSION.VALOR_FIXO_POR_UNIDADE) {
    commissionCents = n * moneyCents(commissionValue);
  } else if (commissionType !== COMMISSION.SEM_COMISSAO) {
    throw consignmentError(CODES.INVALID_ARGUMENT, 'Unsupported commission type');
  }
  if (commissionCents > grossCents) commissionCents = grossCents;
  return {
    lineGrossAmount: fromCents(grossCents),
    lineCommissionAmount: fromCents(commissionCents),
    lineNetAmount: fromCents(grossCents - commissionCents),
  };
}

export function quantityPositive(value) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw consignmentError(CODES.INVALID_ARGUMENT, 'Quantity must be a positive integer');
  }
  return value;
}

export function quantityNonNegative(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw consignmentError(CODES.INVALID_ARGUMENT, 'Quantity must be a non-negative integer');
  }
  return value;
}

export function optionalString(value, label, max = 2000) {
  if (value == null) return '';
  if (typeof value !== 'string') throw consignmentError(CODES.INVALID_ARGUMENT, `Invalid ${label}`);
  if (value.length > max) throw consignmentError(CODES.INVALID_ARGUMENT, `${label} too long`);
  return value;
}

export const OPERATIONS = Object.freeze([
  'createDraft', 'updateDraft', 'issue', 'settle', 'cancelDraft', 'createReseller', 'updateReseller',
]);

export function parseCommand(raw) {
  keysOnly(raw, ['protocolVersion','lojaId','operation','operationId','consignmentId','payload']);
  if (raw.protocolVersion !== CONSIGNMENT_PROTOCOL_VERSION) {
    throw consignmentError(CODES.FAILED_PRECONDITION, 'Unsupported consignment protocol');
  }
  documentId(raw.lojaId, 'lojaId');
  documentId(raw.operationId, 'operationId');
  if (!OPERATIONS.includes(raw.operation)) throw consignmentError(CODES.INVALID_ARGUMENT, 'Unsupported consignment operation');
  const payload = raw.payload == null ? {} : raw.payload;
  if (!isMap(payload)) throw consignmentError(CODES.INVALID_ARGUMENT, 'Invalid payload');
  const consignmentId = raw.consignmentId != null ? documentId(raw.consignmentId, 'consignmentId') : null;
  if (Buffer.byteLength(JSON.stringify(raw)) > 100000) throw consignmentError(CODES.RESOURCE_EXHAUSTED, 'Command too large');
  return {...raw, payload, consignmentId};
}
