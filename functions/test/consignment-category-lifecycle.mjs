/**
 * Scripted consignment lifecycle over the in-memory db, parameterised by source root so identical steps can run
 * against the repository source and a downloaded deployed artifact (business-output parity). No production access.
 */
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {Timestamp} from 'firebase-admin/firestore';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

export const CATEGORY_KEYS = Object.freeze([
  'categoryAssignments', 'categoryMembershipIds', 'categoryId', 'categoryPathIds', 'categoryPathNames',
]);
export const LOJA_ID = 'lifecycle_store';
const owner = {uid: 'owner'};
const FIXED_NOW = Date.parse('2026-10-21T12:00:00.000Z');

export const PATH = {
  fem_prata: [['fem', 'fem_colar', 'fem_prata'], ['Feminino', 'Colar', 'Colar Prata 925']],
  rel_cruz: [['rel', 'rel_colar', 'rel_prata', 'rel_cruz'], ['Religioso', 'Colar', 'Colar Prata 925', 'Cruz']],
  pres_maes: [['pres', 'pres_maes'], ['Presentes', 'Dia das Mães']],
};
export const A = id => ({categoryId: id, pathIds: [...PATH[id][0]], pathNames: [...PATH[id][1]]});
const membership = assignments => [...new Set(assignments.flatMap(a => a.pathIds))];
const triple = a => ({categoryId: a.categoryId, categoryPathIds: [...a.pathIds], categoryPathNames: [...a.pathNames]});
const categorized = assignments => ({
  categoryAssignments: assignments, categoryMembershipIds: membership(assignments), ...triple(assignments[0]),
});

/** Category fields each product must keep on draft_produtos/produtos (null: no category keys at all). */
export const EXPECTED_CATEGORY_FIELDS = Object.freeze({
  'colar-cruz': categorized([A('fem_prata'), A('rel_cruz')]),
  'anel-maes': categorized([A('pres_maes')]),
  'triple-only': triple(A('rel_cruz')),
  'text-only': null,
  'sem-categoria': null,
  // Forged stored data: only well-formed paths survive, membership is re-derived, the stored triple is kept.
  'forjado': {...categorized([A('fem_prata')]), ...triple(A('fem_prata'))},
});
export const PRODUCT_IDS = Object.keys(EXPECTED_CATEGORY_FIELDS);

function draftFor(id) {
  const common = {nome: id, publicadoNoCatalogo: true, preco: 100};
  switch (id) {
    case 'colar-cruz': return {...common, categoria: 'Feminino', subcategoria: 'Colar', ...EXPECTED_CATEGORY_FIELDS[id]};
    case 'anel-maes': return {...common, categoria: 'Presentes', ...EXPECTED_CATEGORY_FIELDS[id]};
    case 'triple-only': return {...common, categoria: 'Religioso', ...EXPECTED_CATEGORY_FIELDS[id]};
    case 'text-only': return {...common, categoria: 'Brincos', subcategoria: 'Argola'};
    case 'forjado': return {
      ...common, categoria: 'Feminino', ...triple(A('fem_prata')),
      categoryAssignments: [
        {...A('fem_prata'), ownerUid: 'leak', custoUnitario: 12},
        {...A('rel_cruz'), pathIds: ['fem', 'rel_cruz'], pathNames: ['Forjado']},
        {categoryId: 'x', pathIds: ['y', 'x'], pathNames: ['X']},
        'lixo',
      ],
      categoryMembershipIds: ['outra-loja-cat', 'fem'],
    };
    default: return common;
  }
}

export function seedLifecycleStore() {
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(LOJA_ID);
  db.seed(base, {ownerUid: 'owner', lojaId: LOJA_ID});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('r1'), {
    storeId: LOJA_ID, resellerId: 'r1', displayName: 'Revendedora', active: true, notes: '',
  });
  for (const id of PRODUCT_IDS) {
    const stock = id === 'anel-maes'
      ? {stockKind: 'variation', quantidade: 8, variacoes: {P: {'sem-cor': 4}, M: {'sem-cor': 4}}}
      : {stockKind: 'simple', quantidade: 10, variacoes: {}};
    db.seed(base.collection('estoque_produtos').doc(id), {lojaId: LOJA_ID, stockRevision: 3, ...stock,
      ...(id === 'colar-cruz' ? EXPECTED_CATEGORY_FIELDS[id] : {})});
    db.seed(base.collection('draft_produtos').doc(id), draftFor(id));
    db.seed(base.collection('produtos').doc(id), {nome: id, quantidade: stock.quantidade, preco: 100});
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  return {db, base};
}

export async function loadConsignmentSource(srcRoot) {
  const url = file => pathToFileURL(join(srcRoot, file)).href;
  const [command, projection] = await Promise.all([
    import(url('consignmentCommand.js')), import(url('consignmentCatalogProjection.js')),
  ]);
  return {
    executeConsignmentCommand: command.executeConsignmentCommand,
    handleProjectionRetryEvent: projection.handleProjectionRetryEvent,
  };
}

// Structural: each source root may resolve its own firebase-admin copy, so `instanceof Timestamp` is not enough.
const isTimestamp = value => value instanceof Timestamp ||
  Object.prototype.toString.call(value) === '[object Date]' ||
  (value?.constructor?.name === 'Timestamp' && typeof value.toMillis === 'function');

/** Deterministic, comparable form: timestamps masked, keys sorted. */
export function canonical(value) {
  if (isTimestamp(value)) return '<ts>';
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  }
  return value;
}

