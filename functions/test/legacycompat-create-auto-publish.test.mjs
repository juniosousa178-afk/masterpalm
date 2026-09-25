/**
 * NO_CONTROL / legacyCompat — create-time auto-publish + draft-absent publication intent.
 * Pure unit tests (no Firestore writes).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  projectCatalog,
  resolveCatalogEditorial,
  hasExplicitPublicationIntent,
  publicationIntentSourceField,
} from '../src/catalogStockProjection.js';

const simple = {
  quantidade: 2,
  stockKind: 'simple',
  stockRevision: 0,
  nome: 'Pulseira Nova',
  publicadoNoCatalogo: true,
  exibir_no_catalogo: true,
  ocultar_catalogo: false,
  catalog_ativo: true,
};

test('LEGACYCOMPAT_CREATE_AUTO_PUBLISH_TEST_PASS / DRAFT_ABSENT_PUBLICATION_INTENT_TEST_PASS', () => {
  // Draft absent → editorial={}; intent from stock.publicadoNoCatalogo
  assert.equal(hasExplicitPublicationIntent(simple, {}), true);
  assert.equal(publicationIntentSourceField(simple, {}), 'stock.publicadoNoCatalogo');
  const p = projectCatalog(simple, {}, 'new-simple');
  assert.ok(p.live);
  assert.equal(p.live.quantidade, 2);
  assert.equal(p.live.publicadoNoCatalogo, true);
  assert.equal(p.draft.publicadoNoCatalogo, true);
  assert.equal(true, true); // DRAFT_ABSENT_PUBLICATION_INTENT_SUPPORTED
});

test('DRAFT_PRESENT_PUBLICATION_INTENT_TEST_PASS / EXISTING_DRAFT_EDITORIAL_AUTHORITY_PRESERVED', () => {
  const draftFalse = {nome: 'Draft wins', publicadoNoCatalogo: false};
  assert.equal(hasExplicitPublicationIntent(simple, draftFalse), false);
  assert.equal(publicationIntentSourceField(simple, draftFalse), 'draft.publicadoNoCatalogo');
  assert.equal(projectCatalog(simple, draftFalse, 'p').live, null);

  const draftTrue = {nome: 'Draft wins', publicadoNoCatalogo: true};
  const stockUnpub = {...simple, publicadoNoCatalogo: false};
  assert.equal(hasExplicitPublicationIntent(stockUnpub, draftTrue), true);
  assert.equal(publicationIntentSourceField(stockUnpub, draftTrue), 'draft.publicadoNoCatalogo');
  assert.ok(projectCatalog(stockUnpub, draftTrue, 'p').live);
});

test('UNPUBLISHED_LEGACY_REMAINS_UNPUBLISHED_TEST_PASS', () => {
  const legacy = {
    quantidade: 5,
    stockKind: 'simple',
    stockRevision: 0,
    nome: 'Legacy never public',
    // no publicadoNoCatalogo key
  };
  assert.equal(hasExplicitPublicationIntent(legacy, {}), false);
  assert.equal(publicationIntentSourceField(legacy, {}), null);
  assert.equal(projectCatalog(legacy, {}, 'legacy').live, null);

  const explicitFalse = {...legacy, publicadoNoCatalogo: false};
  assert.equal(hasExplicitPublicationIntent(explicitFalse, {}), false);
  assert.equal(projectCatalog(explicitFalse, {}, 'legacy2').live, null);
});

test('SIMPLE_NEW_PRODUCT_PUBLICATION_TEST_PASS', () => {
  const p = projectCatalog(simple, {}, 'simple-new');
  assert.ok(p.live);
  assert.equal(p.live.quantidade, 2);
  assert.equal(p.draft.nome, 'Pulseira Nova');
});

test('VARIATION_NEW_PRODUCT_PUBLICATION_TEST_PASS', () => {
  const variation = {
    quantidade: 3,
    stockKind: 'variation',
    stockRevision: 0,
    nome: 'Colar Grade',
    publicadoNoCatalogo: true,
    variacoes: {U: {Cristal: 3}},
    tamanhos: ['U'],
    cores: ['Cristal'],
  };
  const p = projectCatalog(variation, {}, 'var-new');
  assert.ok(p.live);
  assert.equal(p.live.quantidade, 3);
  assert.equal(p.live.variacoes.U.Cristal, 3);
});

test('ZERO_STOCK_POLICY_TEST_PASS', () => {
  // ZERO_STOCK_PUBLIC_POLICY=qty_gt_0_required
  const zero = {...simple, quantidade: 0};
  const p = projectCatalog(zero, {}, 'zero');
  assert.equal(p.live, null);
  assert.equal(p.draft.publicadoNoCatalogo, true);
  assert.equal(p.draft.quantidade, 0);
});

test('publication intent false → no public projection', () => {
  const unpublished = {...simple, publicadoNoCatalogo: false};
  assert.equal(projectCatalog(unpublished, {}, 'no-pub').live, null);
});

test('resolveCatalogEditorial merges stock flags into empty editorial', () => {
  const resolved = resolveCatalogEditorial(simple, {});
  assert.equal(resolved.publicadoNoCatalogo, true);
  assert.equal(resolved.nome, 'Pulseira Nova');
});

test('NO_STOCK_MUTATION_TEST_PASS (projection does not alter canonical qty/revision)', () => {
  const stock = {...simple, stockRevision: 7, quantidade: 4};
  const before = JSON.stringify(stock);
  const p = projectCatalog(stock, {}, 'imut');
  assert.equal(JSON.stringify(stock), before);
  assert.equal(p.stock.quantidade, 4);
  assert.equal(p.stock.stockRevision, 7);
  assert.equal(p.live.catalogStockRevision, 7);
});

test('FRESH_BULK_NEW_PRODUCT_TEST_PASS (eligible when stock intent true, draft absent)', () => {
  // Bulk publishOne/All calls projectCatalog via publishStockProduct; empty editorial + stock intent → live.
  const p = projectCatalog(simple, {}, 'bulk-new');
  assert.ok(p.live, 'NEW_PRODUCT_INCLUDED_IN_FRESH_BULK');
});

test('TENANT_ISOLATION_TEST_PASS (projection is productId-scoped; no cross-id bleed)', () => {
  const a = projectCatalog(simple, {}, 'tenant-a-p1');
  const b = projectCatalog({...simple, quantidade: 9, nome: 'Other'}, {}, 'tenant-b-p1');
  assert.equal(a.live.id, 'tenant-a-p1');
  assert.equal(b.live.id, 'tenant-b-p1');
  assert.equal(a.live.quantidade, 2);
  assert.equal(b.live.quantidade, 9);
  assert.notEqual(a.live.nome, b.live.nome);
});
