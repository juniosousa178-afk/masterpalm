/**
 * Fase R1 — Rules V1 estoque_baixa_pagamento (protocolVersion == 1).
 * projectId: demo-masterpalm-pdv-v1-r1
 * NÃO usa masterpalm-58c46. NÃO usa firebase-admin.
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

const PROJECT_ID = "demo-masterpalm-pdv-v1-r1";
const LOJA_A = "loja-demo-pdv-v1-r1-a";
const LOJA_B = "loja-demo-pdv-v1-r1-b";
const OWNER_A_UID = "owner_pdv_v1_r1_a";
const USER_B_UID = "user_pdv_v1_r1_b";
const OUTSIDER_UID = "outsider_pdv_v1_r1";
const LEGACY_MARKER_ID = "legacy-marker-r1-a";
const V1_MARKER_ID = "op-v1-valid-r1-a";
const LEGACY_UPGRADE_ID = "legacy-upgrade-r1-a";
const LEGACY_SCHEMA_ID = "legacy-schema-r1-a";

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
  console.error(`ABORT: host não é local permitido: ${emulatorHost}`);
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

function markerRef(ctx, lojaId, docId) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection("estoque_baixa_pagamento")
    .doc(docId);
}

function validV1Payload(lojaId, operationId, overrides = {}) {
  return {
    protocolVersion: 1,
    origem: "pdv",
    operationId,
    saleId: "sale-sint-r1-a",
    lojaId,
    baixaAplicada: true,
    snapshotHash: "snap-sint-r1-a",
    txItemsHash: "tx-sint-r1-a",
    ...overrides,
  };
}

async function main() {
  console.log(`Rules R1 V1 | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA_A).set({
        ownerUid: OWNER_A_UID,
        ownerEmail: "owner-a@r1.local",
      });
      await db.collection("lojas").doc(LOJA_B).set({
        ownerUid: USER_B_UID,
        ownerEmail: "user-b@r1.local",
      });
      await db.collection("users").doc(OWNER_A_UID).set({
        email: "owner-a@r1.local",
        store_id: LOJA_A,
      });
      await db.collection("users").doc(USER_B_UID).set({
        email: "user-b@r1.local",
        store_id: LOJA_B,
      });
      await db.collection("users").doc(OUTSIDER_UID).set({
        email: "outsider@r1.local",
      });
      await markerRef(context, LOJA_A, LEGACY_MARKER_ID).set({
        lojaId: LOJA_A,
        baixaAplicada: false,
        origem: "catalogo",
      });
      await markerRef(context, LOJA_A, V1_MARKER_ID).set(
        validV1Payload(LOJA_A, V1_MARKER_ID),
      );
      await markerRef(context, LOJA_A, LEGACY_UPGRADE_ID).set({
        lojaId: LOJA_A,
        baixaAplicada: false,
        origem: "catalogo",
      });
      await markerRef(context, LOJA_A, LEGACY_SCHEMA_ID).set({
        lojaId: LOJA_A,
        baixaAplicada: false,
        origem: "catalogo",
      });
    });

    const ownerA = testEnv.authenticatedContext(OWNER_A_UID, {
      email: "owner-a@r1.local",
    });
    const userB = testEnv.authenticatedContext(USER_B_UID, {
      email: "user-b@r1.local",
    });
    const outsider = testEnv.authenticatedContext(OUTSIDER_UID, {
      email: "outsider@r1.local",
    });
    const unauthenticated = testEnv.unauthenticatedContext();

    console.log("A. Compatibilidade legada");
    await check(
      "A1 owner lê marker legado próprio",
      assertSucceeds(markerRef(ownerA, LOJA_A, LEGACY_MARKER_ID).get()),
    );
    await check(
      "A2 owner cria marker legado válido",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, "legacy-create-r1-a").set({
          lojaId: LOJA_A,
          baixaAplicada: false,
          origem: "catalogo",
        }),
      ),
    );
    await check(
      "A3 owner atualiza marker legado (baixaAplicada)",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, LEGACY_MARKER_ID).update({
          baixaAplicada: true,
          estornoAplicado: false,
        }),
      ),
    );
    await check(
      "A4 user loja B negado leitura loja A",
      assertFails(markerRef(userB, LOJA_A, LEGACY_MARKER_ID).get()),
    );
    await check(
      "A5 user loja B negado escrita loja A",
      assertFails(
        markerRef(userB, LOJA_A, "legacy-forbidden-r1").set({
          lojaId: LOJA_A,
          baixaAplicada: true,
        }),
      ),
    );
    await check(
      "A6 outsider negado leitura loja A",
      assertFails(markerRef(outsider, LOJA_A, LEGACY_MARKER_ID).get()),
    );
    await check(
      "A7 outsider negado escrita loja A",
      assertFails(
        markerRef(outsider, LOJA_A, "legacy-outsider-r1").set({
          lojaId: LOJA_A,
          baixaAplicada: true,
        }),
      ),
    );

    console.log("B. Criação V1 válida");
    const v1CreateId = "op-v1-create-r1-a";
    await check(
      "B6 owner cria marker V1 válido",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, v1CreateId).set(
          validV1Payload(LOJA_A, v1CreateId),
        ),
      ),
    );

    console.log("C. Criação V1 inválida");
    await check(
      "C7 protocolVersion ausente (ramo legado)",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, "legacy-not-v1-r1").set({
          lojaId: LOJA_A,
          baixaAplicada: false,
          origem: "catalogo",
        }),
      ),
    );
    await check(
      "C8 protocolVersion diferente de 1",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-v2-r1").set({
          protocolVersion: 2,
          origem: "pdv",
          operationId: "op-v2-r1",
          saleId: "sale-r1",
          lojaId: LOJA_A,
          baixaAplicada: true,
          snapshotHash: "snap-r1",
          txItemsHash: "tx-r1",
        }),
      ),
    );
    await check(
      "C9 origem diferente de pdv",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-bad-orig-r1").set(
          validV1Payload(LOJA_A, "op-bad-orig-r1", { origem: "catalogo" }),
        ),
      ),
    );
    await check(
      "C10 operationId diferente do markerId",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-id-mismatch-r1").set(
          validV1Payload(LOJA_A, "op-other-r1"),
        ),
      ),
    );
    await check(
      "C11 lojaId diferente do path",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-loja-mismatch-r1").set(
          validV1Payload(LOJA_B, "op-loja-mismatch-r1"),
        ),
      ),
    );
    await check(
      "C12 baixaAplicada false",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-baixa-false-r1").set(
          validV1Payload(LOJA_A, "op-baixa-false-r1", { baixaAplicada: false }),
        ),
      ),
    );
    await check(
      "C13 baixaAplicada ausente",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-baixa-missing-r1").set({
          protocolVersion: 1,
          origem: "pdv",
          operationId: "op-baixa-missing-r1",
          saleId: "sale-r1",
          lojaId: LOJA_A,
          snapshotHash: "snap-r1",
          txItemsHash: "tx-r1",
        }),
      ),
    );
    await check(
      "C14 snapshotHash vazio",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-snap-empty-r1").set(
          validV1Payload(LOJA_A, "op-snap-empty-r1", { snapshotHash: "" }),
        ),
      ),
    );
    await check(
      "C15 txItemsHash vazio",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-tx-empty-r1").set(
          validV1Payload(LOJA_A, "op-tx-empty-r1", { txItemsHash: "" }),
        ),
      ),
    );
    await check(
      "C16 saleId vazio",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-sale-empty-r1").set(
          validV1Payload(LOJA_A, "op-sale-empty-r1", { saleId: "" }),
        ),
      ),
    );
    await check(
      "C17 campo obrigatório ausente (saleId)",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-missing-sale-r1").set({
          protocolVersion: 1,
          origem: "pdv",
          operationId: "op-missing-sale-r1",
          lojaId: LOJA_A,
          baixaAplicada: true,
          snapshotHash: "snap-r1",
          txItemsHash: "tx-r1",
        }),
      ),
    );
    await check(
      "C18 campo extra arbitrário",
      assertFails(
        markerRef(ownerA, LOJA_A, "op-extra-field-r1").set({
          ...validV1Payload(LOJA_A, "op-extra-field-r1"),
          nota: "extra",
        }),
      ),
    );
    await check(
      "C19 user loja B cria V1 na loja A",
      assertFails(
        markerRef(userB, LOJA_A, "op-cross-store-r1").set(
          validV1Payload(LOJA_A, "op-cross-store-r1"),
        ),
      ),
    );
    await check(
      "C20 outsider cria V1",
      assertFails(
        markerRef(outsider, LOJA_A, "op-outsider-v1-r1").set(
          validV1Payload(LOJA_A, "op-outsider-v1-r1"),
        ),
      ),
    );

    console.log("D. Imutabilidade V1");
    await check(
      "D21 owner atualiza snapshotHash V1",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({
          snapshotHash: "snap-altered-r1",
        }),
      ),
    );
    await check(
      "D22 owner atualiza saleId V1",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({
          saleId: "sale-altered-r1",
        }),
      ),
    );
    await check(
      "D23 owner altera baixaAplicada true→false",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({
          baixaAplicada: false,
        }),
      ),
    );
    await check(
      "D24 owner altera origem",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({ origem: "catalogo" }),
      ),
    );
    await check(
      "D25 owner altera protocolVersion",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({ protocolVersion: 2 }),
      ),
    );
    await check(
      "D26 owner remove protocolVersion (downgrade)",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({
          protocolVersion: null,
        }),
      ),
    );
    await check(
      "D27 owner adiciona campo extra",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({ nota: "extra" }),
      ),
    );
    await check(
      "D28 owner update idêntico",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update(
          validV1Payload(LOJA_A, V1_MARKER_ID),
        ),
      ),
    );
    await check(
      "D29 owner apaga marker V1",
      assertFails(markerRef(ownerA, LOJA_A, V1_MARKER_ID).delete()),
    );

    console.log("E. Transições proibidas");
    await check(
      "E30 legacy recebe protocolVersion 1",
      assertFails(
        markerRef(ownerA, LOJA_A, LEGACY_UPGRADE_ID).update({
          protocolVersion: 1,
        }),
      ),
    );
    await check(
      "E31 legacy recebe schema V1 inteiro",
      assertFails(
        markerRef(ownerA, LOJA_A, LEGACY_SCHEMA_ID).update(
          validV1Payload(LOJA_A, LEGACY_SCHEMA_ID),
        ),
      ),
    );
    await check(
      "E32 V1 recebe update para schema legado",
      assertFails(
        markerRef(ownerA, LOJA_A, V1_MARKER_ID).update({
          lojaId: LOJA_A,
          baixaAplicada: false,
          origem: "catalogo",
        }),
      ),
    );

    console.log("F. Separação de escopo");
    const v1ScopeId = "op-v1-scope-a-r1";
    await check(
      "F33 user loja A cria V1 válido em loja A",
      assertSucceeds(
        markerRef(ownerA, LOJA_A, v1ScopeId).set(
          validV1Payload(LOJA_A, v1ScopeId),
        ),
      ),
    );
    await check(
      "F34 mesmo user cria V1 em loja B",
      assertFails(
        markerRef(ownerA, LOJA_B, "op-v1-scope-b-r1").set(
          validV1Payload(LOJA_B, "op-v1-scope-b-r1"),
        ),
      ),
    );
    await check(
      "F35 user loja B altera V1 da loja A",
      assertFails(
        markerRef(userB, LOJA_A, V1_MARKER_ID).update({
          snapshotHash: "snap-hijack-r1",
        }),
      ),
    );
    await check(
      "F36 sem login cria V1",
      assertFails(
        markerRef(unauthenticated, LOJA_A, "op-unauth-v1-r1").set(
          validV1Payload(LOJA_A, "op-unauth-v1-r1"),
        ),
      ),
    );
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nResultado R1: ${passed} OK, ${failed} FAIL`);
  console.log(
    "Limitação L2: Rules V1 endurecem apenas markers protocolVersion==1; " +
      "cliente malicioso pode continuar usando marker legado se ramo legado permitir.",
  );
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
