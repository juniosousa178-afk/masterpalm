/**
 * Prova Firestore Rules — fretes_secrets e bloqueio de token em config/fretes.
 * Exige FIRESTORE_EMULATOR_HOST (firebase emulators:exec define automaticamente).
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
  console.error(
    "FIRESTORE_EMULATOR_HOST não definido — abortando para evitar conexão com produção.",
  );
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const projectId = "masterpalm-superfrete-local";

const rulesPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../firestore.rules",
);
const rules = readFileSync(rulesPath, "utf8");

const OWNER_A = "owner_loja_a";
const OWNER_B = "owner_loja_b";
const LOJA_A = "loja-a-sf";
const LOJA_B = "loja-b-sf";

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

function secretsRef(ctx, lojaId) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection("config")
    .doc("fretes_secrets");
}

function fretesRef(ctx, lojaId) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection("config")
    .doc("fretes");
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("users").doc(OWNER_A).set({
        email: "a@test.com",
        store_id: LOJA_A,
      });
      await db.collection("users").doc(OWNER_B).set({
        email: "b@test.com",
        store_id: LOJA_B,
      });
      await db.collection("lojas").doc(LOJA_A).set({
        published: true,
        ownerUid: OWNER_A,
      });
      await db.collection("lojas").doc(LOJA_B).set({
        published: true,
        ownerUid: OWNER_B,
      });
      await fretesRef(context, LOJA_A).set({
        cepOrigem: "01310100",
        integrations: { superfrete: { configured: true, enabled: true } },
      });
      await secretsRef(context, LOJA_A).set({
        superfrete: { token: "secret_backend_only" },
      });
    });

    const ownerA = testEnv.authenticatedContext(OWNER_A, { email: "a@test.com" });
    const ownerB = testEnv.authenticatedContext(OWNER_B, { email: "b@test.com" });
    const anon = testEnv.unauthenticatedContext();

    console.log("fretes_secrets — acesso direto bloqueado");
    await check(
      "1. dono/admin não lê fretes_secrets",
      assertFails(secretsRef(ownerA, LOJA_A).get()),
    );
    await check(
      "2. dono/admin não escreve fretes_secrets",
      assertFails(
        secretsRef(ownerA, LOJA_A).set({ superfrete: { token: "x" } }),
      ),
    );
    await check(
      "3. anônimo não lê fretes_secrets",
      assertFails(secretsRef(anon, LOJA_A).get()),
    );
    await check(
      "4. loja A não lê fretes_secrets da loja B",
      assertFails(secretsRef(ownerA, LOJA_B).get()),
    );

    console.log("config/fretes — público sem token");
    await check(
      "5. documento público fretes não permite token (create)",
      assertFails(
        fretesRef(ownerA, LOJA_A).set({
          superfrete: { token: "novo_token_proibido" },
        }),
      ),
    );
    await check(
      "6. configuração pública sem token continua legível",
      assertSucceeds(fretesRef(anon, LOJA_A).get()),
    );
    await check(
      "7. configuração pública não permite campos legados de token (update)",
      assertFails(
        fretesRef(ownerA, LOJA_A).update({ superfrete_token: "legado" }),
      ),
    );
    await check(
      "8. escrita pública segura permitida",
      assertSucceeds(
        fretesRef(ownerA, LOJA_A).set(
          {
            cepOrigem: "01310100",
            integrations: {
              superfrete: { configured: true, enabled: true, sandbox: false },
            },
          },
          { merge: true },
        ),
      ),
    );
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nRules emulator SuperFrete: ${passed} passou, ${failed} falhou`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
