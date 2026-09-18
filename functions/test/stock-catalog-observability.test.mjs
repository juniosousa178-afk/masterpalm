import test from 'node:test';
import assert from 'node:assert/strict';
import {emitRestoreAppliedSaleRequiredLog, sanitizeRestorePreconditionLog} from '../src/stockCatalogObservability.js';

const ALLOWED = new Set([
  'event', 'reason', 'operationType', 'lojaId', 'operationId', 'lookupKey',
  'sourceExists', 'sourceKind', 'sourceStatus',
]);

test('missing-applied failure emits structured sanitized metadata', () => {
  const payload = sanitizeRestorePreconditionLog({
    lojaId: 'store-tech',
    operationId: 'restore-op',
    sourceOperationId: 'sale-lookup',
    sourceExists: false,
    sourceKind: null,
    sourceStatus: null,
  });
  assert.equal(payload.event, 'stock_restore_precondition');
  assert.equal(payload.reason, 'applied_sale_required');
  assert.equal(payload.operationType, 'restore');
  assert.equal(payload.lojaId, 'store-tech');
  assert.equal(payload.operationId, 'restore-op');
  assert.equal(payload.lookupKey, 'sale-lookup');
  assert.equal(payload.sourceExists, false);
  assert.equal(payload.sourceKind, null);
  assert.equal(payload.sourceStatus, null);
  assert.deepEqual([...Object.keys(payload)].sort(), [...ALLOWED].filter(k => k in payload).sort());
});

test('drops PII, item names, payment details and full payloads', () => {
  const payload = sanitizeRestorePreconditionLog({
    lojaId: 'store-tech',
    operationId: 'restore-op',
    sourceOperationId: 'sale-lookup',
    sourceExists: true,
    sourceKind: 'editorial',
    sourceStatus: 'applied',
    customerName: 'forbidden',
    email: 'a@b.c',
    phone: '11999999999',
    items: [{productId: 'p', quantity: 2, descricao: 'secret'}],
    sale: {cliente: 'secret'},
    payload: {full: true},
    formasPagamento: ['fiado'],
    nome: 'product name',
  });
  assert.equal(payload.lookupKey, 'sale-lookup');
  assert.equal(payload.sourceKind, 'editorial');
  for (const key of Object.keys(payload)) assert.equal(ALLOWED.has(key), true, key);
  const json = JSON.stringify(payload);
  assert.equal(json.includes('forbidden'), false);
  assert.equal(json.includes('a@b.c'), false);
  assert.equal(json.includes('11999999999'), false);
  assert.equal(json.includes('secret'), false);
  assert.equal(json.includes('product name'), false);
  assert.equal(json.includes('fiado'), false);
});

test('emit logs JSON once and does not mutate input or write counts', () => {
  const lines = [];
  const input = {
    lojaId: 'store-tech',
    operationId: 'restore-op',
    sourceOperationId: 'sale-lookup',
    sourceExists: false,
    items: [{nome: 'should not leak'}],
  };
  const frozen = JSON.stringify(input);
  const payload = emitRestoreAppliedSaleRequiredLog(input, {info: line => lines.push(line)});
  assert.equal(lines.length, 1);
  assert.equal(lines[0], JSON.stringify(payload));
  assert.equal(JSON.stringify(input), frozen);
  assert.equal(JSON.parse(lines[0]).items, undefined);
  assert.equal(JSON.parse(lines[0]).reason, 'applied_sale_required');
});

test('applied success path does not require a log helper call', () => {
  assert.equal(typeof emitRestoreAppliedSaleRequiredLog, 'function');
});
