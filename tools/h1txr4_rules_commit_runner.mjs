/**
 * M3.7 H1TX-R4 — reproduz commit R8 no Emulator com Rules do HEAD.
 * projectId: demo-masterpalm-h1tx-r4
 * NÃO usa masterpalm-58c46. NÃO usa credenciais reais.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dir = dirname(fileURLToPath(import.meta.url));
const rulesTestingUrl = pathToFileURL(
  join(__dir, "../functions/node_modules/@firebase/rules-unit-testing/dist/esm/index.esm.js"),
).href;

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = await import(rulesTestingUrl);

const PROJECT_ID = "demo-masterpalm-h1tx-r4";
const LOJA_ID = "nathy-pratas-e-folheados";
const PRODUCT_ID = "nathy-pratas-e-folheados-anel-elos-cora-ozinho";
const OPERATION_ID = "33642f7f-8342-48bb-9945-3e10c6af9b18";
const OWNER_UID = "owner_h1tx_r4_demo";
const ADMIN_UID = "admin_h1tx_r4_demo";

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
    return "ALLOW";
  } catch (err) {
    console.error(`  UNEXPECTED DENY ${name} — ${err?.message || err}`);
    failed += 1;
    return "DENY";
  }
}

async function expectDeny(name, promise) {
  try {
    await promise;
    console.error(`  UNEXPECTED ALLOW ${name}`);
    failed += 1;
    return "ALLOW";
  } catch (err) {
    console.log(`  DENY  ${name} (esperado)`);
    passed += 1;
    return "DENY";
  }
}

function db(ctx) {
  return ctx.firestore();
}

function estoqueProdutosRef(ctx, prodId = PRODUCT_ID) {
  return db(ctx)
    .collection("lojas")
    .doc(LOJA_ID)
    .collection("estoque_produtos")
    .doc(prodId);
}

function produtosRef(ctx, prodId = PRODUCT_ID) {
  return db(ctx)
    .collection("lojas")
    .doc(LOJA_ID)
    .collection("produtos")
    .doc(prodId);
}

function markerRef(ctx, opId = OPERATION_ID) {
  return db(ctx)
    .collection("lojas")
    .doc(LOJA_ID)
    .collection("estoque_baixa_pagamento")
    .doc(opId);
}

const BEFORE_ESTOQUE = {
  lojaId: LOJA_ID,
  nome: "Anel Elos Coração",
  quantidade: 12,
  variacoes: {
    12: { prata: 2 },
    15: { prata: 5 },
    19: { prata: 1 },
    20: { prata: 3 },
    21: { prata: 1 },
  },
  estoquePorTamanho: { 12: 2, 15: 5, 19: 1, 20: 3, 21: 1 },
};

const AFTER_STOCK = {
  quantidade: 11,
  variacoes: {
    12: { prata: 1 },
    15: { prata: 5 },
    19: { prata: 1 },
    20: { prata: 3 },
    21: { prata: 1 },
  },
  estoquePorTamanho: { 12: 1, 15: 5, 19: 1, 20: 3, 21: 1 },
};

/** Payload R8 exato (com estornoAplicado — observado em produção). */
function markerPayloadR8(opId = OPERATION_ID) {
  return {
    protocolVersion: 1,
    origem: "pdv",
    operationId: opId,
    saleId: opId,
    lojaId: LOJA_ID,
    baixaAplicada: true,
    estornoAplicado: false,
    snapshotHash: "c789a4a6a6e7bea1f24f48264b0fa0d11c1f3f5f8710e35e69175bf2d891018b",
    txItemsHash: "e346cb03833d7660f010cceeaadefd004b6ad90dbb02c8686d74ed6373e6e2cc",
  };
}

/** Payload contrato Rules V1 (8 chaves — sem estornoAplicado). */
function markerPayloadRulesV1(opId = OPERATION_ID) {
  const p = markerPayloadR8(opId);
  const { estornoAplicado: _drop, ...rest } = p;
  return rest;
}

async function seedBase(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const firestore = db(ctx);
    await firestore.collection("lojas").doc(LOJA_ID).set({
      ownerUid: OWNER_UID,
      ownerEmail: "owner-r4@demo.local",
    });
    await firestore.collection("users").doc(OWNER_UID).set({
      email: "owner-r4@demo.local",
      store_id: LOJA_ID,
    });
    await firestore.collection("users").doc(ADMIN_UID).set({
      email: "masterpalm@gmail.com",
      role: "admin",
    });
    await estoqueProdutosRef(ctx).set(BEFORE_ESTOQUE);
    await produtosRef(ctx).set({
      ...BEFORE_ESTOQUE,
      vendasCatalogoTotal: 0,
    });
  });
}

