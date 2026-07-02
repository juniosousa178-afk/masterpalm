/**
 * Fase R2-A — operação atômica V1 estoque simples + marker.
 * projectId: demo-masterpalm-pdv-v1-r2
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dir = dirname(fileURLToPath(import.meta.url));
const rulesTestingUrl = pathToFileURL(
  join(__dir, "../../../functions/node_modules/@firebase/rules-unit-testing/dist/esm/index.esm.js"),
).href;

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = await import(rulesTestingUrl);

const PROJECT_ID = "demo-masterpalm-pdv-v1-r2";
const LOJA_A = "loja-demo-pdv-v1-r2-a";
const LOJA_B = "loja-demo-pdv-v1-r2-b";
const OWNER_A_UID = "owner_pdv_v1_r2_a";
const USER_B_UID = "user_pdv_v1_r2_b";
const OUTSIDER_UID = "outsider_pdv_v1_r2";
const STOCK_DOC_ID = "prod-stock-r2a-simple";
const STOCK_QTY_FIELD = "quantidade";
const MARKER_COL = "estoque_baixa_pagamento";
const STOCK_COL = "estoque_produtos";

const V1_KEYS = [
  "protocolVersion",
  "origem",
  "operationId",
  "saleId",
  "lojaId",
  "baixaAplicada",
  "snapshotHash",
  "txItemsHash",
];

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error("ABORT: FIRESTORE_EMULATOR_HOST não definido.");
  process.exit(1);
}
if (emulatorHost.includes("masterpalm-58c46")) {
  console.error("ABORT: host contém masterpalm-58c46.");
  process.exit(1);
}
if (!PROJECT_ID.startsWith("demo-")) {
  console.error("ABORT: projectId deve começar com demo-.");
  process.exit(1);
}

function isLocalEmulatorHost(host) {
  if (!host || host.includes("masterpalm-58c46")) return false;
  const normalized = host.trim().toLowerCase();
  return (
    normalized.startsWith("localhost:") ||
    normalized.startsWith("127.0.0.1:") ||
    normalized.startsWith("[::1]:")
  );
}

if (!isLocalEmulatorHost(emulatorHost)) {
  console.error(`ABORT: host não é local: ${emulatorHost}`);
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const rules = readFileSync(join(__dir, "../../../firestore.rules"), "utf8");

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    console.log(`  OK  ${name}`);
    passed += 1;
  } catch (err) {
    console.error(` FAIL ${name}`, err?.message || err);
    failed += 1;
  }
}

function markerRef(db, lojaId, operationId) {
  return db
    .collection("lojas")
    .doc(lojaId)
    .collection(MARKER_COL)
    .doc(operationId);
}

function stockRef(db, lojaId, docId = STOCK_DOC_ID) {
  return db
    .collection("lojas")
    .doc(lojaId)
    .collection(STOCK_COL)
    .doc(docId);
}

function buildPlan({
  operationId,
  saleId = "sale-r2a-sint",
  lojaId = LOJA_A,
  snapshotHash = "snap-r2a-sint",
  txItemsHash = "tx-r2a-sint",
  quantityToDebit,
}) {
  return {
    operationId,
    saleId,
    lojaId,
    origem: "pdv",
    protocolVersion: 1,
    snapshotHash,
    txItemsHash,
    stockDocumentId: STOCK_DOC_ID,
    stockQuantityField: STOCK_QTY_FIELD,
    quantityToDebit,
  };
}

function markerPayload(plan) {
  return {
    protocolVersion: 1,
    origem: "pdv",
    operationId: plan.operationId,
    saleId: plan.saleId,
    lojaId: plan.lojaId,
    baixaAplicada: true,
    snapshotHash: plan.snapshotHash,
    txItemsHash: plan.txItemsHash,
  };
}

function evaluateMarker(plan, raw) {
  if (!raw) return "absent";
  const keys = Object.keys(raw);
  if (keys.length !== V1_KEYS.length) return "incompatible";
  for (const k of V1_KEYS) {
    if (!(k in raw)) return "incompatible";
  }
  if (raw.protocolVersion !== 1) return "incompatible";
  if (raw.origem !== "pdv") return "incompatible";
  if (raw.baixaAplicada !== true) return "incompatible";
  const expected = markerPayload(plan);
  for (const k of V1_KEYS) {
    if (raw[k] !== expected[k]) return "incompatible";
  }
  return "compatible";
}

function validateStock(stockData, plan) {
  if (!stockData) return "stock_document_invalid";
  if (!(STOCK_QTY_FIELD in stockData)) return "stock_document_invalid";
  const qty = stockData[STOCK_QTY_FIELD];
  if (typeof qty !== "number" || !Number.isInteger(qty)) {
    return "stock_document_invalid";
  }
  if (qty < 0) return "stock_document_invalid";
  if (qty < plan.quantityToDebit) return "insufficient_stock";
  return "valid";
}

async function applyAtomic(db, plan) {
  return db.runTransaction(async (transaction) => {
    const mRef = markerRef(db, plan.lojaId, plan.operationId);
    const sRef = stockRef(db, plan.lojaId, plan.stockDocumentId);

    const markerSnap = await transaction.get(mRef);
    const markerRaw = markerSnap.exists ? markerSnap.data() : null;
    const compat = evaluateMarker(plan, markerRaw);
    if (compat === "compatible") return "alreadyApplied";
    if (compat === "incompatible") return "remote_marker_identity_conflict";

    const stockSnap = await transaction.get(sRef);
    const stockRaw = stockSnap.exists ? stockSnap.data() : null;
    const stockValidation = validateStock(stockRaw, plan);
    if (stockValidation === "insufficient_stock") return "insufficient_stock";
    if (stockValidation !== "valid") return "stock_document_invalid";

    const current = stockRaw[STOCK_QTY_FIELD];
    const newQty = current - plan.quantityToDebit;
    transaction.update(sRef, { [STOCK_QTY_FIELD]: newQty });
    transaction.set(mRef, markerPayload(plan));
    return "applied";
  });
}

async function readStockQty(db, lojaId) {
  const snap = await stockRef(db, lojaId).get();
  if (!snap.exists) return null;
  return snap.data()?.[STOCK_QTY_FIELD] ?? null;
}

async function readMarker(db, lojaId, operationId) {
  const snap = await markerRef(db, lojaId, operationId).get();
  return snap.exists ? snap.data() : null;
}

function assertMarkerKeys(marker) {
  const keys = Object.keys(marker).sort();
  const expected = [...V1_KEYS].sort();
  if (keys.length !== expected.length) {
    throw new Error(`marker keys=${keys.join(",")} expected=${expected.join(",")}`);
  }
  for (let i = 0; i < keys.length; i++) {
    if (keys[i] !== expected[i]) {
      throw new Error(`marker key mismatch ${keys[i]} vs ${expected[i]}`);
    }
  }
}

async function main() {
  console.log(`Atomic R2-A | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA_A).set({
        ownerUid: OWNER_A_UID,
        ownerEmail: "owner-a@r2.local",
      });
      await db.collection("lojas").doc(LOJA_B).set({
        ownerUid: USER_B_UID,
        ownerEmail: "user-b@r2.local",
      });
      await db.collection("users").doc(OWNER_A_UID).set({
        email: "owner-a@r2.local",
        store_id: LOJA_A,
      });
      await db.collection("users").doc(USER_B_UID).set({
        email: "user-b@r2.local",
        store_id: LOJA_B,
      });
      await db.collection("users").doc(OUTSIDER_UID).set({
        email: "outsider@r2.local",
      });
    });

    const ownerA = testEnv.authenticatedContext(OWNER_A_UID, {
      email: "owner-a@r2.local",
    });
    const userB = testEnv.authenticatedContext(USER_B_UID, {
      email: "user-b@r2.local",
    });
    const outsider = testEnv.authenticatedContext(OUTSIDER_UID, {
      email: "outsider@r2.local",
    });

    console.log("A. Operação V1 válida");
    await check("A1 estoque 5, débito 2, marker ausente → applied", async () => {
      const db = ownerA.firestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await stockRef(ctx.firestore(), LOJA_A).set({
          lojaId: LOJA_A,
          [STOCK_QTY_FIELD]: 5,
          nome: "SKU R2A",
        });
      });
      const plan = buildPlan({
        operationId: "op-r2a-a1",
        quantityToDebit: 2,
      });
      const before = await readStockQty(db, LOJA_A);
      const outcome = await applyAtomic(db, plan);
      const after = await readStockQty(db, LOJA_A);
      const marker = await readMarker(db, LOJA_A, plan.operationId);
      console.log(
        `      before=${before} after=${after} outcome=${outcome} marker=${marker ? "yes" : "no"}`,
      );
      if (outcome !== "applied") throw new Error(`outcome=${outcome}`);
      if (before !== 5 || after !== 3) throw new Error("estoque incorreto");
      if (!marker) throw new Error("marker ausente");
      assertMarkerKeys(marker);
    });

    console.log("B. Repetição idempotente");
    await check("B1 mesma operação → alreadyApplied, estoque 3", async () => {
      const db = ownerA.firestore();
      const plan = buildPlan({
        operationId: "op-r2a-a1",
        quantityToDebit: 2,
      });
      const before = await readStockQty(db, LOJA_A);
      const outcome = await applyAtomic(db, plan);
      const after = await readStockQty(db, LOJA_A);
      console.log(`      before=${before} after=${after} outcome=${outcome}`);
      if (outcome !== "alreadyApplied") throw new Error(`outcome=${outcome}`);
      if (after !== 3) throw new Error("estoque mudou");
    });

    console.log("C. Saldo insuficiente");
    await check("C1 estoque 1, débito 2 → insufficient, sem marker", async () => {
      const db = ownerA.firestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await stockRef(ctx.firestore(), LOJA_A).set({
          lojaId: LOJA_A,
          [STOCK_QTY_FIELD]: 1,
        });
        await markerRef(ctx.firestore(), LOJA_A, "op-r2a-c1").delete();
      });
      const plan = buildPlan({
        operationId: "op-r2a-c1",
        quantityToDebit: 2,
      });
      const before = await readStockQty(db, LOJA_A);
      const outcome = await applyAtomic(db, plan);
      const after = await readStockQty(db, LOJA_A);
      const marker = await readMarker(db, LOJA_A, plan.operationId);
      console.log(
        `      before=${before} after=${after} outcome=${outcome} marker=${marker ? "yes" : "no"}`,
      );
      if (outcome !== "insufficient_stock") throw new Error(`outcome=${outcome}`);
      if (after !== 1) throw new Error("estoque alterado");
      if (marker) throw new Error("marker criado indevidamente");
    });

    console.log("D. Marker incompatível");
    await check("D1 marker legado → conflito, estoque intacto", async () => {
      const db = ownerA.firestore();
      const opId = "op-r2a-d1";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await stockRef(ctx.firestore(), LOJA_A).set({
          lojaId: LOJA_A,
          [STOCK_QTY_FIELD]: 4,
        });
        await markerRef(ctx.firestore(), LOJA_A, opId).set({
          lojaId: LOJA_A,
          baixaAplicada: false,
          origem: "catalogo",
        });
      });
      const plan = buildPlan({ operationId: opId, quantityToDebit: 1 });
      const before = await readStockQty(db, LOJA_A);
      const outcome = await applyAtomic(db, plan);
      const after = await readStockQty(db, LOJA_A);
      const marker = await readMarker(db, LOJA_A, opId);
      console.log(`      before=${before} after=${after} outcome=${outcome}`);
      if (outcome !== "remote_marker_identity_conflict") {
        throw new Error(`outcome=${outcome}`);
      }
      if (after !== before) throw new Error("estoque mudou");
      if (marker.origem !== "catalogo") throw new Error("marker alterado");
    });

    console.log("E. Concorrência simples");
    await check("E1 duas ops paralelas: uma applied, uma insufficient, estoque 2", async () => {
      const db = ownerA.firestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const fdb = ctx.firestore();
        await stockRef(fdb, LOJA_A).set({
          lojaId: LOJA_A,
          [STOCK_QTY_FIELD]: 5,
        });
        for (const op of ["op-r2a-e-a", "op-r2a-e-b"]) {
          const ref = markerRef(fdb, LOJA_A, op);
          const snap = await ref.get();
          if (snap.exists) await ref.delete();
        }
      });
      const planA = buildPlan({
        operationId: "op-r2a-e-a",
        quantityToDebit: 3,
      });
      const planB = buildPlan({
        operationId: "op-r2a-e-b",
        quantityToDebit: 3,
      });
      const before = await readStockQty(db, LOJA_A);
      const [outA, outB] = await Promise.all([
        applyAtomic(db, planA),
        applyAtomic(db, planB),
      ]);
      const after = await readStockQty(db, LOJA_A);
      const markers = await Promise.all([
        readMarker(db, LOJA_A, planA.operationId),
        readMarker(db, LOJA_A, planB.operationId),
      ]);
      const appliedCount = [outA, outB].filter((o) => o === "applied").length;
      const insufficientCount = [outA, outB].filter(
        (o) => o === "insufficient_stock",
      ).length;
      const markerCount = markers.filter(Boolean).length;
      console.log(
        `      before=${before} after=${after} outA=${outA} outB=${outB} markers=${markerCount}`,
      );
      if (appliedCount !== 1) throw new Error(`appliedCount=${appliedCount}`);
      if (insufficientCount !== 1) {
        throw new Error(`insufficientCount=${insufficientCount}`);
      }
      if (after !== 2) throw new Error(`after=${after}`);
      if (markerCount !== 1) throw new Error(`markerCount=${markerCount}`);
    });

    console.log("F. Isolamento de loja");
    await check("F1 user B na loja A → DENY via Rules", async () => {
      const dbB = userB.firestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await stockRef(ctx.firestore(), LOJA_A).set({
          lojaId: LOJA_A,
          [STOCK_QTY_FIELD]: 5,
        });
      });
      const plan = buildPlan({
        operationId: "op-r2a-f1",
        quantityToDebit: 1,
      });
      const before = await readStockQty(ownerA.firestore(), LOJA_A);
      await assertFails(applyAtomic(dbB, plan));
      const after = await readStockQty(ownerA.firestore(), LOJA_A);
      const marker = await readMarker(ownerA.firestore(), LOJA_A, plan.operationId);
      console.log(`      before=${before} after=${after} marker=${marker ? "yes" : "no"}`);
      if (after !== before) throw new Error("estoque A mudou");
      if (marker) throw new Error("marker A criado");
    });

    console.log("G. Outsider");
    await check("G1 outsider na loja A → DENY", async () => {
      const dbOut = outsider.firestore();
      const plan = buildPlan({
        operationId: "op-r2a-g1",
        quantityToDebit: 1,
      });
      const before = await readStockQty(ownerA.firestore(), LOJA_A);
      await assertFails(applyAtomic(dbOut, plan));
      const after = await readStockQty(ownerA.firestore(), LOJA_A);
      const marker = await readMarker(ownerA.firestore(), LOJA_A, plan.operationId);
      console.log(`      before=${before} after=${after} marker=${marker ? "yes" : "no"}`);
      if (after !== before) throw new Error("estoque mudou");
      if (marker) throw new Error("marker criado");
    });

    await check("G2 owner consegue operação válida (ALLOW smoke)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await stockRef(ctx.firestore(), LOJA_A).set({
          lojaId: LOJA_A,
          [STOCK_QTY_FIELD]: 10,
        });
      });
      const plan = buildPlan({
        operationId: "op-r2a-g2-smoke",
        quantityToDebit: 1,
      });
      await assertSucceeds(applyAtomic(ownerA.firestore(), plan));
    });
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nResultado R2-A atomic: ${passed} OK, ${failed} FAIL`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
