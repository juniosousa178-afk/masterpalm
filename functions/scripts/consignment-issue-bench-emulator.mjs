// Firestore emulator only: times consignment issue for 25/32/40/50 distinct products and checks
// 51-product rejection, end-of-transaction atomicity and same-operationId replay.
// Run: npx firebase-tools emulators:exec --only firestore --project demo-consignment-bench "node functions/scripts/consignment-issue-bench-emulator.mjs"
import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Refusing to run without FIRESTORE_EMULATOR_HOST');
const db = getFirestore(initializeApp({projectId: 'demo-consignment-bench'}));
const owner = {uid: 'owner'};
const RUNS = 3;
let seq = 0;

const ids = n => Array.from({length: n}, (_, i) => `P${String(i + 1).padStart(2, '0')}`);
const cmd = (lojaId, operation, operationId, payload, consignmentId) =>
  ({protocolVersion: 1, lojaId, operation, operationId, consignmentId, payload});
const line = productId => ({productId, qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0});

async function seedStore(n, qty) {
  const lojaId = `bench_${Date.now()}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, {ownerUid: 'owner', lojaId});
  batch.set(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  batch.set(base.collection('consignment_resellers').doc('r1'), {
    storeId: lojaId, resellerId: 'r1', displayName: 'Revendedora Bench', active: true, notes: '',
  });
  for (const id of ids(n)) {
    batch.set(base.collection('estoque_produtos').doc(id), {
      lojaId, quantidade: qty, stockKind: 'simple', tipoProduto: 'simples', stockRevision: 3, variacoes: {},
    });
    batch.set(base.collection('draft_produtos').doc(id), {nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: 10});
    batch.set(base.collection('produtos').doc(id), {nome: `Produto ${id}`, quantidade: qty, preco: 10});
    batch.set(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  await batch.commit();
  return {lojaId, base};
}

async function draft(lojaId, productIds) {
  const id = `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `draft_${id}`, {
    resellerId: 'r1', notes: '', lines: productIds.map(line),
  }, id), owner);
  return id;
}

async function quantities(base, n) {
  const snaps = await db.getAll(...ids(n).map(id => base.collection('estoque_produtos').doc(id)));
  return snaps.map(s => s.data().quantidade);
}

const out = {};
for (const n of [25, 32, 40, 50]) {
  const times = [];
  for (let r = 0; r < RUNS; r++) {
    const {lojaId, base} = await seedStore(n, 2);
    const id = await draft(lojaId, ids(n));
    const t0 = performance.now();
    const res = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
    times.push(performance.now() - t0);
    if (res.status !== 'ISSUED') throw new Error(`issue ${n} not issued`);
    const q = await quantities(base, n);
    if (!q.every(v => v === 1)) throw new Error(`issue ${n} stock mismatch`);
    if (r === 0 && n === 50) {
      const replay = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
      const q2 = await quantities(base, n);
      const docs = await base.collection('consignments').get();
      out.ISSUE_50_RETRY_IDEMPOTENT = replay.alreadyApplied === true && q2.every(v => v === 1) && docs.size === 1;
      const doc = (await base.collection('consignments').doc(id).get()).data();
      out.ISSUE_50_INITIAL_CREATED_AT_IS_TIMESTAMP = doc.additions[0].createdAt?.constructor?.name === 'Timestamp';
    }
  }
  times.sort((a, b) => a - b);
  out[`ISSUE_${n}_MS`] = Math.round(times[Math.floor(times.length / 2)]);
}

{
  const {lojaId, base} = await seedStore(51, 1);
  const id = await draft(lojaId, ids(50));
  const ref = base.collection('consignments').doc(id);
  const doc = (await ref.get()).data();
  await ref.set({...doc, lines: [...doc.lines, {...doc.lines[0], productId: 'P51', lineId: 'P51::legacy'}]});
  let code = null;
  try { await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner); }
  catch (e) { code = e.consignmentCode; }
  const q = await quantities(base, 51);
  out.ISSUE_51_REJECTED = code === 'CONSIGNMENT_PRODUCT_LIMIT' && q.every(v => v === 1);
}

{
  const {lojaId, base} = await seedStore(50, 1);
  const id = await draft(lojaId, ids(50));
  await base.collection('consignment_audit').doc(`issue_${id}`).set({type: 'PREEXISTING'});
  let failed = false;
  try { await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner); }
  catch { failed = true; }
  const q = await quantities(base, 50);
  const status = (await base.collection('consignments').doc(id).get()).data().status;
  const op = await base.collection('consignment_operations').doc(`issue_${id}`).get();
  out.ISSUE_50_ATOMICITY_TEST_PASS = failed && q.every(v => v === 1) && status === 'DRAFT' && !op.exists;
}

console.log(JSON.stringify(out, null, 1));
