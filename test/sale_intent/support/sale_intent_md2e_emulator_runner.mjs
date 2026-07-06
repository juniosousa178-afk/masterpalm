/**
 * M3.3 — admin pre_pedidos + Sale Intent no Emulator (ADMIN-EM-1..5).
 * projectId: demo-masterpalm-sale-intent-m33
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

const PROJECT_ID = "demo-masterpalm-sale-intent-m33";
const LOJA = "loja-md2e-admin-pre-pedido";
const OWNER_UID = "owner_md2e_admin";
const ORIGIN = "pre_pedido";
const HASH_SHARED = "hash-pp-em-shared";

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

function saleIntentIdForPedido(pedidoId) {
  return `pre_pedido:${pedidoId}`;
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
    if (data.status === "critical") {
      throw new Error("CRITICAL_STATE");
    }
    if (data.status === "reverted") {
      transaction.update(ref, {
        status: "reserved",
        updatedAt: Timestamp.now(),
      });
      return {
        reserveStatus: "joined",
        operationId: data.operationId,
        status: "reserved",
      };
    }
    return {
      reserveStatus: "joined",
      operationId: data.operationId,
      status: data.status,
    };
  });
}

async function main() {
  console.log(`MD2-E admin pre_pedido | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA).set({
        ownerUid: OWNER_UID,
        ownerEmail: "owner-md2d@local.test",
      });
      await db.collection("users").doc(OWNER_UID).set({
        email: "owner-md2d@local.test",
        store_id: LOJA,
      });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner-md2d@local.test",
    });
    const db = owner.firestore();

    console.log("ADMIN-EM-1 — mesmo pedido → mesmo operationId");
    const pedidoEm1 = `pedido-em-1-${Date.now()}`;
    const intentEm1 = saleIntentIdForPedido(pedidoEm1);
    const [w1, w2] = await Promise.all([
      reserveOrJoinJs(db, {
        lojaId: LOJA,
        saleIntentId: intentEm1,
        origin: ORIGIN,
        stockEffectHash: HASH_SHARED,
      }),
      reserveOrJoinJs(db, {
        lojaId: LOJA,
        saleIntentId: intentEm1,
        origin: ORIGIN,
        stockEffectHash: HASH_SHARED,
      }),
    ]);
    await check("ADMIN-EM-1 mesmo operationId", async () => {
      if (w1.operationId !== w2.operationId) {
        throw new Error(`ops distintos: ${w1.operationId} vs ${w2.operationId}`);
      }
    });
    await check("ADMIN-EM-1 origin pre_pedido", async () => {
      const snap = await intentRef(db, LOJA, intentEm1).get();
      if (snap.data()?.origin !== ORIGIN) {
        throw new Error(`origin=${snap.data()?.origin}`);
      }
    });

    console.log("ADMIN-EM-2 — hash divergente fail-closed");
    const pedidoEm2 = `pedido-em-2-${Date.now()}`;
    const intentEm2 = saleIntentIdForPedido(pedidoEm2);
    await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: intentEm2,
      origin: ORIGIN,
      stockEffectHash: "hash-pp-em-2a",
    });
    let em2Conflict = false;
    try {
      await reserveOrJoinJs(db, {
        lojaId: LOJA,
        saleIntentId: intentEm2,
        origin: ORIGIN,
        stockEffectHash: "hash-pp-em-2b",
      });
    } catch (e) {
      if (String(e?.message || e).includes("IDENTITY_CONFLICT_HASH")) {
        em2Conflict = true;
      } else {
        throw e;
      }
    }
    await check("ADMIN-EM-2 conflito hash", async () => {
      if (!em2Conflict) throw new Error("esperava conflito");
    });

    console.log("ADMIN-EM-3 — pedidos diferentes → operationIds distintos");
    const pedidoA = `pedido-em-3a-${Date.now()}`;
    const pedidoB = `pedido-em-3b-${Date.now()}`;
    const rA = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: saleIntentIdForPedido(pedidoA),
      origin: ORIGIN,
      stockEffectHash: HASH_SHARED,
    });
    const rB = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: saleIntentIdForPedido(pedidoB),
      origin: ORIGIN,
      stockEffectHash: HASH_SHARED,
    });
    await check("ADMIN-EM-3 operationIds distintos", async () => {
      if (rA.operationId === rB.operationId) {
        throw new Error("operationIds colapsados");
      }
    });

    console.log("ADMIN-EM-4 — retry reverted → reserved join");
    const pedidoEm4 = `pedido-em-4-${Date.now()}`;
    const intentEm4 = saleIntentIdForPedido(pedidoEm4);
    const opEm4 = randomUUID();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      const ref = intentRef(adminDb, LOJA, intentEm4);
      await ref.set({
        protocolVersion: 1,
        saleIntentId: intentEm4,
        lojaId: LOJA,
        origin: ORIGIN,
        operationId: opEm4,
        status: "reserved",
        stockEffectHash: HASH_SHARED,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
      await ref.update({
        status: "reverted",
        updatedAt: Timestamp.now(),
      });
    });
    const joinRev = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: intentEm4,
      origin: ORIGIN,
      stockEffectHash: HASH_SHARED,
    });
    await check("ADMIN-EM-4 reverted→reserved join", async () => {
      if (joinRev.status !== "reserved") {
        throw new Error(`status=${joinRev.status}`);
      }
      if (joinRev.operationId !== opEm4) {
        throw new Error("operationId mudou no retry reverted");
      }
    });

    console.log("ADMIN-EM-5 — completed join preserva operationId");
    const pedidoEm5 = `pedido-em-5-${Date.now()}`;
    const intentEm5 = saleIntentIdForPedido(pedidoEm5);
    const opEm5 = randomUUID();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      const ref = intentRef(adminDb, LOJA, intentEm5);
      await ref.set({
        protocolVersion: 1,
        saleIntentId: intentEm5,
        lojaId: LOJA,
        origin: ORIGIN,
        operationId: opEm5,
        status: "reserved",
        stockEffectHash: HASH_SHARED,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
      await ref.update({
        status: "stock_applied",
        updatedAt: Timestamp.now(),
      });
      await ref.update({
        status: "sale_persisted",
        updatedAt: Timestamp.now(),
      });
      await ref.update({
        status: "completed",
        completedAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
    });
    const joinDone = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: intentEm5,
      origin: ORIGIN,
      stockEffectHash: HASH_SHARED,
    });
    await check("ADMIN-EM-5 completed join", async () => {
      if (joinDone.status !== "completed") {
        throw new Error(`status=${joinDone.status}`);
      }
      if (joinDone.operationId !== opEm5) {
        throw new Error("operationId mudou no join completed");
      }
    });

    console.log(`\nResumo: passed=${passed} failed=${failed}`);
    if (failed > 0) process.exit(1);
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
