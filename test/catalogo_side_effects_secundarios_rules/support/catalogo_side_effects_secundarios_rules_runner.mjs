/**
 * M3.7.1 — RULESEC catalogo_side_effects_secundarios (Firebase Rules Unit Testing).
 * projectId: demo-masterpalm-cat-side-rules
 */
import { readFileSync } from "node:fs";
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

const PROJECT_ID = "demo-masterpalm-cat-side-rules";
const LOJA_A = "loja-cat-side-rules-a";
const LOJA_B = "loja-cat-side-rules-b";
const OWNER_A_UID = "owner_cat_side_rules_a";
const USER_B_UID = "user_cat_side_rules_b";
const OUTSIDER_UID = "outsider_cat_side_rules";
const VENDA_EXISTING = "venda-side-existing";
const VENDA_CREATE = "venda-side-create";
const VENDA_INCREMENTAL = "venda-side-incremental";
const VENDA_MONOTONIC = "venda-side-monotonic";
const VENDA_IDEMPOTENT = "venda-side-idempotent";
const VENDA_REAL = "venda-side-real";

const COL = "catalogo_side_effects_secundarios";

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
let skipped = 0;

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

function skip(name, reason) {
  console.log(` SKIP ${name} — ${reason}`);
  skipped += 1;
}

function markerRef(ctx, lojaId, vendaId) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection(COL)
    .doc(vendaId);
}

function ts() {
  return Timestamp.now();
}

function payloadDenorm() {
  return { denormAplicado: true, updatedAt: ts() };
}

function payloadNotificacao() {
  return { notificacaoAdminEnviada: true, updatedAt: ts() };
}

function payloadCupom() {
  return { cupomSalvo: true, updatedAt: ts() };
}

function payloadCampanha() {
  return { campanhaRegistrada: true, updatedAt: ts() };
}

async function main() {
  console.log(`RULESEC catalogo_side_effects | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA_A).set({
        ownerUid: OWNER_A_UID,
        ownerEmail: "owner-a@cat-side.local",
      });
      await db.collection("lojas").doc(LOJA_B).set({
        ownerUid: USER_B_UID,
        ownerEmail: "user-b@cat-side.local",
      });
      await db.collection("users").doc(OWNER_A_UID).set({
        email: "owner-a@cat-side.local",
        store_id: LOJA_A,
      });
      await db.collection("users").doc(USER_B_UID).set({
        email: "user-b@cat-side.local",
        store_id: LOJA_B,
      });
      await db.collection("users").doc(OUTSIDER_UID).set({
        email: "outsider@cat-side.local",
      });
      await markerRef(context, LOJA_A, VENDA_EXISTING).set({
        denormAplicado: true,
        updatedAt: ts(),
      });
      await markerRef(context, LOJA_A, VENDA_INCREMENTAL).set({
        denormAplicado: true,
        updatedAt: ts(),
      });
      await markerRef(context, LOJA_A, VENDA_MONOTONIC).set({
        denormAplicado: true,
        updatedAt: ts(),
      });
      await markerRef(context, LOJA_A, VENDA_IDEMPOTENT).set({
        notificacaoAdminEnviada: true,
        updatedAt: ts(),
      });
    });

    const ownerA = testEnv.authenticatedContext(OWNER_A_UID, {
      email: "owner-a@cat-side.local",
    });
    const userB = testEnv.authenticatedContext(USER_B_UID, {
      email: "user-b@cat-side.local",
    });
    const outsider = testEnv.authenticatedContext(OUTSIDER_UID, {
      email: "outsider@cat-side.local",
    });

    await check(
      "RULESEC-1 member da loja READ marker existente",
      assertSucceeds(markerRef(ownerA, LOJA_A, VENDA_EXISTING).get()),
    );

    await check(
      "RULESEC-2 member da loja CREATE marker válido",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, VENDA_CREATE).set(payloadDenorm(), { merge: true }),
      ),
    );

    await check(
      "RULESEC-3 member da loja UPDATE marker válido",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, VENDA_INCREMENTAL).set(payloadNotificacao(), {
          merge: true,
        }),
      ),
    );

    await check(
      "RULESEC-4 outra loja negado READ",
      assertFails(markerRef(userB, LOJA_A, VENDA_EXISTING).get()),
    );

    await check(
      "RULESEC-5 outra loja negado CREATE",
      assertFails(
        markerRef(userB, LOJA_A, "venda-cross-create").set(payloadDenorm(), { merge: true }),
      ),
    );

    await check(
      "RULESEC-6 outra loja negado UPDATE",
      assertFails(
        markerRef(userB, LOJA_A, VENDA_EXISTING).set(payloadNotificacao(), { merge: true }),
      ),
    );

    await check(
      "RULESEC-7 campo arbitrário negado",
      assertFails(
        markerRef(ownerA, LOJA_A, "venda-extra-field").set(
          { denormAplicado: true, updatedAt: ts(), nota: "extra" },
          { merge: true },
        ),
      ),
    );

    skip(
      "RULESEC-8 identity field imutável",
      "N/A — doc não grava lojaId/vendaId; identidade é o path",
    );

    await check(
      "RULESEC-9 delete negado",
      assertFails(markerRef(ownerA, LOJA_A, VENDA_EXISTING).delete()),
    );

    await check(
      "RULESEC-10 payload real denorm (service)",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, `${VENDA_REAL}-denorm`).set(payloadDenorm(), { merge: true }),
      ),
    );
    await check(
      "RULESEC-10 payload real notificacao (service)",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, `${VENDA_REAL}-notif`).set(payloadNotificacao(), {
          merge: true,
        }),
      ),
    );
    await check(
      "RULESEC-10 payload real cupom (service)",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, `${VENDA_REAL}-cupom`).set(payloadCupom(), { merge: true }),
      ),
    );
    await check(
      "RULESEC-10 payload real campanha (service)",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, `${VENDA_REAL}-camp`).set(payloadCampanha(), { merge: true }),
      ),
    );

    await check(
      "RULESEC-11 retry incremental aceito",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, VENDA_INCREMENTAL).set(payloadCupom(), { merge: true }),
      ),
    );

    await check(
      "RULESEC-12 marker true→false negado",
      assertFails(
        markerRef(ownerA, LOJA_A, VENDA_MONOTONIC).set(
          { denormAplicado: false, updatedAt: ts() },
          { merge: true },
        ),
      ),
    );

    await check(
      "RULESEC-13 marker true→true idempotente",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, VENDA_IDEMPOTENT).set(payloadNotificacao(), {
          merge: true,
        }),
      ),
    );

    await check(
      "RULESEC-14 tipo inválido negado",
      assertFails(
        markerRef(ownerA, LOJA_A, "venda-bad-type").set(
          { denormAplicado: "true", updatedAt: ts() },
          { merge: true },
        ),
      ),
    );

    await check(
      "RULESEC-15 updatedAt obrigatório (timestamp)",
      assertFails(
        markerRef(ownerA, LOJA_A, "venda-no-ts").set({ denormAplicado: true }, { merge: true }),
      ),
    );

    await check(
      "RULESEC-extra outsider negado READ",
      assertFails(markerRef(outsider, LOJA_A, VENDA_EXISTING).get()),
    );
  } finally {
    await testEnv.cleanup();
  }

  const total = passed + failed;
  console.log(`\nRULESEC: ${passed}/${total} OK, ${failed} FAIL, ${skipped} SKIP`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
