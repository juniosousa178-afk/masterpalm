/**
 * Unit tests — global stock health classifier refinement.
 * node --test functions/test/global_stock_health_classifier.test.mjs
 */
import {describe, it} from 'node:test';
import assert from 'node:assert/strict';
import {
  computeOperationalQty,
  classifyProductStructure,
  physicalRecountCount,
  riskForTenant,
  classifySaleBinding,
  saleBindingRaisesOperationalRisk,
} from '../scripts/lib/global_stock_health_classifier.mjs';

describe('Nathy operational qty 818', () => {
  it('excludes p=true tombstones: 1165 - 347 = 818', () => {
    const products = [];
    const tombsById = new Map();
    // 818 operational as one product for simplicity + 129 tombstoned totaling 347
    products.push({id: 'live-bulk', quantidade: 818});
    let remaining = 347;
    for (let i = 0; i < 129; i++) {
      const id = `tomb-${i}`;
      if (i < 128) {
        products.push({id, quantidade: 2});
        remaining -= 2;
      } else {
        products.push({id, quantidade: remaining});
      }
      tombsById.set(id, {p: true});
    }
    const all = products.reduce((s, p) => s + p.quantidade, 0);
    assert.equal(all, 1165);
    const qty = computeOperationalQty(products, tombsById);
    assert.equal(qty.REMOTE_ALL_DOCS_QTY, 1165);
    assert.equal(qty.REMOTE_ARCHIVED_TOMBSTONED_QTY, 347);
    assert.equal(qty.REMOTE_ARCHIVED_TOMBSTONED_PRODUCT_COUNT, 129);
    assert.equal(qty.REMOTE_OPERATIONAL_QTY, 818);
  });
});

describe('C2 LEGACY_SIZE_METADATA_ONLY', () => {
  it('qty positive + metadata size + no cells → C2 STRUCTURAL_LEGACY, no recount', () => {
    const p = {
      id: 'legacy-1',
      quantidade: 5,
      tamanhos: ['14', '15', '16'],
      cores: ['prata'],
      estoquePorTamanho: {14: 2, 15: 2, 16: 1},
      variacoes: {},
    };
    const c = classifyProductStructure(p, null);
    assert.equal(c.CLASS, 'C2');
    assert.equal(c.STRUCTURAL_LABEL, 'LEGACY_SIZE_METADATA_ONLY');
    assert.equal(c.PHYSICAL_RECOUNT, false);
    assert.equal(c.STRUCTURAL_LEGACY, true);
    assert.equal(physicalRecountCount([c]), 0);
  });
});

describe('C4 full tombstone', () => {
  it('p=true must not affect operational qty/risk', () => {
    const products = [
      {id: 'alive', quantidade: 10},
      {id: 'dead', quantidade: 99},
    ];
    const tombsById = new Map([['dead', {p: true}]]);
    const qty = computeOperationalQty(products, tombsById);
    assert.equal(qty.REMOTE_OPERATIONAL_QTY, 10);
    assert.equal(qty.REMOTE_ARCHIVED_TOMBSTONED_QTY, 99);

    const c = classifyProductStructure(products[1], tombsById.get('dead'));
    assert.equal(c.CLASS, 'C4');
    assert.equal(c.OPERATIONAL, false);
    assert.equal(c.PHYSICAL_RECOUNT, false);

    const health = riskForTenant({
      CRITICAL_HINTS: [],
      TRUE_PHYSICAL_RECOUNT_COUNT: 0,
      UNRECOVERABLE_BINDING_COUNT: 0,
      AMBIGUOUS_BINDING_COUNT: 0,
      PENDING_COUNT: 0,
      ACTIVE_LINEAGE_RISK_COUNT: 0,
      CLASS_A_PROJECTION_COUNT: 0,
      CLASS_B_COUNT: 0,
      CLASS_C2_LEGACY_COUNT: 1,
      CLASS_C4_TOMBSTONE_COUNT: 1,
      CLASS_C5_COUNT: 0,
      HISTORICAL_LINEAGE_COUNT: 5,
      STALE_TOMBSTONE_COUNT: 2,
    });
    assert.equal(health, 'HEALTHY');
  });
});

describe('Class A projection repair candidate', () => {
  it('aggregate != canonical cell sum → CLASS A', () => {
    const p = {
      id: 'proj-1',
      quantidade: 0,
      variacoes: {U: {prata: 1}},
      tamanhos: ['U'],
      cores: ['prata'],
    };
    const c = classifyProductStructure(p, null);
    assert.equal(c.CLASS, 'A');
    assert.equal(c.PROJECTION_REPAIR_CANDIDATE, true);
    assert.equal(c.PHYSICAL_RECOUNT, false);
    assert.equal(c.CANONICAL_CELL_SUM, 1);
    assert.equal(c.AGGREGATE_QTY, 0);
  });
});

describe('Physical recount rule', () => {
  it('C2 must NOT count toward physical recount', () => {
    const c2 = classifyProductStructure({
      id: 'x',
      quantidade: 3,
      tamanhos: ['10'],
      variacoes: {},
    }, null);
    assert.equal(c2.CLASS, 'C2');
    assert.equal(physicalRecountCount([c2]), 0);
  });
});

describe('Sale binding operational risk', () => {
  it('only unrecoverable/ambiguous raise risk', () => {
    const ops = new Map([
      ['op1', {id: 'op1', status: 'applied', kind: 'sale'}],
    ]);
    assert.equal(classifySaleBinding({id: 's1', stockOperationId: 'op1'}, ops), 'MODERN_EXPLICIT_BINDING');
    assert.equal(saleBindingRaisesOperationalRisk('MODERN_EXPLICIT_BINDING'), false);
    assert.equal(saleBindingRaisesOperationalRisk('LEGACY_NO_EXPLICIT_BINDING_SAFE'), false);
    assert.equal(saleBindingRaisesOperationalRisk('UNRECOVERABLE_BINDING'), true);
    assert.equal(saleBindingRaisesOperationalRisk('AMBIGUOUS_BINDING'), true);
    assert.equal(
      classifySaleBinding({id: 's2', stockOperationId: 'missing-op'}, ops),
      'UNRECOVERABLE_BINDING',
    );
  });
});

describe('Tenant health with Class A', () => {
  it('Class A → REVIEW not BLOCKED', () => {
    assert.equal(riskForTenant({
      CRITICAL_HINTS: [],
      TRUE_PHYSICAL_RECOUNT_COUNT: 0,
      UNRECOVERABLE_BINDING_COUNT: 0,
      AMBIGUOUS_BINDING_COUNT: 0,
      PENDING_COUNT: 0,
      ACTIVE_LINEAGE_RISK_COUNT: 0,
      CLASS_A_PROJECTION_COUNT: 3,
      CLASS_B_COUNT: 0,
      CLASS_C5_COUNT: 0,
    }), 'REVIEW');
  });
});
