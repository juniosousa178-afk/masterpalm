/**
 * R8.4 — readback real de FieldValue.serverTimestamp no Emulator.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  initializeTestEnvironment,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import { serverTimestamp } from "firebase/firestore";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error("FIRESTORE_EMULATOR_HOST não definido — abortando.");
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const projectId = "masterpalm-stock-readback-r84";

const rulesPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../firestore.rules",
);
const rules = readFileSync(rulesPath, "utf8");

const OWNER_UID = "owner_readback_r84";
const LOJA_ID = "loja_readback_r84";
const PROD_ID = "prod_readback_r84";

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
        nome: "Loja readback",
      });
      await db
        .collection("lojas")
        .doc(LOJA_ID)
        .collection("estoque_produtos")
        .doc(PROD_ID)
        .set({
          nome: "Prod",
          quantidade: 10,
          variacoes: {},
          stockRevision: 1,
          stockOperationId: "op-init",
        });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner@test.com",
    });
    const ref = owner
      .firestore()
      .collection("lojas")
      .doc(LOJA_ID)
      .collection("estoque_produtos")
      .doc(PROD_ID);

    await assertSucceeds(
      ref.update({
        quantidade: 9,
        stockRevision: 2,
        stockOperationId: "op-readback",
        stockUpdatedAt: serverTimestamp(),
      }),
    );

    const snap = await ref.get();
    const data = snap.data();
    const ts = data?.stockUpdatedAt;

    if (ts == null) {
      throw new Error("stockUpdatedAt ausente após write");
    }
    if (typeof ts.toMillis !== "function") {
      throw new Error(
        "stockUpdatedAt não resolvido (placeholder intermediário permaneceu)",
      );
    }
    if (data.stockRevision !== 2) {
      throw new Error(`stockRevision esperado 2, obteve ${data.stockRevision}`);
    }
    if (data.stockOperationId !== "op-readback") {
      throw new Error("stockOperationId não confirmado no readback");
    }

    console.log("SERVER_TIMESTAMP_READBACK_VALIDATED");
    console.log(
      `readback stockUpdatedAt=${ts.toDate().toISOString()} revision=${data.stockRevision}`,
    );
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
