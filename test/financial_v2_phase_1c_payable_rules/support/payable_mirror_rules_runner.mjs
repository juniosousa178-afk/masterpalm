/**
 * Fase 1C — regras do espelho contas_pagar no emulador.
 * projectId demo. Não aponta para produção.
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

const PROJECT_ID = "demo-masterpalm-payable-mirror";
const LOJA_A = "loja-payable-a";
const LOJA_B = "loja-payable-b";
const OWNER_A = "owner_payable_a";
const OWNER_B = "owner_payable_b";

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

function mirrorDoc(lojaId, payableId, status = "pendente") {
  const now = Timestamp.fromDate(new Date("2026-03-01T12:00:00Z"));
  return {
    storeId: lojaId,
    payableId,
    source: "hive_conta_pagar",
    schemaVersion: 1,
    mirroredAt: now,
    mirrorRevision: 1,
    localUpdatedAtMs: 1,
    mirrorOnly: true,
    authoritative: false,
    deletedAt: null,
    id: payableId,
    lojaId,
    fornecedorId: 1,
    fornecedorNome: "F",
    compraId: "compraA",
    descricao: "P",
    valorTotalCompra: 10,
    valorParcela: 10,
    parcelaNumero: 1,
    parcelaTotal: 1,
    dataVencimento: now,
    dataPagamento: null,
    status,
    formaPagamento: "",
    observacao: "",
    lancamentoFinanceiroId: "",
    criadoEm: now,
    atualizadoEm: now,
    dataCompra: now,
    idFirebase: "",
    deleted: false,
  };
}

function ref(ctx, lojaId, payableId) {
  return ctx.firestore().collection("lojas").doc(lojaId).collection("contas_pagar").doc(payableId);
}

let failed = 0;

async function check(name, promise) {
  try {
    await promise;
    console.log(`  OK  ${name}`);
  } catch (err) {
    console.error(` FAIL ${name}`, err?.message || err);
    failed += 1;
  }
}

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: { rules, host, port },
});

try {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection("lojas").doc(LOJA_A).set({
      ownerUid: OWNER_A,
      ownerEmail: "a@payable.local",
    });
    await db.collection("lojas").doc(LOJA_B).set({
      ownerUid: OWNER_B,
      ownerEmail: "b@payable.local",
    });
    await ref(context, LOJA_A, "compraA_p1").set(mirrorDoc(LOJA_A, "compraA_p1"));
  });

  const ownerA = testEnv.authenticatedContext(OWNER_A, {
    email: "a@payable.local",
  });
  const ownerB = testEnv.authenticatedContext(OWNER_B, {
    email: "b@payable.local",
  });

  await check(
    "SAME_STORE_READ_ALLOWED",
    assertSucceeds(ref(ownerA, LOJA_A, "compraA_p1").get()),
  );
  await check(
    "SAME_STORE_WRITE_ALLOWED",
    assertSucceeds(
      ref(ownerA, LOJA_A, "compraA_p2").set(mirrorDoc(LOJA_A, "compraA_p2")),
    ),
  );
  await check(
    "CROSS_STORE_READ_DENIED",
    assertFails(ref(ownerB, LOJA_A, "compraA_p1").get()),
  );
  await check(
    "CROSS_STORE_WRITE_DENIED",
    assertFails(
      ref(ownerB, LOJA_A, "compraB_p1").set(mirrorDoc(LOJA_A, "compraB_p1")),
    ),
  );
} finally {
  await testEnv.cleanup();
}

if (failed > 0) {
  console.error(`PAYABLE_RULES_FAILED=${failed}`);
  process.exit(1);
}
console.log("PAYABLE_RULES_PASS=true");
