/**
 * M3.2-B — integração PDV coordenado no Emulator (MD2-B-T1/T2/T3).
 * projectId: demo-masterpalm-sale-intent-m32b
 */
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dir = dirname(fileURLToPath(import.meta.url));
const rulesTestingUrl = pathToFileURL(
  join(__dir, "../../../functions/node_modules/@firebase/rules-unit-testing/dist/esm/index.esm.js"),
).href;
const firestoreUrl = pathToFileURL(
  join(__dir, "../../../functions/node_modules/firebase/firestore/dist/esm/index.esm.js"),
).href;

const { Timestamp } = await import(firestoreUrl);

const { initializeTestEnvironment } = await import(rulesTestingUrl);

const PROJECT_ID = "demo-masterpalm-sale-intent-m32b";
const LOJA = "loja-md2b-pdv-a";
const OWNER_UID = "owner_md2b_pdv_a";
const STOCK_DOC = "prod-md2b-stock";
const STOCK_COL = "estoque_produtos";
const MARKER_COL = "estoque_baixa_pagamento";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error("ABORT: FIRESTORE_EMULATOR_HOST não definido.");
  process.exit(1);
}
if (emulatorHost.includes("masterpalm-58c46")) {
  console.error("ABORT: host contém masterpalm-58c46.");
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

function intentRef(db, lojaId, saleIntentId) {
  return db
    .collection("lojas")
    .doc(lojaId)
    .collection("sale_intents")
    .doc(saleIntentId);
}

function markerRef(db, lojaId, operationId) {
  return db
    .collection("lojas")
    .doc(lojaId)
    .collection(MARKER_COL)
    .doc(operationId);
}

function stockRef(db, lojaId) {
  return db.collection("lojas").doc(lojaId).collection(STOCK_COL).doc(STOCK_DOC);
}

async function reserveOrJoinJs(db, { lojaId, saleIntentId, origin, stockEffectHash }) {
  const ref = intentRef(db, lojaId, saleIntentId);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) {
      const operationId = randomUUID();
      transaction.set(ref, {
        protocolVersion: 1,
        saleIntentId,
        lojaId,
        origin,
        operationId,
        status: "reserved",
        stockEffectHash,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
      return { reserveStatus: "created", operationId, status: "reserved" };
    }
    const data = snap.data();
    if (data.stockEffectHash !== stockEffectHash) {
      throw new Error("IDENTITY_CONFLICT_HASH");
    }
    if (data.origin !== origin) {
      throw new Error("IDENTITY_CONFLICT_ORIGIN");
    }
    return {
      reserveStatus: "joined",
      operationId: data.operationId,
      status: data.status,
    };
  });
}

async function baixaIdempotenteJs(db, { lojaId, operationId, qty = 1 }) {
  const mRef = markerRef(db, lojaId, operationId);
  const sRef = stockRef(db, lojaId);
  return db.runTransaction(async (transaction) => {
    const mSnap = await transaction.get(mRef);
    if (mSnap.exists && mSnap.data()?.baixaAplicada === true) {
      return "alreadyApplied";
    }
    const sSnap = await transaction.get(sRef);
    const current = sSnap.data()?.quantidade ?? 0;
    if (current < qty) return "insufficient_stock";
    transaction.update(sRef, { quantidade: current - qty });
    transaction.set(mRef, {
      protocolVersion: 1,
      origem: "pdv_manual",
      operationId,
      saleId: operationId,
      lojaId,
      baixaAplicada: true,
      snapshotHash: "md2b-test",
      txItemsHash: "md2b-test",
    });
    return "applied";
  });
}

