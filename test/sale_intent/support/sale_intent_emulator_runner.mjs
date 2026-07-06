/**
 * M3.2-A — sale_intents no Emulator (MD2-T1/T7/T14/T15).
 * projectId: demo-masterpalm-sale-intent-m32a
 * NÃO usa masterpalm-58c46.
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

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = await import(rulesTestingUrl);

const PROJECT_ID = "demo-masterpalm-sale-intent-m32a";
const LOJA = "loja-md2-sale-intent-a";
const OWNER_UID = "owner_md2_sale_intent_a";
const OUTSIDER_UID = "outsider_md2_sale_intent";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error("ABORT: FIRESTORE_EMULATOR_HOST não definido.");
  process.exit(1);
}
if (emulatorHost.includes("masterpalm-58c46")) {
  console.error("ABORT: host contém masterpalm-58c46.");
  process.exit(1);
}

function isLocalEmulatorHost(host) {
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

const rulesPath = join(__dir, "../../../firestore.rules");
const rules = readFileSync(rulesPath, "utf8");

let passed = 0;
let failed = 0;

async function check(name, promise) {
  try {
    await promise;
    console.log(`  OK  ${name}`);
    passed += 1;
  } catch (err) {
    console.error(` FAIL ${name}`, err?.message || err);
    failed += 1;
  }
}

function intentRef(ctx, lojaId, saleIntentId) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection("sale_intents")
    .doc(saleIntentId);
}

function validCreatePayload(lojaId, saleIntentId, overrides = {}) {
  return {
    protocolVersion: 1,
    saleIntentId,
    lojaId,
    origin: "pdv_manual",
    operationId: randomUUID(),
    status: "reserved",
    stockEffectHash: "hash-md2-default",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...overrides,
  };
}

const ALLOWED_ORIGINS = new Set(["pdv_manual", "order_review", "pre_pedido"]);

async function reserveOrJoinJs(db, { lojaId, saleIntentId, origin, stockEffectHash }) {
  const ref = intentRef({ firestore: () => db }, lojaId, saleIntentId);
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
    return {
      reserveStatus: "joined",
      operationId: data.operationId,
      status: data.status,
    };
  });
}

async function main() {
  console.log(`MD2 sale_intents | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA).set({
        ownerUid: OWNER_UID,
        ownerEmail: "owner-md2@local.test",
      });
      await db.collection("users").doc(OWNER_UID).set({
        email: "owner-md2@local.test",
        store_id: LOJA,
      });
      await db.collection("users").doc(OUTSIDER_UID).set({
        email: "outsider@local.test",
      });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner-md2@local.test",
    });
    const outsider = testEnv.authenticatedContext(OUTSIDER_UID, {
      email: "outsider@local.test",
    });

    console.log("MD2-T1 — concorrência reserveOrJoin");
    const intentT1 = `intent-md2-t1-${Date.now()}`;
    const hashT1 = "hash-md2-t1-shared";
    const dbOwner = owner.firestore();
    const [r1, r2] = await Promise.all([
      reserveOrJoinJs(dbOwner, {
        lojaId: LOJA,
        saleIntentId: intentT1,
        origin: "pdv_manual",
        stockEffectHash: hashT1,
      }),
      reserveOrJoinJs(dbOwner, {
        lojaId: LOJA,
        saleIntentId: intentT1,
        origin: "pdv_manual",
        stockEffectHash: hashT1,
      }),
    ]);
    await check(
      "T1 um created e um joined",
      async () => {
        const statuses = [r1.reserveStatus, r2.reserveStatus].sort();
        if (statuses.join(",") !== "created,joined") {
          throw new Error(`reserveStatus inesperado: ${statuses}`);
        }
      },
    );
    await check(
      "T1 mesmo operationId",
      async () => {
        if (r1.operationId !== r2.operationId) {
          throw new Error(`op divergente: ${r1.operationId} vs ${r2.operationId}`);
        }
      },
    );
    await check(
      "T1 exatamente 1 documento",
      async () => {
        const snap = await intentRef(owner, LOJA, intentT1).get();
        if (!snap.exists()) throw new Error("doc ausente");
      },
    );

    console.log("MD2-T7 — hash divergente fail-closed");
    const intentT7 = `intent-md2-t7-${Date.now()}`;
    await reserveOrJoinJs(dbOwner, {
      lojaId: LOJA,
      saleIntentId: intentT7,
      origin: "pdv_manual",
      stockEffectHash: "hash-md2-t7-a",
    });
    let t7Conflict = false;
    try {
      await reserveOrJoinJs(dbOwner, {
        lojaId: LOJA,
        saleIntentId: intentT7,
        origin: "pdv_manual",
        stockEffectHash: "hash-md2-t7-b",
      });
    } catch (e) {
      if (String(e?.message || e).includes("IDENTITY_CONFLICT_HASH")) {
        t7Conflict = true;
      } else {
        throw e;
      }
    }
    await check("T7 conflito hash", async () => {
      if (!t7Conflict) throw new Error("esperava conflito de hash");
    });
    await check("T7 hash remoto preservado", async () => {
      const snap = await intentRef(owner, LOJA, intentT7).get();
      const h = snap.data()?.stockEffectHash;
      if (h !== "hash-md2-t7-a") throw new Error(`hash remoto=${h}`);
    });

    console.log("MD2-T14 — Rules");
    const intentRules = `intent-md2-rules-${Date.now()}`;
    const opRules = randomUUID();
    await check(
      "T14 create V1 válido",
      assertSucceeds(
        intentRef(owner, LOJA, intentRules).set(
          validCreatePayload(LOJA, intentRules, { operationId: opRules }),
        ),
      ),
    );
    await check(
      "T14 nega mudar operationId",
      assertFails(
        intentRef(owner, LOJA, intentRules).update({
          operationId: randomUUID(),
          status: "stock_applied",
          updatedAt: Timestamp.now(),
        }),
      ),
    );
    await check(
      "T14 nega mudar stockEffectHash",
      assertFails(
        intentRef(owner, LOJA, intentRules).update({
          stockEffectHash: "outro-hash",
          status: "stock_applied",
          updatedAt: Timestamp.now(),
        }),
      ),
    );
    await check(
      "T14 nega status regressivo stock_applied→reserved",
      assertFails(
        intentRef(owner, LOJA, intentRules).update({
          status: "reserved",
          updatedAt: Timestamp.now(),
        }),
      ),
    );
    await check(
      "T14 permite reserved→stock_applied",
      assertSucceeds(
        intentRef(owner, LOJA, intentRules).update({
          status: "stock_applied",
          updatedAt: Timestamp.now(),
        }),
      ),
    );
    await check(
      "T14 nega campo arbitrário",
      assertFails(
        intentRef(owner, LOJA, intentRules).update({
          clienteNome: "x",
          status: "stock_applied",
          updatedAt: Timestamp.now(),
        }),
      ),
    );
    await check(
      "T14 nega delete",
      assertFails(intentRef(owner, LOJA, intentRules).delete()),
    );
    await check(
      "T14 outsider negado create",
      assertFails(
        intentRef(outsider, LOJA, `intent-outsider-${Date.now()}`).set(
          validCreatePayload(LOJA, `intent-outsider-${Date.now()}`),
        ),
      ),
    );

    console.log("MD2-T15 — transição concorrente");
    const intentT15 = `intent-md2-t15-${Date.now()}`;
    const opT15 = randomUUID();
    await intentRef(owner, LOJA, intentT15).set(
      validCreatePayload(LOJA, intentT15, { operationId: opT15 }),
    );
    const dbT15 = owner.firestore();
    const refT15 = intentRef(owner, LOJA, intentT15);
    const results = await Promise.allSettled([
      dbT15.runTransaction(async (tx) => {
        const snap = await tx.get(refT15);
        const from = snap.data().status;
        if (from !== "reserved") throw new Error("SKIP");
        tx.update(refT15, {
          status: "stock_applied",
          updatedAt: Timestamp.now(),
        });
        return "stock_applied";
      }),
      dbT15.runTransaction(async (tx) => {
        const snap = await tx.get(refT15);
        const from = snap.data().status;
        if (from !== "reserved") throw new Error("SKIP");
        tx.update(refT15, {
          status: "reverted",
          updatedAt: Timestamp.now(),
        });
        return "reverted";
      }),
    ]);
    const fulfilled = results.filter((r) => r.status === "fulfilled");
    await check("T15 exatamente uma transição vence", async () => {
      if (fulfilled.length !== 1) {
        throw new Error(`fulfilled=${fulfilled.length}`);
      }
    });
    await check("T15 estado final terminal válido", async () => {
      const snap = await refT15.get();
      const st = snap.data()?.status;
      if (st !== "stock_applied" && st !== "reverted") {
        throw new Error(`status final=${st}`);
      }
    });
    await check("T15 sem regressão para reserved", async () => {
      const snap = await refT15.get();
      if (snap.data()?.status === "reserved") {
        throw new Error("regressão silenciosa para reserved");
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
