/**
 * 040B2 + 040B3 — Rules emulator: PAID→OPEN client DENY (sem lastWriteOrigin),
 * duplicate/empty vendaId guards. projectId demo-*; NÃO usa produção.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dir = dirname(fileURLToPath(import.meta.url));
const candidates = [
  join(__dir, "../functions/node_modules/@firebase/rules-unit-testing/dist/esm/index.esm.js"),
  join(__dir, "../node_modules/@firebase/rules-unit-testing/dist/esm/index.esm.js"),
];

let rulesTestingUrl;
for (const p of candidates) {
  try {
    readFileSync(p);
    rulesTestingUrl = pathToFileURL(p).href;
    break;
  } catch {
    /* next */
  }
}
if (!rulesTestingUrl) {
  console.error("ABORT: @firebase/rules-unit-testing não encontrado.");
  process.exit(1);
}

const { initializeTestEnvironment } = await import(rulesTestingUrl);

const PROJECT_ID = "demo-masterpalm-fiado-040b2";
const LOJA = "loja-rules-040b2";
const OWNER = "owner_fiado_040b2";
const VENDA = "venda-rules-040b2";
const P1 = `cr_${VENDA}_p1`;
const LEGACY = "cr_legacy_deadbeef";

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

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const rules = readFileSync(join(__dir, "../firestore.rules"), "utf8");

let passed = 0;
let failed = 0;

async function expectAllow(name, promise) {
  try {
    await promise;
    console.log(`  ALLOW ${name}`);
    passed += 1;
  } catch (err) {
    console.error(`  UNEXPECTED DENY ${name} — ${err?.message || err}`);
    failed += 1;
  }
}

async function expectDeny(name, promise) {
  try {
    await promise;
    console.error(`  UNEXPECTED ALLOW ${name}`);
    failed += 1;
  } catch {
    console.log(`  DENY  ${name}`);
    passed += 1;
  }
}

function db(ctx) {
  return ctx.firestore();
}

function paidDoc(extra = {}) {
  return {
    lojaId: LOJA,
    contaReceberId: P1,
    vendaIdFirebase: VENDA,
    clienteNome: "Cliente",
    valorOriginal: 100,
    valorPago: 100,
    saldoAtual: 0,
    valor: 0,
    status: "paga",
    pago: true,
    lastWriteOrigin: "edicao_venda_paga",
    ...extra,
  };
}

function openDoc(id = P1, extra = {}) {
  return {
    lojaId: LOJA,
    contaReceberId: id,
    vendaIdFirebase: VENDA,
    clienteNome: "Cliente",
    valorOriginal: 100,
    valorPago: 0,
    saldoAtual: 100,
    valor: 100,
    status: "pendente",
    pago: false,
    lastWriteOrigin: "venda_fiada",
    ...extra,
  };
}

async function seedOwner(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const firestore = db(ctx);
    await firestore.collection("lojas").doc(LOJA).set({ ownerUid: OWNER });
  });
}

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: { host, port, rules },
});

try {
  await seedOwner(testEnv);
  const owner = testEnv.authenticatedContext(OWNER);

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await db(ctx).collection("lojas").doc(LOJA).collection("contas_receber").doc(P1).set(paidDoc());
  });

  await expectDeny(
    "OLD_CLIENT_REOPEN_UPDATE",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .set(openDoc(), { merge: true }),
  );

  await expectDeny(
    "OLD_CLIENT_UPSERT_REOPEN",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .set(openDoc(P1, { lastWriteOrigin: "app" }), { merge: true }),
  );

  await expectDeny(
    "OLD_CLIENT_PAGO_FALSE_KEEP_STATUS",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .set({ pago: false, lastWriteOrigin: "app" }, { merge: true }),
  );

  await expectDeny(
    "DELETE_PAID",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .delete(),
  );

  await expectDeny(
    "CREATE_SECOND_OPEN_LEGACY",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(LEGACY)
      .set(openDoc(LEGACY)),
  );

  await expectDeny(
    "SPOOF_ESTORNO_BAIXA",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .set(
        openDoc(P1, {
          lastWriteOrigin: "estorno_baixa",
          valorPago: 0,
          saldoAtual: 100,
        }),
        { merge: true },
      ),
  );

  await expectDeny(
    "SPOOF_ESTORNO_LOCAL",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .set(
        openDoc(P1, {
          lastWriteOrigin: "estorno_local",
          valorPago: 0,
          saldoAtual: 100,
          pago: false,
        }),
        { merge: true },
      ),
  );

  await expectDeny(
    "ARBITRARY_CLIENT_REFUND_MARKERS",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .set(
        openDoc(P1, {
          refund: true,
          status: "estornado",
          origin: "server",
          trusted: true,
          isRefund: true,
          serverWrite: true,
          admin: true,
          lastWriteOrigin: "trusted_refund_fn",
          pago: false,
          saldoAtual: 100,
        }),
        { merge: true },
      ),
  );

  await expectDeny(
    "EMPTY_SALE_ID_SALE_SHAPED_CREATE",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc("cr_empty-sale-040b3_p1")
      .set(openDoc("cr_empty-sale-040b3_p1", { vendaIdFirebase: "" })),
  );

  await expectDeny(
    "ALTERNATE_DOC_ID_DUPLICATE",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc("cr_alt-doc-040b3_p2")
      .set(openDoc("cr_alt-doc-040b3_p2", { vendaIdFirebase: VENDA })),
  );

  await expectAllow(
    "MANUAL_LEGACY_WITHOUT_SALE_ID",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc("cr_legacy_040b3aa")
      .set(openDoc("cr_legacy_040b3aa", { vendaIdFirebase: "" })),
  );

  await expectAllow(
    "LEGACY_PAID_NORMAL_UPDATE",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc(P1)
      .set(
        paidDoc({
          observacao: "atualizacao-normal-040b3",
          lastWriteOrigin: "app",
        }),
        { merge: true },
      ),
  );

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await db(ctx)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc("cr_venda-parcial-040b2_p1")
      .set(openDoc("cr_venda-parcial-040b2_p1", {
        vendaIdFirebase: "venda-parcial-040b2",
        saldoAtual: 100,
        valorPago: 0,
      }));
  });

  await expectAllow(
    "PARTIAL_OPEN_TO_PARTIAL",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc("cr_venda-parcial-040b2_p1")
      .set(
        openDoc("cr_venda-parcial-040b2_p1", {
          vendaIdFirebase: "venda-parcial-040b2",
          valorPago: 40,
          saldoAtual: 60,
          valor: 60,
          status: "parcial",
          lastWriteOrigin: "baixa",
        }),
        { merge: true },
      ),
  );

  await expectAllow(
    "OPEN_TO_PAID",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc("cr_venda-parcial-040b2_p1")
      .set(
        paidDoc({
          contaReceberId: "cr_venda-parcial-040b2_p1",
          vendaIdFirebase: "venda-parcial-040b2",
        }),
        { merge: true },
      ),
  );

  await expectAllow(
    "CREATE_NEW_OPEN_NO_CANONICAL_PAID",
    db(owner)
      .collection("lojas")
      .doc(LOJA)
      .collection("contas_receber")
      .doc("cr_venda-nova-040b2_p1")
      .set(openDoc("cr_venda-nova-040b2_p1", {
        vendaIdFirebase: "venda-nova-040b2",
      })),
  );

  console.log(`\n040B3 rules ${passed} passed / ${failed} failed`);
  if (failed > 0) process.exit(1);
} finally {
  await testEnv.cleanup();
}
