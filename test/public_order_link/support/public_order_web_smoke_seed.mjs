// Fixtures da página pública do pedido no emulador (nunca em produção).
// FIRESTORE_EMULATOR_HOST=127.0.0.1:8187 node test/public_order_link/support/public_order_web_smoke_seed.mjs
import {createRequire} from "node:module";

const require = createRequire(new URL("../../../functions/package.json", import.meta.url));
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST obrigatório: este seed só roda no emulador.");
  process.exit(1);
}

const PROJECT_ID = "demo-masterpalm-public-order";
const LOJA = "loja-smoke";
const IMG_A = "https://picsum.photos/id/237/400/400";
const IMG_B = "https://picsum.photos/id/1080/400/400";
const IMG_404 = "https://picsum.photos/id/9999999/400/400";

const criado = Timestamp.fromDate(new Date("2026-10-21T12:30:00Z"));
const base = (pedidoId, itensResumo, extra = {}) => ({
  pedidoId,
  lojaId: LOJA,
  status: "pendente",
  dataCriacao: criado,
  dataAtualizacao: criado,
  total: 74.5,
  itensResumo,
  freteNome: "PAC",
  ...extra,
});

export const SMOKE_ORDERS = {
  SmokeDoisProdutos01: base("SmokeDoisProdutos01", [
    {nome: "Estojo Veludo Rosa Anel/brinco/pingente/berloque", quantidade: 1, imagem: IMG_A},
    {nome: "Anel Pedra Lux", quantidade: 2, imagem: IMG_B},
  ], {codigoRastreio: "BR123456789BR"}),
  SmokeQuebradaFalta01: base("SmokeQuebradaFalta01", [
    {nome: "Brinco Argola Quebrada", quantidade: 1, imagem: IMG_404},
    {nome: "Pulseira Sem Foto", quantidade: 3},
  ], {status: "confirmado", total: 120}),
  SmokeLegadoSemFoto01: base("SmokeLegadoSemFoto01", [
    {nome: "Colar Legado", quantidade: 1},
  ], {total: 39.9}),
};

const app = initializeApp({projectId: PROJECT_ID});
const db = getFirestore(app);
for (const [id, data] of Object.entries(SMOKE_ORDERS)) {
  await db.collection("lojas").doc(LOJA).collection("pedido_status_publico").doc(id).set(data);
}
console.log(`seeded ${Object.keys(SMOKE_ORDERS).length} pedido_status_publico em lojas/${LOJA}`);
