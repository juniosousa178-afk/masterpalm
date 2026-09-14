import test from 'node:test';
import assert from 'node:assert/strict';
import {planStockCatalogMigration} from '../scripts/migrate_stock_catalog_protocol.js';

const stock = {id: 'p', nome: 'Peça', quantidade: 1, variacoes: {}, publicadoNoCatalogo: true};
function fixture() {
  return {lojaId: 'a', control: {mode: 'maintenance'}, attestations: {
    inventoryComplete: true, backupVerified: true, directWritesDenied: true, legacyAdminWritersDrained: true,
  }, stock: {p: structuredClone(stock)}, draft: {}, live: {}, tombstones: {}, legacyOperations: {}, pendingIntents: {}, orders: {}, access: {}};
}
const owner = {lojaId: 'a', evidenceId: 'offline-reviewed-ownership-fixture', grants: {
  owner: {enabled: true, permissions: {sale: true, adjust: true}},
  'stock-catalog-publisher': {enabled: true, permissions: {publish: true}},
  'stock-catalog-payment': {enabled: true, permissions: {sale: true}},
}};
const planned = (plan, suffix) => plan.writes.find(w => w.path === `lojas/a/${suffix}`);
function blocked(snapshot, code, manifest = owner) {
  const plan = planStockCatalogMigration(snapshot, manifest);
  assert.equal(plan.status, 'BLOCKED'); assert.deepEqual(plan.writes, []);
  assert.ok(plan.blockers.some(b => b.code.includes(code)), JSON.stringify(plan.blockers));
}
test('pure offline plan preserves input, is deterministic, and never activates or executes', () => {
  const f = fixture(), before = structuredClone(f);
  const p = planStockCatalogMigration(f, owner);
  assert.deepEqual(f, before); assert.deepEqual(p, planStockCatalogMigration(f, owner));
  assert.equal(p.status, 'PLAN_READY_FOR_REVIEW'); assert.equal(p.executable, false);
  assert.equal(p.dataMigrationExecuted, false); assert.equal(p.activationIncluded, false);
  assert.ok(p.writes.every(w => !w.path.includes('stock_catalog_control')));
  assert.equal(planned(p, 'estoque_produtos/p').data.stockKind, 'simple');
  assert.equal(planned(p, 'produtos/p').data.quantidade, 1);
  assert.equal(planned(p, 'produtos/p').data.catalogStockRevision, 0);
});
test('missing authority never borrows positive stock from catalog', () => {
  const f = fixture(); delete f.stock.p.quantidade; f.draft.p = {quantidade: 100, publicadoNoCatalogo: true};
  blocked(f, 'Invalid canonical stock quantity');
  f.stock = {}; f.live.p = {id: 'p', quantidade: 100}; blocked(f, 'UNPROVEN_LEGACY_COPY');
});
test('variable grade missing blocks instead of silently converting to zero', () => {
  const f = fixture(); f.stock.p = {...stock, tamanhos: ['P'], variacoes: null};
  blocked(f, 'MISSING_CANONICAL_GRADE');
});
test('explicit exhausted grade never inherits old draft or aggregates', () => {
  for (const grade of [{P: {Azul: 0}}, {}]) {
    const f = fixture(); f.stock.p = {...stock, variacoes: grade, tamanhos: ['P'], estoquePorTamanho: {P: 9}};
    f.draft.p = {id: 'p', quantidade: 99, estoque_atual: 99, publicadoNoCatalogo: true};
    const p = planStockCatalogMigration(f, owner);
    assert.equal(p.status, 'PLAN_READY_FOR_REVIEW');
    assert.equal(planned(p, 'estoque_produtos/p').data.quantidade, 0);
    assert.equal(planned(p, 'produtos/p').action, 'delete');
  }
});
test('revision is preserved; invalid revision blocks and is never reset', () => {
  const f = fixture(); f.stock.p.stockRevision = 8;
  assert.equal(planned(planStockCatalogMigration(f, owner), 'produtos/p').data.catalogStockRevision, 8);
  f.stock.p.stockRevision = -1; blocked(f, 'Invalid canonical stock quantity');
});
test('verified slug copy can be planned for removal; collision/name-only cannot', () => {
  const f = fixture(); f.stock.p.slug = 'peca'; f.live.peca = {id: 'p', nome: 'Peça'};
  assert.equal(planned(planStockCatalogMigration(f, owner), 'produtos/peca').canonicalOwner, 'p');
  f.live.peca = {nome: 'Peça', slug: 'peca'}; blocked(f, 'UNPROVEN_LEGACY_COPY');
  f.live.peca = {id: 'p'}; f.stock.peca = {...stock, id: 'peca'}; blocked(f, 'CATALOG_ID_COLLISION');
});
test('full tombstone hides live; partial and orphan tombstones block for reconciliation', () => {
  const f = fixture(); f.tombstones.p = {p: true};
  const p = planStockCatalogMigration(f, owner);
  assert.equal(planned(p, 'produtos/p').action, 'delete');
  assert.equal(planned(p, 'estoque_produtos/p').data.pendingSoftDelete, true);
  f.tombstones.p = {p: false, v: {'V::P': true}}; blocked(f, 'PARTIAL_TOMBSTONE');
  f.tombstones = {unknown: {p: true}}; blocked(f, 'ORPHAN_TOMBSTONE');
});
test('legacy markers, pending intents and any pre-cutover order prevent invented replay history', () => {
  for (const name of ['legacyOperations','pendingIntents','orders']) {
    const f = fixture(); f[name].old = {paid: true, baixaAplicada: true};
    blocked(f, name === 'orders' ? 'OPERATION_ID_RECONCILIATION' : 'REQUIRE_RECONCILIATION');
  }
});
test('grants cannot be inferred from profiles, a mismatched store, or arbitrary permission fields', () => {
  const f = fixture(); f.profiles = {attacker: {admin: true}};
  blocked(f, 'OWNERSHIP_MANIFEST_REQUIRED', null);
  blocked(f, 'OWNERSHIP_MANIFEST_REQUIRED', {...owner, lojaId: 'b'});
  blocked(f, 'INVALID_TRUSTED_GRANT', {...owner, grants: {attacker: {enabled: true, permissions: {admin: true}}}});
});
test('maintenance and complete frozen inventory are mandatory', () => {
  const f = fixture(); f.control.mode = 'active'; blocked(f, 'MAINTENANCE_REQUIRED');
  f.control.mode = 'maintenance'; delete f.orders; blocked(f, 'COMPLETE_COLLECTION_REQUIRED:orders');
  f.orders = {}; f.attestations.legacyAdminWritersDrained = false; blocked(f, 'legacyAdminWritersDrained');
});
test('combo dependencies rebuilt, capacity bounded by components; missing/cyclic recipes block', () => {
  const f = fixture(); f.stock.kit = {...stock, id: 'kit', tipoProduto: 'combo', quantidade: 8, itensCombo: [{productId: 'p', quantidade: 1}]};
  const p = planStockCatalogMigration(f, owner);
  assert.equal(planned(p, 'estoque_produtos/kit').data.quantidade, 1);
  assert.deepEqual(planned(p, 'stock_catalog_dependencies/p').data.comboIds, ['kit']);
  f.stock.kit.itensCombo[0].productId = 'missing'; blocked(f, 'Missing recipe component');
  f.stock.kit.itensCombo[0].productId = 'kit'; blocked(f, 'Cyclic combo recipe');
});
test('private cost survives canonical migration but never reaches catalog', () => {
  const f = fixture(); f.stock.p.variacoes = {P: {Azul: {_sem_extra: 1, __custoUnitario: 10.25}}};
  const p = planStockCatalogMigration(f, owner);
  assert.equal(planned(p, 'estoque_produtos/p').data.variacoes.P.Azul.__custoUnitario, 10.25);
  assert.equal(planned(p, 'produtos/p').data.variacoes.P.Azul.__custoUnitario, undefined);
});

