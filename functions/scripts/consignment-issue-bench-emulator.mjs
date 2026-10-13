// Firestore emulator only: times consignment issue / return / settle for 50/100/125/150 distinct products
// (median + p95), and checks 151 rejection, atomicity, replay, concurrent stock contention and post-commit projection.
// Run: npx firebase-tools emulators:exec --only firestore --project demo-consignment-bench "node functions/scripts/consignment-issue-bench-emulator.mjs"
import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT} from '../src/consignmentProtocol.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Refusing to run without FIRESTORE_EMULATOR_HOST');
const db = getFirestore(initializeApp({projectId: 'demo-consignment-bench'}));
const owner = {uid: 'owner'};
const RUNS = 7;
const CALLABLE_TIMEOUT_MS = 60000;
const N = MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT;
let seq = 0;

const ids = n => Array.from({length: n}, (_, i) => `nathy-pratas-colar-letra-${String(i + 1).padStart(3, '0')}`);
const cmd = (lojaId, operation, operationId, payload, consignmentId) =>
  ({protocolVersion: 1, lojaId, operation, operationId, consignmentId, payload});
const line = (productId, qtySent = 1) =>
  ({productId, qtySent, unitSalePrice: 89.9, commissionType: 'PERCENTUAL', commissionValue: 30});

async function commitInChunks(writes) {
  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    for (const [ref, data] of writes.slice(i, i + 400)) batch.set(ref, data);
    await batch.commit();
  }
}

