/**
 * M3.2-C — order review + Sale Intent no Emulator (OR-EM-1/2/3).
 * projectId: demo-masterpalm-sale-intent-m32c
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

const PROJECT_ID = "demo-masterpalm-sale-intent-m32c";
const LOJA = "loja-md2c-order-review";
const OWNER_UID = "owner_md2c_or";
const ORIGIN = "order_review";
const HASH_SHARED = "hash-or-em-shared";

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

function saleIntentIdForOrder(orderId) {
  return `order_review:${orderId}`;
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
  console.log(`MD2-C order_review | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA).set({
        ownerUid: OWNER_UID,
        ownerEmail: "owner-md2c@local.test",
      });
      await db.collection("users").doc(OWNER_UID).set({
        email: "owner-md2c@local.test",
        store_id: LOJA,
      });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner-md2c@local.test",
    });
    const db = owner.firestore();

    console.log("OR-EM-1 — dois writers mesmo saleIntentId order_review");
    const orderEm1 = `order-em-1-${Date.now()}`;
    const intentEm1 = saleIntentIdForOrder(orderEm1);
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
    await check("OR-EM-1 mesmo operationId", async () => {
      if (w1.operationId !== w2.operationId) {
        throw new Error(`ops distintos: ${w1.operationId} vs ${w2.operationId}`);
      }
    });
    await check("OR-EM-1 origin order_review", async () => {
      const snap = await intentRef(db, LOJA, intentEm1).get();
      if (snap.data()?.origin !== ORIGIN) {
        throw new Error(`origin=${snap.data()?.origin}`);
      }
    });

    console.log("OR-EM-2 — hash divergente fail-closed");
    const orderEm2 = `order-em-2-${Date.now()}`;
    const intentEm2 = saleIntentIdForOrder(orderEm2);
    await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: intentEm2,
      origin: ORIGIN,
      stockEffectHash: "hash-or-em-2a",
    });
    let em2Conflict = false;
    try {
      await reserveOrJoinJs(db, {
        lojaId: LOJA,
        saleIntentId: intentEm2,
        origin: ORIGIN,
        stockEffectHash: "hash-or-em-2b",
      });
    } catch (e) {
      if (String(e?.message || e).includes("IDENTITY_CONFLICT_HASH")) {
        em2Conflict = true;
      } else {
        throw e;
      }
    }
    await check("OR-EM-2 conflito hash", async () => {
      if (!em2Conflict) throw new Error("esperava conflito");
    });

    console.log("OR-EM-3 — orderIds diferentes → operationIds distintos");
    const orderA = `order-em-3a-${Date.now()}`;
    const orderB = `order-em-3b-${Date.now()}`;
    const rA = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: saleIntentIdForOrder(orderA),
      origin: ORIGIN,
      stockEffectHash: HASH_SHARED,
    });
    const rB = await reserveOrJoinJs(db, {
      lojaId: LOJA,
      saleIntentId: saleIntentIdForOrder(orderB),
      origin: ORIGIN,
      stockEffectHash: HASH_SHARED,
    });
    await check("OR-EM-3 operationIds distintos", async () => {
      if (rA.operationId === rB.operationId) {
        throw new Error("operationIds colapsados");
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
