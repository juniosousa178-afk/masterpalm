/**
 * Rules — pedido_status_publico: get público por ID exato, list só para membros da loja.
 * projectId: demo-masterpalm-public-order. NÃO usa masterpalm-58c46. NÃO usa firebase-admin.
 * Uso: firebase emulators:exec --only firestore --project demo-masterpalm-public-order "node <este arquivo>"
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dir = dirname(fileURLToPath(import.meta.url));
const rulesTestingUrl = pathToFileURL(
  join(__dir, "../../../functions/node_modules/@firebase/rules-unit-testing/dist/esm/index.esm.js"),
).href;
const { initializeTestEnvironment, assertFails, assertSucceeds } = await import(rulesTestingUrl);

const PROJECT_ID = "demo-masterpalm-public-order";
const LOJA_A = "loja-a";
const LOJA_B = "loja-b";
const OWNER_A = "owner_a";
const PEDIDO_A = "PedidoAaaaaaaaaaaaaa";
const PEDIDO_B = "PedidoBbbbbbbbbbbbbb";
const PEDIDO_C = "PedidoCcccccccccccccc";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST || "";
const normalized = emulatorHost.trim().toLowerCase();
if (
  !normalized ||
  normalized.includes("masterpalm-58c46") ||
  !(normalized.startsWith("localhost:") || normalized.startsWith("127.0.0.1:") || normalized.startsWith("[::1]:"))
) {
  console.error(`ABORT: FIRESTORE_EMULATOR_HOST precisa ser local (atual: ${emulatorHost || "vazio"}).`);
  process.exit(1);
}
const [host, portStr] = emulatorHost.split(":");

const env = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: {
    host,
    port: Number(portStr || "8080"),
    rules: readFileSync(join(__dir, "../../../firestore.rules"), "utf8"),
  },
});

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

const mirror = (lojaId, pedidoId) => ({
  pedidoId,
  lojaId,
  status: "pendente",
  total: 10,
  itensResumo: [{ nome: "Anel", quantidade: 1 }],
});

await env.clearFirestore();
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await db.doc(`lojas/${LOJA_A}`).set({ ownerUid: OWNER_A });
  await db.doc(`lojas/${LOJA_B}`).set({ ownerUid: "owner_b" });
  await db.doc(`lojas/${LOJA_A}/pedido_status_publico/${PEDIDO_A}`).set(mirror(LOJA_A, PEDIDO_A));
  await db.doc(`lojas/${LOJA_A}/pedido_status_publico/${PEDIDO_B}`).set(mirror(LOJA_A, PEDIDO_B));
  await db.doc(`lojas/${LOJA_B}/pedido_status_publico/${PEDIDO_C}`).set(mirror(LOJA_B, PEDIDO_C));
});

const anon = env.unauthenticatedContext().firestore();
const outsider = env.authenticatedContext("outsider").firestore();
const ownerA = env.authenticatedContext(OWNER_A).firestore();

const pub = (db, lojaId, pedidoId) => db.doc(`lojas/${lojaId}/pedido_status_publico/${pedidoId}`);
const pubCol = (db, lojaId) => db.collection(`lojas/${lojaId}/pedido_status_publico`);

await check("A. anônimo lê pedido A por ID exato na loja A",
  assertSucceeds(pub(anon, LOJA_A, PEDIDO_A).get()));
await check("B. anônimo NÃO lista a coleção (loja e collectionGroup)", Promise.all([
  assertFails(pubCol(anon, LOJA_A).get()),
  assertFails(anon.collectionGroup("pedido_status_publico").get()),
]));
await check("C. anônimo NÃO consulta com filtro", Promise.all([
  assertFails(pubCol(anon, LOJA_A).where("status", "==", "pendente").get()),
  assertFails(pubCol(anon, LOJA_A).where("pedidoId", "==", PEDIDO_A).get()),
  assertFails(anon.collectionGroup("pedido_status_publico").where("lojaId", "==", LOJA_A).get()),
]));
await check("D. pedido da loja A com loja B na referência não é revelado", Promise.all([
  assertFails(pub(anon, LOJA_B, PEDIDO_A).get()),
  assertFails(pub(anon, LOJA_A, PEDIDO_C).get()),
]));
await check("E. ID inexistente não revela nada",
  assertFails(pub(anon, LOJA_A, "NaoExiste0000000000x").get()));
await check("F. dono da loja A mantém get, list, escrita válida e delete", (async () => {
  await assertSucceeds(pub(ownerA, LOJA_A, PEDIDO_A).get());
  await assertSucceeds(pubCol(ownerA, LOJA_A).get());
  await assertSucceeds(pub(ownerA, LOJA_A, PEDIDO_B).set(mirror(LOJA_A, PEDIDO_B)));
  await assertSucceeds(pub(ownerA, LOJA_A, PEDIDO_B).delete());
})());
await check("G. lojista de outra loja continua bloqueado em list e escrita", Promise.all([
  assertFails(pubCol(outsider, LOJA_A).get()),
  assertFails(pubCol(ownerA, LOJA_B).get()),
  assertFails(pub(ownerA, LOJA_B, PEDIDO_C).set(mirror(LOJA_B, PEDIDO_C))),
  assertFails(pub(ownerA, LOJA_B, PEDIDO_C).delete()),
]));
await check("H. anônimo NÃO escreve nem apaga o espelho", Promise.all([
  assertFails(pub(anon, LOJA_A, PEDIDO_A).set(mirror(LOJA_A, PEDIDO_A))),
  assertFails(pub(anon, LOJA_A, PEDIDO_A).update({status: "pago"})),
  assertFails(pub(anon, LOJA_A, "NovoAnonimo000000000").set(mirror(LOJA_A, "NovoAnonimo000000000"))),
  assertFails(pub(anon, LOJA_A, PEDIDO_A).delete()),
]));

const IMG = "https://firebasestorage.googleapis.com/v0/b/demo/o/lojas%2Floja-a%2Fprodutos%2Fanel.jpg?alt=media&token=t";
const PEDIDO_FOTO = "PedidoFotoaaaaaaaaaa";
const mirrorComFoto = (lojaId, pedidoId) => ({
  ...mirror(lojaId, pedidoId),
  itensResumo: [{ nome: "Anel", quantidade: 1, imagem: IMG }],
});
await env.withSecurityRulesDisabled(async (ctx) => {
  await ctx.firestore().doc(`lojas/${LOJA_A}/pedido_status_publico/${PEDIDO_FOTO}`)
    .set(mirrorComFoto(LOJA_A, PEDIDO_FOTO));
});
await check("I. espelho com foto: anônimo lê por ID exato e recebe a imagem", (async () => {
  const snap = await assertSucceeds(pub(anon, LOJA_A, PEDIDO_FOTO).get());
  if (snap.data().itensResumo[0].imagem !== IMG) throw new Error("imagem ausente");
})());
await check("J. espelho com foto: anônimo continua sem listar/consultar e sem escrever", Promise.all([
  assertFails(pubCol(anon, LOJA_A).get()),
  assertFails(pubCol(anon, LOJA_A).where("status", "==", "pendente").get()),
  assertFails(pub(anon, LOJA_A, PEDIDO_FOTO).set(mirrorComFoto(LOJA_A, PEDIDO_FOTO))),
  assertFails(pub(anon, LOJA_A, PEDIDO_FOTO).update({ itensResumo: [] })),
]));
await check("K. dono da loja grava espelho com foto (cancelamento no app) sem mudar Rules", Promise.all([
  assertSucceeds(pub(ownerA, LOJA_A, PEDIDO_FOTO).set({ ...mirrorComFoto(LOJA_A, PEDIDO_FOTO), status: "cancelado" })),
  assertFails(pub(ownerA, LOJA_B, PEDIDO_FOTO).set(mirrorComFoto(LOJA_B, PEDIDO_FOTO))),
]));

await env.cleanup();
console.log(`PUBLIC_ORDER_RULES passed=${passed} failed=${failed}`);
process.exit(failed === 0 ? 0 : 1);
