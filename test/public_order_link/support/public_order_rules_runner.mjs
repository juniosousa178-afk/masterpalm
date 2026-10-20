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

await check("anônimo lê pedido A por ID exato na loja A",
  assertSucceeds(anon.doc(`lojas/${LOJA_A}/pedido_status_publico/${PEDIDO_A}`).get()));
await check("anônimo NÃO lê pedido C trocando a loja para A (inexistente)",
  assertFails(anon.doc(`lojas/${LOJA_A}/pedido_status_publico/${PEDIDO_C}`).get()));
await check("anônimo NÃO lê pedido A pela loja B",
  assertFails(anon.doc(`lojas/${LOJA_B}/pedido_status_publico/${PEDIDO_A}`).get()));
await check("anônimo NÃO lista pedidos da loja A",
  assertFails(anon.collection(`lojas/${LOJA_A}/pedido_status_publico`).get()));
await check("anônimo NÃO lista via collectionGroup",
  assertFails(anon.collectionGroup("pedido_status_publico").get()));
await check("usuário de outra loja NÃO lista pedidos da loja A",
  assertFails(outsider.collection(`lojas/${LOJA_A}/pedido_status_publico`).get()));
await check("dono da loja A lista os pedidos da própria loja",
  assertSucceeds(ownerA.collection(`lojas/${LOJA_A}/pedido_status_publico`).get()));
await check("anônimo NÃO escreve no espelho",
  assertFails(anon.doc(`lojas/${LOJA_A}/pedido_status_publico/${PEDIDO_A}`).set(mirror(LOJA_A, PEDIDO_A))));

await env.cleanup();
console.log(`PUBLIC_ORDER_RULES passed=${passed} failed=${failed}`);
process.exit(failed === 0 ? 0 : 1);
