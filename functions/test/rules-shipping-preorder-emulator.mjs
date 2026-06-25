/**
 * Prova Firestore Rules — shipping_preorders e bloqueio token Melhor Envio.
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
  console.error("FIRESTORE_EMULATOR_HOST não definido.");
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const projectId = "masterpalm-shipping-preorder-local";

const rulesPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../firestore.rules",
);
const rules = readFileSync(rulesPath, "utf8");

const OWNER_A = "owner_loja_a";
const OWNER_B = "owner_loja_b";
const SELLER_A = "seller_loja_a";
const LOJA_A = "loja-a-ship";
const LOJA_B = "loja-b-ship";

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

function shippingRef(ctx, lojaId, docId) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection("shipping_preorders")
    .doc(docId);
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
        email: "owner-a@test.com",
        store_id: LOJA_A,
      });
      await db.collection("users").doc(OWNER_B).set({
        email: "owner-b@test.com",
        store_id: LOJA_B,
      });
      await db.collection("users").doc(SELLER_A).set({
        email: "seller-a@test.com",
        store_id: LOJA_A,
      });
      await db.collection("lojas").doc(LOJA_A).set({
        published: true,
        ownerUid: OWNER_A,
      });
      await db.collection("lojas").doc(LOJA_B).set({
        published: true,
        ownerUid: OWNER_B,
      });
      await db.collection("lojas").doc(LOJA_A).collection("vendedores").doc(SELLER_A).set({
        ativo: true,
        email: "seller-a@test.com",
        permissoes: { vendas: true },
      });
      await shippingRef(context, LOJA_A, "melhor_envio_ped-1").set({
        status: "created",
        provider: "melhor_envio",
      });
      await secretsRef(context, LOJA_A).set({
        melhor_envio: { token: "secret" },
      });
    });

    const ownerA = testEnv.authenticatedContext(OWNER_A, { email: "owner-a@test.com" });
    const ownerB = testEnv.authenticatedContext(OWNER_B, { email: "owner-b@test.com" });
    const sellerA = testEnv.authenticatedContext(SELLER_A, { email: "seller-a@test.com" });
    const anon = testEnv.unauthenticatedContext();

    console.log("shipping_preorders");
    await check(
      "1. admin/dono lê shipping_preorders da própria loja",
      assertSucceeds(shippingRef(ownerA, LOJA_A, "melhor_envio_ped-1").get()),
    );
    await check(
      "2. admin/dono não escreve shipping_preorders",
      assertFails(
        shippingRef(ownerA, LOJA_A, "melhor_envio_ped-2").set({ status: "failed" }),
      ),
    );
    await check(
      "3. vendedor não lê shipping_preorders",
      assertFails(shippingRef(sellerA, LOJA_A, "melhor_envio_ped-1").get()),
    );
    await check(
      "4. anônimo não lê shipping_preorders",
      assertFails(shippingRef(anon, LOJA_A, "melhor_envio_ped-1").get()),
    );
    await check(
      "5. loja A não lê shipping_preorders da loja B",
      assertFails(shippingRef(ownerA, LOJA_B, "melhor_envio_ped-1").get()),
    );

    console.log("fretes_secrets e config/fretes");
    await check(
      "6. cliente não lê fretes_secrets",
      assertFails(secretsRef(ownerA, LOJA_A).get()),
    );
    await check(
      "7. cliente não escreve fretes_secrets",
      assertFails(secretsRef(ownerA, LOJA_A).set({ melhor_envio: { token: "x" } })),
    );
    await check(
      "8. cliente não salva token Melhor Envio em config/fretes",
      assertFails(
        fretesRef(ownerA, LOJA_A).set({ melhorEnvio: { token: "x" } }),
      ),
    );
    await check(
      "9. escrita pública segura em config/fretes permitida",
      assertSucceeds(
        fretesRef(ownerA, LOJA_A).set(
          {
            cepOrigem: "01310100",
            integrations: { melhor_envio: { configured: true, enabled: true } },
          },
          { merge: true },
        ),
      ),
    );
    await check(
      "10. match amplo pre_pedidos não libera shipping_preorders para vendedor",
      assertFails(shippingRef(sellerA, LOJA_A, "melhor_envio_ped-1").get()),
    );
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nRules emulator shipping_preorder: ${passed} passou, ${failed} falhou`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
