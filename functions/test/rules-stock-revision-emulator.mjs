/**
 * R8.4 ÔÇö Firestore Rules stockRevision enforcement (E1ÔÇôE8).
 * Exige FIRESTORE_EMULATOR_HOST (firebase emulators:exec).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error("FIRESTORE_EMULATOR_HOST n├úo definido ÔÇö abortando.");
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const projectId = "masterpalm-stock-r84-local";

const rulesPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../firestore.rules",
);
const rules = readFileSync(rulesPath, "utf8");

const OWNER_UID = "owner_stock_r84";
const LOJA_ID = "loja_stock_r84";
const PROD_ID = "prod_stock_r84";

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

function estoqueRef(ctx) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(LOJA_ID)
    .collection("estoque_produtos")
    .doc(PROD_ID);
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA_ID).set({
        ownerUid: OWNER_UID,
        nome: "Loja teste R84",
      });
      await db
        .collection("lojas")
        .doc(LOJA_ID)
        .collection("estoque_produtos")
        .doc(PROD_ID)
        .set({
          nome: "Prod base",
          quantidade: 10,
          variacoes: {},
          stockRevision: 8,
          stockOperationId: "op-base",
        });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner@test.com",
    });

    console.log("E1 ÔÇö cliente novo v├ílido (8ÔåÆ9)");
    await check(
      "E1 valid revision increment",
      assertSucceeds(
        estoqueRef(owner).update({
          quantidade: 9,
          stockRevision: 9,
          stockOperationId: "op-e1",
        }),
      ),
    );

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("lojas")
        .doc(LOJA_ID)
        .collection("estoque_produtos")
        .doc(PROD_ID)
        .set({
          nome: "Prod base",
          quantidade: 10,
          variacoes: {},
          stockRevision: 8,
          stockOperationId: "op-base",
        });
    });

    console.log("E2 ÔÇö cliente antigo sem revision");
    await check(
      "E2 legacy grade change rejected",
      assertFails(
        estoqueRef(owner).update({
          quantidade: 5,
        }),
      ),
    );

    console.log("E3 ÔÇö mesma revision grade diferente");
    await check(
      "E3 same revision different grade",
      assertFails(
        estoqueRef(owner).update({
          quantidade: 5,
          stockRevision: 8,
          stockOperationId: "op-e3",
        }),
      ),
    );

    console.log("E4 ÔÇö revision regressiva");
    await check(
      "E4 revision regression",
      assertFails(
        estoqueRef(owner).update({
          quantidade: 5,
          stockRevision: 7,
          stockOperationId: "op-e4",
        }),
      ),
    );

    console.log("E5 ÔÇö salto de revision");
    await check(
      "E5 revision jump",
      assertFails(
        estoqueRef(owner).update({
          quantidade: 5,
          stockRevision: 10,
          stockOperationId: "op-e5",
        }),
      ),
    );

    console.log("E6 ÔÇö retry mesma operationId");
    await check(
      "E6 first apply",
      assertSucceeds(
        estoqueRef(owner).update({
          quantidade: 9,
          stockRevision: 9,
          stockOperationId: "op-e6",
        }),
      ),
    );
    await check(
      "E6 idempotent retry",
      assertSucceeds(
        estoqueRef(owner).update({
          quantidade: 9,
          stockRevision: 9,
          stockOperationId: "op-e6",
        }),
      ),
    );

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("lojas")
        .doc(LOJA_ID)
        .collection("estoque_produtos")
        .doc(PROD_ID)
        .set({
          nome: "Prod base",
          quantidade: 10,
          variacoes: {},
          stockRevision: 8,
          stockOperationId: "op-base",
        });
    });

    console.log("E7 ÔÇö edi├º├úo nome sem estoque");
    await check(
      "E7 metadata-only",
      assertSucceeds(
        estoqueRef(owner).update({
          nome: "Prod renomeado",
        }),
      ),
    );

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection("lojas")
        .doc(LOJA_ID)
        .collection("estoque_produtos")
        .doc(PROD_ID)
        .set({
          nome: "Prod atual",
          quantidade: 5,
          variacoes: {},
          stockRevision: 9,
          stockOperationId: "op-remote",
        });
    });

    console.log("E8 ÔÇö documento stale revision 7 sobre 9");
    await check(
      "E8 stale full overwrite",
      assertFails(
        estoqueRef(owner).set({
          nome: "Prod stale",
          quantidade: 10,
          variacoes: {},
          stockRevision: 7,
          stockOperationId: "op-stale",
        }),
      ),
    );

    console.log(`\nSTOCK_REVISION_RULES: passed=${passed} failed=${failed}`);
    if (failed === 0) {
      console.log("STOCK_REVISION_SERVER_ENFORCEMENT_VALIDATED");
    } else {
      console.log("STOCK_REVISION_CLIENT_ONLY_UNSAFE");
      process.exit(1);
    }
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
