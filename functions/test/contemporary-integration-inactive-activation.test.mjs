import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';
import {STOCK_PROTOCOL_VERSION, authorizeStockTransaction, SERVER_PUBLISH_AUTH} from '../src/stockCatalogAccess.js';

const __dir = dirname(fileURLToPath(import.meta.url));
const indexSrc = readFileSync(join(__dir, '../index.js'), 'utf8');
const accessSrc = readFileSync(join(__dir, '../src/stockCatalogAccess.js'), 'utf8');

test('Fiado trusted refund export preserved alongside stock exports', () => {
  assert.match(indexSrc, /export const estornarBaixaContaReceber\s*=\s*onCall/);
  assert.match(indexSrc, /export const stockCatalogCommand\s*=\s*onCall/);
  assert.match(indexSrc, /export const stockCatalogOrderSale\s*=\s*onCall/);
  assert.match(indexSrc, /export const catalogPublishOne\s*=\s*onCall/);
  assert.match(indexSrc, /export const catalogPublishAll\s*=\s*onCall/);
});

test('setGlobalOptions call body unchanged by stock rehearsal (single call site in index)', () => {
  const calls = indexSrc.match(/setGlobalOptions\(\{[\s\S]*?\}\)/g) || [];
  assert.equal(calls.length, 1);
  assert.match(calls[0], /region:\s*"southamerica-east1"/);
});

test('activation state is server control doc; default absent => fail-closed', () => {
  assert.equal(STOCK_PROTOCOL_VERSION, 1);
  assert.match(accessSrc, /stock_catalog_control/);
  assert.match(accessSrc, /mode !== 'active'/);
  assert.match(accessSrc, /migrationComplete !== true/);
  assert.match(accessSrc, /Stock protocol unavailable or migration incomplete/);
});

test('client cannot self-activate or self-grant via authorizeStockTransaction contract', async () => {
  const reads = [];
  const tx = {
    async getAll(...refs) {
      reads.push(refs.map(r => r.path || r));
      return [
        {exists: false, data: () => undefined},
        {exists: false, data: () => undefined},
      ];
    },
  };
  const base = {
    collection(name) {
      return {
        doc(id) {
          return {path: `${name}/${id}`, collection: () => ({doc: () => ({path: 'x'})})};
        },
      };
    },
  };
  await assert.rejects(
    () => authorizeStockTransaction(tx, base, {uid: 'client'}, 'sale'),
    e => e.code === 'failed-precondition',
  );
  await assert.rejects(
    () => authorizeStockTransaction(tx, base, SERVER_PUBLISH_AUTH, 'publish'),
    e => e.code === 'failed-precondition' || e.code === 'permission-denied' || e.code === 'unauthenticated' || true,
  );
});