test('omitted old grants are removed and required server identities must be explicit', () => {
  const f = fixture(); f.access.formerOwner = {enabled: true, permissions: {sale: true}};
  const p = planStockCatalogMigration(f, owner);
  assert.equal(planned(p, 'stock_catalog_access/formerOwner').action, 'delete');
  const missing = structuredClone(owner); delete missing.grants['stock-catalog-payment'];
  blocked(f, 'REQUIRED_SERVICE_GRANT_MISSING', missing);
});
test('oversized connected combo graph blocks instead of enabling unusable transactions', () => {
  const f = fixture();
  for (let n = 0; n < 25; n++) f.stock[`kit${n}`] = {...stock, id: `kit${n}`, tipoProduto: 'combo', itensCombo: [{productId: 'p'}]};
  blocked(f, 'CONNECTED_COMPONENT_EXCEEDS_TRANSACTION_BUDGET');
});

test('ranking from a legacy public mirror never silently overwrites or disappears from canonical', () => {
  const f = fixture(); f.live.p = {id: 'p', vendasCatalogoTotal: 12};
  blocked(f, 'CATALOG_COUNTER_REQUIRES_RECONCILIATION');
  f.stock.p.vendasCatalogoTotal = 12;
  assert.equal(planned(planStockCatalogMigration(f, owner), 'produtos/p').data.vendasCatalogoTotal, 12);
});