async function runMatrix(owner, admin) {
  console.log("\n=== RULE403 MATRIX (store owner) ===\n");

  const opSuffix = (n) => `${OPERATION_ID}-r403-${n}`;

  // RULE403-1: somente update estoque principal
  await expectAllow(
    "RULE403-1 estoque update principal",
    assertSucceeds(
      estoqueProdutosRef(owner).update({
        ...AFTER_STOCK,
        updatedAt: new Date(),
      }),
    ),
  );

  // RULE403-2: somente update granular (dot notation como no commit)
  await expectAllow(
    "RULE403-2 estoque update granular dot-notation",
    assertSucceeds(
      estoqueProdutosRef(owner).update({
        "estoquePorTamanho.12": 1,
        "variacoes.12.prata": 1,
        quantidade: 11,
        updatedAt: new Date(),
      }),
    ),
  );

  // RULE403-3: duas writes no mesmo estoque (update + set merge)
  await expectAllow(
    "RULE403-3 estoque update + set merge mesmo doc",
    (async () => {
      const ref = estoqueProdutosRef(owner);
      const batch = db(owner).batch();
      batch.update(ref, { ...AFTER_STOCK, updatedAt: new Date() });
      batch.set(ref, { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      await batch.commit();
    })(),
  );

  // RULE403-4: somente produtos mirror
  await expectDeny(
    "RULE403-4 produtos mirror set merge (estoque fields)",
    produtosRef(owner).set({ ...AFTER_STOCK, updatedAt: new Date() }, { merge: true }),
  );

  // RULE403-5a: marker R8 com estornoAplicado
  await expectDeny(
    "RULE403-5a marker create R8 (com estornoAplicado)",
    markerRef(owner, opSuffix(5)).set(markerPayloadR8(opSuffix(5))),
  );

  // RULE403-5b: marker sem estornoAplicado
  await expectAllow(
    "RULE403-5b marker create Rules V1 (sem estornoAplicado)",
    assertSucceeds(markerRef(owner, opSuffix(5)).set(markerPayloadRulesV1(opSuffix(5)))),
  );

  // RULE403-6: estoque principal + marker R8
  await expectDeny(
    "RULE403-6 estoque update + marker R8",
    (async () => {
      const batch = db(owner).batch();
      batch.update(estoqueProdutosRef(owner), { ...AFTER_STOCK, updatedAt: new Date() });
      batch.set(markerRef(owner, opSuffix(6)), markerPayloadR8(opSuffix(6)));
      await batch.commit();
    })(),
  );

  // RULE403-7: duas writes estoque + marker R8
  await expectDeny(
    "RULE403-7 duas writes estoque + marker R8",
    (async () => {
      const ref = estoqueProdutosRef(owner);
      const batch = db(owner).batch();
      batch.update(ref, { ...AFTER_STOCK, updatedAt: new Date() });
      batch.set(ref, { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      batch.set(markerRef(owner, opSuffix(7)), markerPayloadR8(opSuffix(7)));
      await batch.commit();
    })(),
  );

  // RULE403-8: estoque + mirror + marker R8
  await expectDeny(
    "RULE403-8 estoque + produtos mirror + marker R8",
    (async () => {
      const ref = estoqueProdutosRef(owner);
      const batch = db(owner).batch();
      batch.update(ref, { ...AFTER_STOCK, updatedAt: new Date() });
      batch.set(produtosRef(owner), { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      batch.set(markerRef(owner, opSuffix(8)), markerPayloadR8(opSuffix(8)));
      await batch.commit();
    })(),
  );

  // RULE403-9: commit R8 EXATO (4 writes)
  await expectDeny(
    "RULE403-9 commit R8 EXATO",
    (async () => {
      const ref = estoqueProdutosRef(owner);
      const batch = db(owner).batch();
      batch.update(ref, { ...AFTER_STOCK, updatedAt: new Date() });
      batch.set(ref, { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      batch.set(produtosRef(owner), { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      batch.set(markerRef(owner, opSuffix(9)), markerPayloadR8(opSuffix(9)));
      await batch.commit();
    })(),
  );

  // Contraste: R8 exato mas marker Rules-conforme
  await expectDeny(
    "RULE403-9b commit R8 sem estornoAplicado no marker",
    (async () => {
      const ref = estoqueProdutosRef(owner);
      const batch = db(owner).batch();
      batch.update(ref, { ...AFTER_STOCK, updatedAt: new Date() });
      batch.set(ref, { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      batch.set(produtosRef(owner), { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      batch.set(markerRef(owner, opSuffix("9b")), markerPayloadRulesV1(opSuffix("9b")));
      await batch.commit();
    })(),
  );

  console.log("\n=== ADMIN (isAdminOrSystem) contraste ===\n");
  await expectAllow(
    "ADMIN produtos mirror set merge",
    assertSucceeds(
      produtosRef(admin).set({ ...AFTER_STOCK, updatedAt: new Date() }, { merge: true }),
    ),
  );
  await expectDeny(
    "ADMIN marker R8 com estornoAplicado",
    markerRef(admin, opSuffix("adm")).set(markerPayloadR8(opSuffix("adm"))),
  );

  // GREEN path: estoque + marker V1 sem produtos mirror
  await expectAllow(
    "RULE403-10 estoque + marker V1 (sem produtos)",
    (async () => {
      const ref = estoqueProdutosRef(owner);
      const batch = db(owner).batch();
      batch.update(ref, { ...AFTER_STOCK, updatedAt: new Date() });
      batch.set(ref, { ...AFTER_STOCK, updatedAt: new Date() }, { merge: true });
      batch.set(markerRef(owner, opSuffix(10)), markerPayloadRulesV1(opSuffix(10)));
      await batch.commit();
    })(),
  );
}

async function main() {
  console.log(`H1TX-R4 Rules commit | project=${PROJECT_ID} | host=${emulatorHost}`);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules, host, port },
  });

  try {
    await seedBase(testEnv);
    const owner = testEnv.authenticatedContext(OWNER_UID, {
      email: "owner-r4@demo.local",
    });
    const admin = testEnv.authenticatedContext(ADMIN_UID, {
      email: "masterpalm@gmail.com",
    });
    await runMatrix(owner, admin);
  } finally {
    await testEnv.cleanup();
  }

  console.log(`\nResultado H1TX-R4: ${passed} OK, ${failed} FAIL`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