async function main() {
  console.log(`MD2-B PDV | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA).set({
        ownerUid: OWNER_UID,
        ownerEmail: "owner-md2b@local.test",
      });
      await db.collection("users").doc(OWNER_UID).set({
        email: "owner-md2b@local.test",
        store_id: LOJA,
      });
      await stockRef(db, LOJA).set({ nome: "Prod", quantidade: 10 });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner-md2b@local.test",
    });
    const db = owner.firestore();

    console.log("MD2-B-T1 — dois devices mesma intent + baixa 1x");
    const intentT1 = `intent-md2b-t1-${Date.now()}`;
    const hashT1 = "hash-md2b-shared-t1";
    const [a, b] = await Promise.all([
      reserveOrJoinJs(db, {
        lojaId: LOJA,
        saleIntentId: intentT1,
        origin: "pdv_manual",
        stockEffectHash: hashT1,
      }),
      reserveOrJoinJs(db, {
        lojaId: LOJA,
        saleIntentId: intentT1,
        origin: "pdv_manual",
        stockEffectHash: hashT1,
      }),
    ]);
    await check("T1 mesmo operationId", async () => {
      if (a.operationId !== b.operationId) {
        throw new Error(`opIds distintos: ${a.operationId} vs ${b.operationId}`);
      }
    });
    let ba1;
    let ba2;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const dbNoRules = ctx.firestore();
      [ba1, ba2] = await Promise.all([
        baixaIdempotenteJs(dbNoRules, { lojaId: LOJA, operationId: a.operationId }),
        baixaIdempotenteJs(dbNoRules, { lojaId: LOJA, operationId: a.operationId }),
      ]);
    });
    await check("T1 baixa idempotente", async () => {
      const outcomes = [ba1, ba2].sort().join(",");
      if (outcomes !== "alreadyApplied,applied") {
        throw new Error(`baixa inesperada: ${ba1}, ${ba2}`);
      }
    });
    let stockSnap;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      stockSnap = await stockRef(ctx.firestore(), LOJA).get();
    });
    await check("T1 estoque debitado 1x", async () => {
      if (stockSnap.data()?.quantidade !== 9) {
        throw new Error(`quantidade=${stockSnap.data()?.quantidade}`);
      }
    });
    await check("T1 um marker para operationId", async () => {
      let m;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        m = await markerRef(ctx.firestore(), LOJA, a.operationId).get();
      });
      if (!m?.exists) throw new Error("marker ausente");
    });

    console.log("MD2-B-T2 — intents distintas mesmo hash");
    const hashT2 = "hash-md2b-shared-t2";
    const iA = `intent-md2b-t2a-${Date.now()}`;
    const iB = `intent-md2b-t2b-${Date.now()}`;
    const rA = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: iA,
      origin: "pdv_manual",
      stockEffectHash: hashT2,
    });
    const rB = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: iB,
      origin: "pdv_manual",
      stockEffectHash: hashT2,
    });
    await check("T2 operationIds distintos", async () => {
      if (rA.operationId === rB.operationId) {
        throw new Error("colapso por hash");
      }
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const dbNoRules = ctx.firestore();
      await baixaIdempotenteJs(dbNoRules, { lojaId: LOJA, operationId: rA.operationId });
      await baixaIdempotenteJs(dbNoRules, { lojaId: LOJA, operationId: rB.operationId });
    });
    await check("T2 dois markers novos", async () => {
      let mA;
      let mB;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const dbNoRules = ctx.firestore();
        mA = await markerRef(dbNoRules, LOJA, rA.operationId).get();
        mB = await markerRef(dbNoRules, LOJA, rB.operationId).get();
      });
      if (!mA?.exists || !mB?.exists) {
        throw new Error("markers T2 ausentes");
      }
    });

    console.log("MD2-B-T3 — hash divergente mesma intent");
    const intentT3 = `intent-md2b-t3-${Date.now()}`;
    const hashWin = "hash-md2b-t3-win";
    await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: intentT3,
      origin: "pdv_manual",
      stockEffectHash: hashWin,
    });
    let conflict = false;
    try {
      await reserveOrJoinJs(db, {
        lojaId: LOJA,
        saleIntentId: intentT3,
        origin: "pdv_manual",
        stockEffectHash: "hash-md2b-t3-loser",
      });
    } catch {
      conflict = true;
    }
    await check("T3 conflito hash", async () => {
      if (!conflict) throw new Error("esperava conflito");
    });
    const docT3 = await intentRef(db, LOJA, intentT3).get();
    await check("T3 hash original preservado", async () => {
      if (docT3.data()?.stockEffectHash !== hashWin) {
        throw new Error("hash alterado");
      }
    });
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nResumo: passed=${passed} failed=${failed}`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
