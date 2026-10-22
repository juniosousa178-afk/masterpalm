// Foto dos itens no espelho público com Firestore real (emulador): só lê produtos da loja do pedido.
// Runs only against the local emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8187 (project demo-stock-catalog).
import test, {after} from "node:test";
import assert from "node:assert/strict";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {withPublicOrderItemImages} from "../src/publicOrderItemImages.js";

const enabled = process.env.FIRESTORE_EMULATOR_HOST === "127.0.0.1:8187";
const skip = enabled ? false : "Firestore emulator (127.0.0.1:8187) not running";
const db = enabled ? new Firestore({projectId: "demo-stock-catalog"}) : null;
after(() => db?.terminate());

const runId = Date.now().toString(36);
const img = (loja, f) =>
  `https://firebasestorage.googleapis.com/v0/b/demo/o/lojas%2F${loja}%2Fprodutos%2F${f}?alt=media&token=t-${f}`;

async function seed() {
  const lojaA = `imgA-${runId}`;
  const lojaB = `imgB-${runId}`;
  const batch = db.batch();
  batch.set(db.doc(`lojas/${lojaA}/produtos/estojo`), {nome: "Estojo", imagens: [img(lojaA, "estojo.jpg")], custo: 9});
  batch.set(db.doc(`lojas/${lojaA}/produtos/anel`), {nome: "Anel", imagem_principal: img(lojaA, "anel.jpg")});
  batch.set(db.doc(`lojas/${lojaA}/estoque_produtos/anel`), {imagens: [img(lojaA, "privada.jpg")], custoReal: 7});
  batch.set(db.doc(`lojas/${lojaB}/produtos/segredo`), {imagens: [img(lojaB, "segredo.jpg")]});
  await batch.commit();
  return {lojaA, lojaB};
}

async function sync(lojaId, pedidoId, pedidoData, isNewOrder) {
  const mirrorRef = db.doc(`lojas/${lojaId}/pedido_status_publico/${pedidoId}`);
  const itensResumo = pedidoData.itens
    .map((i) => ({nome: String(i.nome ?? "").trim(), quantidade: Number(i.quantidade) || 1}))
    .filter((i) => i.nome);
  const payload = {pedidoId, lojaId, status: pedidoData.status, total: pedidoData.total, itensResumo};
  payload.itensResumo = await withPublicOrderItemImages(db, {lojaId, pedidoData, itensResumo, mirrorRef, isNewOrder});
  await mirrorRef.set(payload, {merge: false});
  return (await mirrorRef.get()).data();
}

test("pedido novo: fotos do produto publicado, total/status intactos, nada privado", {skip}, async () => {
  const {lojaA} = await seed();
  const pedido = {
    status: "pendente",
    total: 74.5,
    dataCriacao: Timestamp.now(),
    itens: [
      {productId: "estojo", nome: "Estojo Veludo Rosa Anel/brinco/pingente/berloque", quantidade: 1, imagemSnapshot: "https://evil.example/x.png"},
      {productId: "anel", nome: "Anel Pedra Lux", quantidade: 1, imagemSnapshot: img(lojaA, "anel.jpg")},
    ],
  };
  const doc = await sync(lojaA, "P1", pedido, true);
  assert.equal(doc.total, 74.5);
  assert.equal(doc.status, "pendente");
  assert.deepEqual(doc.itensResumo, [
    {nome: "Estojo Veludo Rosa Anel/brinco/pingente/berloque", quantidade: 1, imagem: img(lojaA, "estojo.jpg")},
    {nome: "Anel Pedra Lux", quantidade: 1, imagem: img(lojaA, "anel.jpg")},
  ]);
  assert.ok(!JSON.stringify(doc).includes("privada"));
  assert.ok(!JSON.stringify(doc).includes("custo"));
});

test("produto apagado e status atualizado depois: a foto do pedido continua", {skip}, async () => {
  const {lojaA} = await seed();
  const old = Timestamp.fromMillis(Date.now() - 24 * 3600 * 1000);
  const pedido = {status: "pendente", total: 34.6, dataCriacao: old, itens: [{productId: "anel", nome: "Anel Pedra Lux", quantidade: 1}]};
  await sync(lojaA, "P2", pedido, true);
  await db.doc(`lojas/${lojaA}/produtos/anel`).delete();
  const doc = await sync(lojaA, "P2", {...pedido, status: "confirmado"}, false);
  assert.equal(doc.status, "confirmado");
  assert.deepEqual(doc.itensResumo, [{nome: "Anel Pedra Lux", quantidade: 1, imagem: img(lojaA, "anel.jpg")}]);
});

test("pedido legado atualizado: continua sem foto", {skip}, async () => {
  const {lojaA} = await seed();
  const old = Timestamp.fromMillis(Date.now() - 24 * 3600 * 1000);
  await db.doc(`lojas/${lojaA}/pedido_status_publico/P3`).set({itensResumo: [{nome: "Anel", quantidade: 1}]});
  const doc = await sync(lojaA, "P3", {status: "confirmado", total: 10, dataCriacao: old, itens: [{productId: "anel", nome: "Anel", quantidade: 1}]}, false);
  assert.deepEqual(doc.itensResumo, [{nome: "Anel", quantidade: 1}]);
});

test("cross-tenant: produto de outra loja nunca vira foto", {skip}, async () => {
  const {lojaA, lojaB} = await seed();
  const doc = await sync(lojaA, "P4", {
    status: "pendente",
    total: 1,
    dataCriacao: Timestamp.now(),
    itens: [
      {productId: "segredo", nome: "Segredo", quantidade: 1, imagemSnapshot: img(lojaB, "segredo.jpg")},
      {productId: `../../${lojaB}/produtos/segredo`, nome: "Path", quantidade: 1},
    ],
  }, true);
  assert.deepEqual(doc.itensResumo, [{nome: "Segredo", quantidade: 1}, {nome: "Path", quantidade: 1}]);
  assert.ok(!JSON.stringify(doc).includes(lojaB));
});
