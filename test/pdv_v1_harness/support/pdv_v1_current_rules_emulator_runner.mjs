/**
 * Valida Rules ATUAIS (firestore.rules) no Emulator — Fase 6.4 PDV harness.
 * projectId: demo-masterpalm-pdv-v1-harness
 * NÃO valida Rules V1 futuras. NÃO usa masterpalm-58c46.
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

const PROJECT_ID = "demo-masterpalm-pdv-v1-harness";
const LOJA_ID = "loja-demo-pdv-v1-harness-64";
const LOJA_OUTSIDER = "loja-outside-demo-64";
const OWNER_UID = "owner_demo_pdv_v1_64";
const OUTSIDER_UID = "outsider_demo_pdv_v1_64";
const MARKER_ID = "00000000-0000-4000-8000-000000000064";
const PROD_ID = "prod-sint-demo-64";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  console.error(
    "ABORT: FIRESTORE_EMULATOR_HOST não definido — evita conexão com produção.",
  );
  process.exit(1);
}
if (emulatorHost.includes("masterpalm-58c46")) {
  console.error("ABORT: host contém masterpalm-58c46");
  process.exit(1);
}
if (!emulatorHost.includes("localhost") && !emulatorHost.includes("127.0.0.1")) {
  console.error("ABORT: host não é localhost/127.0.0.1");
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");

const rulesPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../../firestore.rules",
);
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

function markerRef(ctx, lojaId = LOJA_ID, docId = MARKER_ID) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection("estoque_baixa_pagamento")
    .doc(docId);
}

function estoqueRef(ctx, lojaId = LOJA_ID, prodId = PROD_ID) {
  return ctx
    .firestore()
    .collection("lojas")
    .doc(lojaId)
    .collection("estoque_produtos")
    .doc(prodId);
}

async function main() {
  console.log(`Rules harness Fase 6.4 | project=${PROJECT_ID} | host=${emulatorHost}`);
  console.log("Valida Rules ATUAIS — NÃO Rules V1 futuras.");

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection("lojas").doc(LOJA_ID).set({
        ownerUid: OWNER_UID,
        ownerEmail: "owner-demo@harness.local",
        published: false,
      });
      await db.collection("lojas").doc(LOJA_OUTSIDER).set({
        ownerUid: OUTSIDER_UID,
        ownerEmail: "outsider@harness.local",
        published: false,
      });
      await db.collection("users").doc(OWNER_UID).set({
        email: "owner-demo@harness.local",
        store_id: LOJA_ID,
      });
      await db.collection("users").doc(OUTSIDER_UID).set({
        email: "outsider@harness.local",
        store_id: LOJA_OUTSIDER,
      });
      await db
        .collection("lojas")
        .doc(LOJA_ID)
        .collection("estoque_produtos")
        .doc(PROD_ID)
        .set({ lojaId: LOJA_ID, quantidade: 10, nome: "SKU Demo" });
      await markerRef(context, LOJA_ID).set({
        lojaId: LOJA_ID,
        baixaAplicada: false,
        origem: "catalogo",
      });
    });

    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner-demo@harness.local",
    });
    const outsider = testEnv.authenticatedContext(OUTSIDER_UID, {
      email: "outsider@harness.local",
    });

    console.log("Marcador legado estoque_baixa_pagamento");
    await check(
      "1. membro lê marcador própria loja",
      assertSucceeds(markerRef(owner).get()),
    );
    await check(
      "2. membro cria marcador legado com lojaId correspondente",
      assertSucceeds(
        markerRef(owner, LOJA_ID, "marker-create-demo-64").set({
          lojaId: LOJA_ID,
          baixaAplicada: false,
          origem: "catalogo",
        }),
      ),
    );
    await check(
      "3. membro grava baixaAplicada:true isolado (FORJA — Rules atuais permitem)",
      assertSucceeds(
        markerRef(owner).update({ baixaAplicada: true, estornoAplicado: false }),
      ),
    );
    await check(
      "4. membro grava estornoAplicado:true isolado (FORJA — Rules atuais permitem)",
      assertSucceeds(
        markerRef(owner).update({ estornoAplicado: true }),
      ),
    );
    await check(
      "5. membro altera marcador existente (update livre)",
      assertSucceeds(
        markerRef(owner).update({ protocolVersion: 0, nota: "alterado" }),
      ),
    );
    await check(
      "6. usuário fora da loja negado leitura",
      assertFails(markerRef(outsider, LOJA_ID).get()),
    );
    await check(
      "7. usuário loja divergente negado escrita",
      assertFails(
        markerRef(outsider, LOJA_ID, "marker-forbidden-64").set({
          lojaId: LOJA_ID,
          baixaAplicada: true,
        }),
      ),
    );

    console.log("estoque_produtos");
    await check(
      "8. membro escreve estoque_produtos (Rules atuais permissivas)",
      assertSucceeds(
        estoqueRef(owner).set({ lojaId: LOJA_ID, quantidade: 9 }, { merge: true }),
      ),
    );
    await check(
      "9. outsider negado estoque_produtos de outra loja",
      assertFails(
        estoqueRef(outsider, LOJA_ID).set({ lojaId: LOJA_ID, quantidade: 0 }),
      ),
    );

    console.log("Isolamento projeto");
    if (PROJECT_ID === "demo-masterpalm-pdv-v1-harness") {
      console.log("  OK  10. projectId == demo-masterpalm-pdv-v1-harness");
      passed += 1;
    } else {
      console.error(" FAIL 10. projectId incorreto");
      failed += 1;
    }
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nResultado: ${passed} OK, ${failed} FAIL`);
  console.log(
    "Limitações: valida Rules atuais no Emulator; NÃO prova produção, quota ou cliente comprometido em escala.",
  );
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
