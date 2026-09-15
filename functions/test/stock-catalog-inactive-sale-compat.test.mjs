import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {classifyStockControlState, INACTIVE_COMPAT_ALLOWED_KINDS} from '../src/stockCatalogAccess.js';
import {inferStockKind, resolveLegacyCompatStockKind} from '../src/catalogStockProjection.js';

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8187') {
  throw new Error('Local emulator required; refusing any other endpoint');
}
const db = new Firestore({projectId: 'demo-stock-catalog'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const owner = {uid: 'owner'};

/** @param {{omitStockKind?: boolean}} opts — when true, fixture MUST NOT seed stockKind (P0 regression). */
async function seedLegacy({
  control = null, product = {}, withOwner = true, withDraft = false, withDep = false, omitStockKind = false,
} = {}) {
  const lojaId = `inactive_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, withOwner ? {ownerUid: 'owner', name: 'Fixture'} : {name: 'Fixture'});
  const stock = {quantidade: 5, stockRevision: 1, ...product};
  if (!omitStockKind && !('stockKind' in product)) stock.stockKind = 'simple';
  if (omitStockKind) delete stock.stockKind;
  batch.set(base.collection('estoque_produtos').doc('p'), stock);
  if (withDraft) batch.set(base.collection('draft_produtos').doc('p'), {nome: 'Peça', publicadoNoCatalogo: true});
  if (withDep) batch.set(base.collection('stock_catalog_dependencies').doc('p'), {comboIds: []});
  if (control) batch.set(base.collection('stock_catalog_control').doc('state'), control);
  await batch.commit();
  if (omitStockKind) {
    assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().stockKind, undefined);
  }
  return {base, lojaId};
}

function intent(lojaId, kind, operationId, item = {}, extra = {}) {
  return {protocolVersion: 1, lojaId, kind, operationId, items: [{productId: 'p', quantity: 1, ...item}], ...extra};
}
async function denied(promise, code, messageIncludes) {
  await assert.rejects(promise, e => {
    if (e.code !== code) return false;
    if (messageIncludes && !String(e.message).includes(messageIncludes)) return false;
    return true;
  });
}

const linaGradeMissingKind = {
  quantidade: 12,
  stockRevision: 2,
  estoquePorTamanho: {34: 2, 35: 2, 36: 2, 37: 2, 38: 2, 39: 2},
  variacoes: {
    34: {amendoa: 2}, 35: {amendoa: 2}, 36: {amendoa: 2},
    37: {amendoa: 2}, 38: {amendoa: 2}, 39: {amendoa: 2},
  },
  tamanhos: ['34', '35', '36', '37', '38', '39'],
};

test('classify: no control / inactive / active / invalid', () => {
  assert.equal(classifyStockControlState({exists: false}), 'NO_CONTROL');
  assert.equal(classifyStockControlState({exists: true, data: () => ({mode: 'inactive', protocolVersion: 1})}), 'INACTIVE');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({mode: 'active', protocolVersion: 1, migrationComplete: true}),
  }), 'ACTIVE');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({mode: 'active', protocolVersion: 1, migrationComplete: false}),
  }), 'INVALID');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({mode: 'maintenance', protocolVersion: 1, migrationComplete: true}),
  }), 'INVALID');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({protocolVersion: 2, mode: 'active', migrationComplete: true}),
  }), 'INVALID');
  assert.deepEqual([...INACTIVE_COMPAT_ALLOWED_KINDS], ['sale', 'restore']);
});

test('resolveLegacyCompatStockKind: absent / valid / invalid', () => {
  assert.deepEqual(resolveLegacyCompatStockKind({quantidade: 3}), {stockKind: 'simple', stockKindSource: 'inferred'});
  assert.deepEqual(resolveLegacyCompatStockKind({stockKind: 'variation', variacoes: {P: {A: 1}}}), {
    stockKind: 'variation', stockKindSource: 'explicit',
  });
  assert.throws(() => resolveLegacyCompatStockKind({stockKind: 'grade', quantidade: 1}), e =>
    e.code === 'failed-precondition' && e.message === 'Invalid stockKind');
  assert.equal(inferStockKind(linaGradeMissingKind), 'variation');
});

test('no-control store authenticated owner simple sale succeeds without draft/dep', async () => {
  const {base, lojaId} = await seedLegacy();
  const result = await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal(result.alreadyApplied, false);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 4);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_access').doc('owner').get()).exists, false);
  assert.equal((await base.collection('draft_produtos').doc('p').get()).exists, false);
});

test('CASE1 no-control SIMPLE missing stockKind sale SUCCESS (no migration error)', async () => {
  const {base, lojaId} = await seedLegacy({omitStockKind: true, product: {quantidade: 5}});
  const result = await executeStockCommand(db, intent(lojaId, 'sale', 'mk1'), owner);
  assert.equal(result.alreadyApplied, false);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.quantidade, 4);
  assert.equal(stock.stockKind, undefined);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_access').doc('owner').get()).exists, false);
});

test('CASE2 inactive SIMPLE missing stockKind sale SUCCESS', async () => {
  const {base, lojaId} = await seedLegacy({
    omitStockKind: true,
    product: {quantidade: 5},
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 'mk2'), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.quantidade, 4);
  assert.equal(stock.stockKind, undefined);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).data().mode, 'inactive');
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).data().migrationComplete, false);
});

test('CASE3 no-control GRADE missing stockKind sizes 34-39 selected 37', async () => {
  const {base, lojaId} = await seedLegacy({omitStockKind: true, product: linaGradeMissingKind});
  await executeStockCommand(db, intent(lojaId, 'sale', 'g37mk', {size: '37', color: 'amendoa'}), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.stockKind, undefined);
  assert.equal(stock.variacoes['37'].amendoa, 1);
  assert.equal(stock.variacoes['34'].amendoa, 2);
  assert.equal(stock.variacoes['35'].amendoa, 2);
  assert.equal(stock.variacoes['36'].amendoa, 2);
  assert.equal(stock.variacoes['38'].amendoa, 2);
  assert.equal(stock.variacoes['39'].amendoa, 2);
  assert.equal(stock.estoquePorTamanho['37'], 1);
});

test('CASE4 inactive GRADE missing stockKind SUCCESS', async () => {
  const {base, lojaId} = await seedLegacy({
    omitStockKind: true,
    product: linaGradeMissingKind,
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 'g37in', {size: '37', color: 'amendoa'}), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.variacoes['37'].amendoa, 1);
  assert.equal(stock.stockKind, undefined);
});

test('CASE5 explicit valid stockKind preserved (inference does not override)', async () => {
  const {base, lojaId} = await seedLegacy({
    product: {stockKind: 'simple', quantidade: 4},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 'exp1'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().stockKind, 'simple');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 3);
});

test('CASE6 invalid explicit stockKind FAIL CLOSED (no silent infer)', async () => {
  const {lojaId} = await seedLegacy({
    product: {stockKind: 'legacy-grade', quantidade: 5},
  });
  await denied(
    executeStockCommand(db, intent(lojaId, 'sale', 'badkind'), owner),
    'failed-precondition',
    'Invalid stockKind',
  );
});

test('CASE7 ambiguous/conflict shape FAIL CLOSED (explicit simple + grade data)', async () => {
  const {lojaId} = await seedLegacy({
    product: {
      stockKind: 'simple',
      quantidade: 5,
      variacoes: {37: {amendoa: 2}},
      estoquePorTamanho: {37: 2},
      tamanhos: ['37'],
    },
  });
  await denied(
    executeStockCommand(db, intent(lojaId, 'sale', 'ambig'), owner),
    'failed-precondition',
    'Simple product has variation data',
  );
});

test('CASE8 insufficient stock missing kind → stock error NOT migration-required', async () => {
  const {base, lojaId} = await seedLegacy({omitStockKind: true, product: {quantidade: 0}});
  let caught;
  try {
    await executeStockCommand(db, intent(lojaId, 'sale', 'insuf'), owner);
  } catch (e) {
    caught = e;
  }
  assert.ok(caught);
  assert.equal(caught.code, 'failed-precondition');
  assert.notEqual(caught.message, 'Stock migration required');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
  assert.equal((await base.collection('stock_catalog_operations').doc('insuf').get()).exists, false);
});

test('CASE9 duplicate retry missing kind exactly-once', async () => {
  const {base, lojaId} = await seedLegacy({omitStockKind: true, product: {quantidade: 3}});
  const cmd = intent(lojaId, 'sale', 'once-mk');
  const a = await executeStockCommand(db, cmd, owner);
  const b = await executeStockCommand(db, cmd, owner);
  assert.equal(a.alreadyApplied, false);
  assert.equal(b.alreadyApplied, true);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 2);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().stockKind, undefined);
});

test('CASE10 restore missing stockKind SUCCESS', async () => {
  const {base, lojaId} = await seedLegacy({omitStockKind: true, product: {quantidade: 5}});
  await executeStockCommand(db, intent(lojaId, 'sale', 'sale-mk'), owner);
  await executeStockCommand(db, intent(lojaId, 'restore', 'rest-mk', {}, {sourceOperationId: 'sale-mk'}), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.quantidade, 5);
  assert.equal(stock.stockKind, undefined);
});

test('empty tamanhos evidence prevents false SIMPLE (variation path)', async () => {
  const partial = {
    quantidade: 0,
    variacoes: {},
    estoquePorTamanho: {},
    tamanhos: ['34', '35', '36'],
  };
  assert.equal(inferStockKind(partial), 'variation');
  const {lojaId} = await seedLegacy({omitStockKind: true, product: partial});
  // Selecting a size must not take the simple-product branch.
  await denied(
    executeStockCommand(db, intent(lojaId, 'sale', 'partial', {size: '34', color: 'x'}), owner),
    'failed-precondition',
  );
});

test('inactive control store sale succeeds', async () => {
  const {base, lojaId} = await seedLegacy({
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 4);
});

test('migrated-inactive (migrationComplete true, mode inactive) sale succeeds', async () => {
  const {base, lojaId} = await seedLegacy({
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: true},
    withDraft: true,
    withDep: true,
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 4);
});

test('CASE12/13 other-store caller denied; unauthenticated denied', async () => {
  const {lojaId} = await seedLegacy({omitStockKind: true});
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), null), 'unauthenticated');
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), {uid: 'intruder'}), 'permission-denied');
});

test('invalid command on inactive denied; restock not allowed on compat bridge', async () => {
  const {base, lojaId} = await seedLegacy();
  await denied(executeStockCommand(db, intent(lojaId, 'restock', 'r1'), owner), 'failed-precondition');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 5);
});

test('duplicate retry does not double decrement', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 3}});
  const cmd = intent(lojaId, 'sale', 'once');
  const a = await executeStockCommand(db, cmd, owner);
  const b = await executeStockCommand(db, cmd, owner);
  assert.equal(a.alreadyApplied, false);
  assert.equal(b.alreadyApplied, true);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 2);
});

test('insufficient stock fails safely without mutation marker', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 0}});
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner), 'failed-precondition');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
  assert.equal((await base.collection('stock_catalog_operations').doc('s1').get()).exists, false);
});

test('grade sizes 34-39: sale size 37 decrements only 37', async () => {
  const grade = {
    stockKind: 'variation',
    quantidade: 12,
    stockRevision: 2,
    estoquePorTamanho: {34: 2, 35: 2, 36: 2, 37: 2, 38: 2, 39: 2},
    variacoes: {
      34: {amendoa: 2}, 35: {amendoa: 2}, 36: {amendoa: 2},
      37: {amendoa: 2}, 38: {amendoa: 2}, 39: {amendoa: 2},
    },
    tamanhos: ['34', '35', '36', '37', '38', '39'],
  };
  const {base, lojaId} = await seedLegacy({product: grade});
  await executeStockCommand(db, intent(lojaId, 'sale', 'g37', {size: '37', color: 'amendoa'}), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.variacoes['37'].amendoa, 1);
  assert.equal(stock.variacoes['34'].amendoa, 2);
  assert.equal(stock.variacoes['35'].amendoa, 2);
  assert.equal(stock.variacoes['36'].amendoa, 2);
  assert.equal(stock.variacoes['38'].amendoa, 2);
  assert.equal(stock.variacoes['39'].amendoa, 2);
  assert.equal(stock.estoquePorTamanho['37'], 1);
});

test('missing selected size fails structured', async () => {
  const {lojaId} = await seedLegacy({
    product: {
      stockKind: 'variation',
      quantidade: 2,
      estoquePorTamanho: {37: 2},
      variacoes: {37: {amendoa: 2}},
    },
  });
  await denied(
    executeStockCommand(db, intent(lojaId, 'sale', 'bad', {size: '99', color: 'amendoa'}), owner),
    'failed-precondition',
  );
});

test('corrupt/incomplete control fails closed', async () => {
  for (const control of [
    {protocolVersion: 2, mode: 'active', migrationComplete: true},
    {protocolVersion: 1, mode: 'active', migrationComplete: false},
    {protocolVersion: 1, mode: 'maintenance', migrationComplete: true},
  ]) {
    const {base, lojaId} = await seedLegacy({control});
    await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner), 'failed-precondition');
    assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 5);
  }
});

test('CASE11 ACTIVE migrated product protocol unchanged (grant required)', async () => {
  const lojaId = `active_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  await base.set({ownerUid: 'owner'});
  await base.collection('estoque_produtos').doc('p').set({quantidade: 2, stockKind: 'simple', stockRevision: 0});
  await base.collection('draft_produtos').doc('p').set({nome: 'A', publicadoNoCatalogo: true});
  await base.collection('stock_catalog_dependencies').doc('p').set({comboIds: []});
  await base.collection('stock_catalog_control').doc('state').set({
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  // owner membership alone is not enough on ACTIVE — grant required
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner), 'permission-denied');
  await base.collection('stock_catalog_access').doc('owner').set({
    enabled: true, permissions: {sale: true},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().stockKind, 'simple');
});

test('LEGACY_COMBO_INACTIVE_PATH: combo with missing stockKind reachable and sale expands', async () => {
  const lojaId = `combo_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, {ownerUid: 'owner', name: 'Fixture'});
  batch.set(base.collection('estoque_produtos').doc('combo'), {
    quantidade: 2, stockRevision: 0, tipoProduto: 'combo',
    itensCombo: [{productId: 'child', quantity: 1}],
  });
  batch.set(base.collection('estoque_produtos').doc('child'), {
    quantidade: 5, stockRevision: 0,
  });
  await batch.commit();
  assert.equal((await base.collection('estoque_produtos').doc('combo').get()).data().stockKind, undefined);
  assert.equal((await base.collection('estoque_produtos').doc('child').get()).data().stockKind, undefined);
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'combo-sale',
    items: [{productId: 'combo', quantity: 1}],
  }, owner);
  assert.equal((await base.collection('estoque_produtos').doc('child').get()).data().quantidade, 4);
  assert.equal((await base.collection('estoque_produtos').doc('combo').get()).data().stockKind, undefined);
  assert.equal((await base.collection('estoque_produtos').doc('child').get()).data().stockKind, undefined);
});
