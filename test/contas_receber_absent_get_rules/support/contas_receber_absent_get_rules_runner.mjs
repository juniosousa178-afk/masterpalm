/**
 * Rules-only: same-store GET of an absent contas_receber document.
 * Requires FIRESTORE_EMULATOR_HOST. Never targets production.
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dir, "../../..");
const rulesTestingUrl = pathToFileURL(
  join(repoRoot, "functions/node_modules/@firebase/rules-unit-testing/dist/esm/index.esm.js"),
).href;

const { initializeTestEnvironment, assertFails, assertSucceeds } = await import(rulesTestingUrl);

const PROJECT_ID = "demo-fiado-absent-get";
const LOJA_A = "loja-fiado-rules-a";
const LOJA_B = "loja-fiado-rules-b";
const UID_A = "uid_fiado_rules_a";
const UID_B = "uid_fiado_rules_b";
const AMOUNT = 504.6;

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST || "";
if (!emulatorHost || emulatorHost.includes("masterpalm-58c46")) {
  console.error("ABORT: FIRESTORE_EMULATOR_HOST ausente ou aponta para produção.");
  process.exit(1);
}
if (!PROJECT_ID.startsWith("demo-")) {
  console.error("ABORT: projectId de teste precisa começar com demo-.");
  process.exit(1);
}

const [host, portStr] = emulatorHost.split(":");
const port = Number(portStr || "8080");
const newRules = readFileSync(join(repoRoot, "firestore.rules"), "utf8");
const BASELINE_COMMIT = "739ee56a07fe8b5040dd4b6ac36d0e35764f0966";
const oldRules = execFileSync("git", ["show", `${BASELINE_COMMIT}:firestore.rules`], {
  cwd: repoRoot,
  encoding: "utf8",
});

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    console.log(`  OK  ${name}`);
    passed += 1;
  } catch (err) {
    console.error(` FAIL ${name}`, err?.message || err);
    failed += 1;
  }
}

function col(ctx, lojaId) {
  return ctx.firestore().collection("lojas").doc(lojaId).collection("contas_receber");
}

function receivable(lojaId, extra = {}) {
  return {
    lojaId,
    valorOriginal: AMOUNT,
    valorPago: 0,
    saldoAtual: AMOUNT,
    valor: AMOUNT,
    status: "pendente",
    pago: false,
    historicoPagamentos: [],
    schemaVersion: 1,
    ...extra,
  };
}

function baixaId(docId, forma, day) {
  const cents = Math.round(Math.abs(AMOUNT) * 100);
  const formaKey = forma.trim().toLowerCase().replaceAll(" ", "_");
  return `bx_${docId}_${cents}_${day}_${formaKey}`;
}

async function seed(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection("lojas").doc(LOJA_A).set({ ownerUid: UID_A });
    await db.collection("lojas").doc(LOJA_B).set({ ownerUid: UID_B });
    await db.collection("users").doc(UID_A).set({ store_id: LOJA_A, email: "a@fiado-rules.local" });
    await db.collection("users").doc(UID_B).set({ store_id: LOJA_B, email: "b@fiado-rules.local" });
    await col(context, LOJA_A).doc("existing").set(receivable(LOJA_A));
    await col(context, LOJA_B).doc("existing-b").set(receivable(LOJA_B));
    await col(context, LOJA_A).doc("mismatch").set(receivable(LOJA_B));
  });
}

async function queryOutcome(ctx, lojaId) {
  try {
    const snap = await col(ctx, lojaId).get();
    return `allow:${snap.size}`;
  } catch (err) {
    const code = err?.code || err?.message || "deny";
    return `deny:${code}`;
  }
}

async function publishAndReceive(ctx, docId, forma) {
  const ref = col(ctx, LOJA_A).doc(docId);
  const first = await ref.get();
  if (first.exists) throw new Error(`esperado ausente: ${docId}`);
  await ref.set(receivable(LOJA_A, { contaReceberId: docId }));

  const day = "20261007";
  const id = baixaId(docId, forma, day);
  const finRef = ctx.firestore().collection("lojas").doc(LOJA_A).collection("lancamentos_financeiros").doc(`lf_${id}`);

  async function applyOnce() {
    await ctx.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.data() || {};
      const hist = Array.isArray(data.historicoPagamentos) ? data.historicoPagamentos : [];
      if (hist.some((h) => h.baixaId === id && h.estornada !== true)) return;
      hist.push({
        baixaId: id,
        valor: AMOUNT,
        data: "2026-10-07T12:00:00.000",
        forma,
        estornada: false,
      });
      tx.set(ref, {
        ...data,
        lojaId: LOJA_A,
        historicoPagamentos: hist,
        valorPago: AMOUNT,
        saldoAtual: 0,
        valor: 0,
        status: "paga",
        pago: true,
        lastWriteOrigin: "baixa",
      }, { merge: true });
    });
    await finRef.set({
      lojaId: LOJA_A,
      valor: AMOUNT,
      formaPagamento: forma,
      tipo: "entrada_extra",
      referenciaExterna: id,
    }, { merge: true });
  }

  await applyOnce();
  await applyOnce();

  const after = await ref.get();
  const data = after.data() || {};
  const hist = data.historicoPagamentos || [];
  if (hist.length !== 1) throw new Error(`historico ${hist.length} em ${docId}`);
  if (hist[0].baixaId !== id) throw new Error(`baixaId divergente em ${docId}`);
  if (hist[0].forma !== forma) throw new Error(`forma ${hist[0].forma}`);
  if (Math.abs(Number(data.valorPago) - AMOUNT) > 0.001) throw new Error("valorPago");
  if (Math.abs(Number(data.saldoAtual)) > 0.001) throw new Error("saldo");
  if (data.status !== "paga") throw new Error(`status ${data.status}`);
  const fin = await finRef.get();
  if (!fin.exists) throw new Error(`lancamento ausente para ${forma}`);
  if (fin.data().referenciaExterna !== id) throw new Error(`referencia ${forma}`);
}

async function listBaseline() {
  const oldEnv = await initializeTestEnvironment({
    projectId: `${PROJECT_ID}-old`,
    firestore: { rules: oldRules, host, port },
  });
  try {
    await seed(oldEnv);
    const ownerA = oldEnv.authenticatedContext(UID_A, { email: "a@fiado-rules.local" });
    const oldSame = await queryOutcome(ownerA, LOJA_A);
    const oldCross = await queryOutcome(ownerA, LOJA_B);
    console.log(`  OLD same-store list ${oldSame}`);
    console.log(`  OLD cross-store list ${oldCross}`);
    return { oldSame, oldCross };
  } finally {
    await oldEnv.cleanup();
  }
}

async function main() {
  console.log(`RULES contas_receber absent GET | project=${PROJECT_ID} | host=${emulatorHost}`);
  const { oldSame, oldCross } = await listBaseline();
  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: newRules, host, port },
  });

  try {
    await seed(testEnv);

    const userA = testEnv.authenticatedContext(UID_A, { email: "a@fiado-rules.local" });
    const anon = testEnv.unauthenticatedContext();
    const newSame = await queryOutcome(userA, LOJA_A);
    const newCross = await queryOutcome(userA, LOJA_B);
    console.log(`  NEW same-store list ${newSame}`);
    console.log(`  NEW cross-store list ${newCross}`);

    await check("list/query same-store unchanged", async () => {
      if (newSame !== oldSame) throw new Error(`${oldSame} -> ${newSame}`);
    });
    await check("list/query cross-store unchanged and denied", async () => {
      if (newCross !== oldCross) throw new Error(`${oldCross} -> ${newCross}`);
      if (!newCross.startsWith("deny:")) throw new Error(newCross);
    });

    await check("same-store absent GET exists=false", async () => {
      const snap = await assertSucceeds(col(userA, LOJA_A).doc("missing-id").get());
      if (snap.exists) throw new Error("exists=true");
    });
    await check("cross-store absent GET denied", async () => {
      await assertFails(col(userA, LOJA_B).doc("missing-id").get());
    });
    await check("unauthenticated absent GET denied", async () => {
      await assertFails(col(anon, LOJA_A).doc("missing-id").get());
    });
    await check("same-store existing GET allowed", async () => {
      const snap = await assertSucceeds(col(userA, LOJA_A).doc("existing").get());
      if (!snap.exists) throw new Error("missing existing");
      if (snap.data().lojaId !== LOJA_A) throw new Error("lojaId");
    });
    await check("cross-store existing GET denied", async () => {
      await assertFails(col(userA, LOJA_B).doc("existing-b").get());
    });
    await check("mismatched embedded lojaId GET denied", async () => {
      await assertFails(col(userA, LOJA_A).doc("mismatch").get());
    });
    await check("same-store create allowed", async () => {
      await assertSucceeds(col(userA, LOJA_A).doc("create-ok").set(receivable(LOJA_A)));
    });
    await check("cross-store create denied", async () => {
      await assertFails(col(userA, LOJA_B).doc("create-no").set(receivable(LOJA_B)));
    });
    await check("same-store create with foreign lojaId denied", async () => {
      await assertFails(col(userA, LOJA_A).doc("create-bad").set(receivable(LOJA_B)));
    });
    await check("same-store update allowed", async () => {
      await assertSucceeds(col(userA, LOJA_A).doc("existing").update({
        lojaId: LOJA_A,
        observacao: "baixa-teste",
      }));
    });
    await check("cross-store update denied", async () => {
      await assertFails(col(userA, LOJA_B).doc("existing-b").update({
        lojaId: LOJA_B,
        observacao: "nao",
      }));
    });
    await check("update cannot rewrite embedded lojaId to another store", async () => {
      await assertFails(col(userA, LOJA_A).doc("existing").update({ lojaId: LOJA_B }));
    });

    await check("Cartão local-only publish + baixa idempotente", async () => {
      await publishAndReceive(userA, "receipt-card", "Cartão");
    });
    await check("Pix local-only publish + baixa idempotente", async () => {
      await publishAndReceive(userA, "receipt-pix", "Pix");
    });
    await check("Dinheiro local-only publish + baixa idempotente", async () => {
      await publishAndReceive(userA, "receipt-cash", "Dinheiro");
    });
  } finally {
    await testEnv.cleanup();
  }

  console.log(`RESULT passed=${passed} failed=${failed}`);
  if (failed > 0) process.exit(1);
}

await main();