async function seedStore(n, qty) {
  const lojaId = `bench_${Date.now()}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  const writes = [
    [base, {ownerUid: 'owner', lojaId}],
    [base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true}],
    [base.collection('consignment_resellers').doc('r1'), {
      storeId: lojaId, resellerId: 'r1', displayName: 'Revendedora Bench', active: true, notes: '',
    }],
  ];
  for (const id of ids(n)) {
    writes.push([base.collection('estoque_produtos').doc(id), {
      lojaId, quantidade: qty, stockKind: 'simple', tipoProduto: 'simples', stockRevision: 3, variacoes: {},
    }]);
    writes.push([base.collection('draft_produtos').doc(id), {nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: 89.9}]);
    writes.push([base.collection('produtos').doc(id), {nome: `Produto ${id}`, quantidade: qty, preco: 89.9}]);
    writes.push([base.collection('stock_catalog_dependencies').doc(id), {comboIds: []}]);
  }
  await commitInChunks(writes);
  return {lojaId, base};
}

async function draft(lojaId, productIds, qty = 1) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {
    resellerId: 'r1', notes: '', lines: productIds.map(p => line(p, qty)),
  }, id), owner);
  return id;
}

async function quantities(base, n) {
  const snaps = await db.getAll(...ids(n).map(id => base.collection('estoque_produtos').doc(id)));
  return snaps.map(s => s.data().quantidade);
}

/** Times the stock commit separately from the full callable (commit + inline projection). */
async function timed(command) {
  const realRun = db.runTransaction.bind(db);
  let commitMs = null;
  const t0 = performance.now();
  db.runTransaction = (fn, opts) => realRun(fn, opts).then(r => {
    if (commitMs === null) commitMs = performance.now() - t0;
    return r;
  });
  try {
    const res = await executeConsignmentCommand(db, command, owner);
    return {res, commitMs, totalMs: performance.now() - t0};
  } finally {
    db.runTransaction = realRun;
  }
}

const stats = values => {
  const s = [...values].sort((a, b) => a - b);
  return {median: Math.round(s[Math.floor(s.length / 2)]), p95: Math.round(s[Math.min(s.length - 1, Math.ceil(s.length * 0.95) - 1)])};
};

const out = {};
let maxMs = 0;
for (const n of [50, 100, 125, 150]) {
  const issue = {commit: [], total: []};
  const ret = {commit: [], total: []};
  const settle = {commit: [], total: []};
  for (let r = 0; r < RUNS; r++) {
    const {lojaId, base} = await seedStore(n, 3);
    const id = await draft(lojaId, ids(n), 2);
    const a = await timed(cmd(lojaId, 'issue', `issue_${id}`, {}, id));
    if (a.res.status !== 'ISSUED') throw new Error(`issue ${n} not issued`);
    if (!(await quantities(base, n)).every(v => v === 1)) throw new Error(`issue ${n} stock mismatch`);
    issue.commit.push(a.commitMs); issue.total.push(a.totalMs);
    if (r === 0) {
      const op = (await base.collection('consignment_operations').doc(`issue_${id}`).get()).data();
      const drafts = await db.getAll(...ids(n).map(p => base.collection('draft_produtos').doc(p)));
      const stocks = await db.getAll(...ids(n).map(p => base.collection('estoque_produtos').doc(p)));
      out[`PROJECTION_${n}_DONE_INLINE`] = op.projection?.status === 'DONE'
        && drafts.every((d, i) => d.data().catalogStockRevision === stocks[i].data().stockRevision);
    }
    let doc = (await base.collection('consignments').doc(id).get()).data();
    const b = await timed(cmd(lojaId, 'returnItems', `ret_${id}`, {
      expectedRevision: doc.revision,
      lines: doc.lines.map(l => ({lineId: l.lineId, productId: l.productId, variationKey: l.variationKey, qty: 1})),
    }, id));
    if (!(await quantities(base, n)).every(v => v === 2)) throw new Error(`return ${n} stock mismatch`);
    ret.commit.push(b.commitMs); ret.total.push(b.totalMs);
    doc = (await base.collection('consignments').doc(id).get()).data();
    const c = await timed(cmd(lojaId, 'settle', `settle_${id}`, {
      lines: doc.lines.map((l, i) => ({lineId: l.lineId, qtySold: i % 2, qtyReturned: 1 - (i % 2)})),
    }, id));
    if (c.res.status !== 'SETTLED') throw new Error(`settle ${n} not settled`);
    settle.commit.push(c.commitMs); settle.total.push(c.totalMs);
    maxMs = Math.max(maxMs, a.totalMs, b.totalMs, c.totalMs);
    if (r === 0 && n === N) {
      const replay = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
      const docs = await base.collection('consignments').get();
      const audits = await base.collection('consignment_audit').where('type', '==', 'CONSIGNMENT_ISSUE').get();
      out.ISSUE_150_RETRY_IDEMPOTENT = replay.alreadyApplied === true && docs.size === 1 && audits.size === 1;
    }
  }
  for (const [name, m] of [['ISSUE', issue], ['RETURN', ret], ['SETTLE', settle]]) {
    const commit = stats(m.commit);
    const total = stats(m.total);
    out[`${name}_${n}_COMMIT_MEDIAN_MS`] = commit.median;
    out[`${name}_${n}_COMMIT_P95_MS`] = commit.p95;
    out[`${name}_${n}_TOTAL_MEDIAN_MS`] = total.median;
    out[`${name}_${n}_TOTAL_P95_MS`] = total.p95;
  }
}
out.MAX_OBSERVED_MS = Math.round(maxMs);
out.NO_TIMEOUT_AT_150 = maxMs < CALLABLE_TIMEOUT_MS;

{
  const {lojaId, base} = await seedStore(N + 1, 1);
  const id = await draft(lojaId, ids(N));
  const ref = base.collection('consignments').doc(id);
  const doc = (await ref.get()).data();
  const extra = ids(N + 1)[N];
  await ref.set({...doc, lines: [...doc.lines, {...doc.lines[0], productId: extra, lineId: `${extra}::legacy`}]});
  let code = null;
  try { await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner); }
  catch (e) { code = e.consignmentCode; }
  out.ISSUE_151_REJECTED = code === 'CONSIGNMENT_PRODUCT_LIMIT' && (await quantities(base, N + 1)).every(v => v === 1);
}

{
  const {lojaId, base} = await seedStore(N, 1);
  const id = await draft(lojaId, ids(N));
  await base.collection('consignment_audit').doc(`issue_${id}`).set({type: 'PREEXISTING'});
  let failed = false;
  try { await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner); }
  catch { failed = true; }
  const status = (await base.collection('consignments').doc(id).get()).data().status;
  const op = await base.collection('consignment_operations').doc(`issue_${id}`).get();
  out.ISSUE_150_ATOMICITY_TEST_PASS = failed && (await quantities(base, N)).every(v => v === 1) && status === 'DRAFT' && !op.exists;
}

// Real emulator contention: a PDV-like transactional sale of the last product races the 150 issue.
{
  const trials = 5;
  let consistent = 0;
  const outcomes = {issueWon: 0, saleWon: 0, bothApplied: 0, neither: 0};
  for (let t = 0; t < trials; t++) {
    const {lojaId, base} = await seedStore(N, 1);
    const id = await draft(lojaId, ids(N));
    const lastRef = base.collection('estoque_produtos').doc(ids(N)[N - 1]);
    const sale = db.runTransaction(async tx => {
      const s = await tx.get(lastRef);
      const q = s.data().quantidade;
      if (q < 1) return false;
      tx.update(lastRef, {quantidade: q - 1, stockRevision: s.data().stockRevision + 1, stockOperationId: `pdv_${t}`});
      return true;
    });
    const issue = executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner)
      .then(() => true, () => false);
    const [saleOk, issueOk] = await Promise.all([sale, issue]);
    const q = await quantities(base, N);
    const status = (await base.collection('consignments').doc(id).get()).data().status;
    const others = q.slice(0, N - 1);
    const last = q[N - 1];
    let ok = false;
    if (issueOk && !saleOk) ok = status === 'ISSUED' && others.every(v => v === 0) && last === 0;
    if (!issueOk && saleOk) ok = status === 'DRAFT' && others.every(v => v === 1) && last === 0;
    if (!issueOk && !saleOk) ok = status === 'DRAFT' && q.every(v => v === 1);
    if (ok) consistent++;
    if (issueOk && !saleOk) outcomes.issueWon++;
    else if (!issueOk && saleOk) outcomes.saleWon++;
    else if (issueOk && saleOk) outcomes.bothApplied++;
    else outcomes.neither++;
  }
  out.CONCURRENT_150_TRIALS = trials;
  out.CONCURRENT_150_OUTCOMES = outcomes;
  out.CONCURRENT_STOCK_CHANGE_150_ATOMIC = consistent === trials;
}

console.log(JSON.stringify(out, null, 1));