const cmd = (operation, operationId, payload = {}, consignmentId = null) =>
  ({protocolVersion: 1, lojaId: LOJA_ID, operation, operationId, ...(consignmentId ? {consignmentId} : {}), payload});
const line = (productId, qtySent, variationKey) => ({
  productId, qtySent, unitSalePrice: 100, commissionType: 'PERCENTUAL', commissionValue: 10,
  ...(variationKey ? {variationKey} : {}),
});
const P = {size: 'P', color: 'sem-cor', extra: ''};
const retryEvent = (operationId, data) => ({data: {data: () => data}, params: {lojaId: LOJA_ID, operationId}});

/**
 * issue → withdrawal → deferred issue → retry → replayed retry → second deferred issue → partial-sale settlement →
 * stale retry (overtaken) → full settlement → command replay. Returns every step's result and snapshot.
 */
export async function runConsignmentLifecycle(src) {
  const RealDate = globalThis.Date;
  globalThis.Date = class extends RealDate {
    constructor(...args) { super(...(args.length ? args : [FIXED_NOW])); }
    static now() { return FIXED_NOW; }
  };
  try {
    const {db, base} = seedLifecycleStore();
    const run = c => src.executeConsignmentCommand(db, c, owner);
    const consignment = id => db.getData(base.collection('consignments').doc(id));
    const opDoc = id => db.getData(base.collection('consignment_operations').doc(id));
    const steps = [];
    const step = (name, result) => steps.push({name, result: canonical(result), snapshot: db.snapshot(),
      commitsSoFar: db.commits.length});

    await run(cmd('createDraft', 'draft_c1', {resellerId: 'r1', notes: '', lines: [
      line('colar-cruz', 3), line('anel-maes', 2, P), line('triple-only', 2), line('text-only', 2),
      line('sem-categoria', 2), line('forjado', 1),
    ]}, 'c1'));
    step('issue', await run(cmd('issue', 'issue_c1', {}, 'c1')));

    let doc = consignment('c1');
    const row = (productId, qty) => {
      const l = doc.lines.find(x => x.productId === productId);
      return {lineId: l.lineId, productId, variationKey: l.variationKey, qty};
    };
    step('withdrawal', await run(cmd('returnItems', 'ret_c1', {
      expectedRevision: doc.revision, lines: [row('colar-cruz', 1), row('anel-maes', 1)],
    }, 'c1')));

    const deferredIssue = async (id, lines) => {
      await run(cmd('createDraft', `draft_${id}`, {resellerId: 'r1', notes: '', lines}, id));
      db.faultInjector = ({path}) => { if (path.includes('/draft_produtos/')) throw new Error('deferred projection'); };
      try { return await run(cmd('issue', `issue_${id}`, {}, id)); } finally { db.faultInjector = null; }
    };
    step('deferredIssue', await deferredIssue('c2', [line('colar-cruz', 2), line('forjado', 1)]));
    step('retry', await src.handleProjectionRetryEvent(db, retryEvent('issue_c2', opDoc('issue_c2'))));
    step('replayRetry', await src.handleProjectionRetryEvent(db, retryEvent('issue_c2', opDoc('issue_c2'))));
    step('deferredIssue2', await deferredIssue('c3', [line('colar-cruz', 1), line('triple-only', 1)]));

    doc = consignment('c1');
    const sold = {'colar-cruz': 1, 'anel-maes': 1, 'triple-only': 1, 'text-only': 2, 'sem-categoria': 0, 'forjado': 1};
    step('partialSale', await run(cmd('settle', 'settle_c1', {lines: doc.lines.map(l => {
      const outstanding = l.qtySent - (l.qtyWithdrawn ?? 0);
      return {lineId: l.lineId, productId: l.productId, variationKey: l.variationKey,
        qtySold: sold[l.productId], qtyReturned: outstanding - sold[l.productId]};
    })}, 'c1')));

    step('staleRetry', await src.handleProjectionRetryEvent(db, retryEvent('issue_c3', opDoc('issue_c3'))));

    doc = consignment('c2');
    step('settlement', await run(cmd('settle', 'settle_c2', {lines: doc.lines.map(l => ({
      lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qtySold: l.qtySent, qtyReturned: 0,
    }))}, 'c2')));
    step('commandReplay', await run(cmd('settle', 'settle_c2', {lines: doc.lines.map(l => ({
      lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qtySold: l.qtySent, qtyReturned: 0,
    }))}, 'c2')));
    return {db, base, steps};
  } finally {
    globalThis.Date = RealDate;
  }
}

/** Snapshot with category keys removed from projected catalog docs, timestamps masked. */
export function businessView(snapshot) {
  const out = {};
  for (const [path, data] of [...snapshot.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    const projected = /\/(draft_produtos|produtos)\//.test(path);
    const kept = projected
      ? Object.fromEntries(Object.entries(data).filter(([k]) => !CATEGORY_KEYS.includes(k)))
      : data;
    out[path] = canonical(kept);
  }
  return out;
}

/** Field-level differences between two business views: [{path, key, a, b}]. */
export function diffBusinessViews(a, b) {
  const diffs = [];
  for (const path of new Set([...Object.keys(a), ...Object.keys(b)])) {
    const da = a[path];
    const dbv = b[path];
    if (!da || !dbv) { diffs.push({path, key: '<doc>', a: Boolean(da), b: Boolean(dbv)}); continue; }
    for (const key of new Set([...Object.keys(da), ...Object.keys(dbv)])) {
      if (JSON.stringify(da[key]) !== JSON.stringify(dbv[key])) diffs.push({path, key, a: da[key], b: dbv[key]});
    }
  }
  return diffs;
}
