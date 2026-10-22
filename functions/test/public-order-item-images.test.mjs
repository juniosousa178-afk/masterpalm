import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

import {
  PUBLIC_ORDER_IMAGE_DERIVATION_WINDOW_MS,
  catalogProductImages,
  isSafeProductDocId,
  resolvePublicOrderItemImages,
  sanitizePublicOrderImageUrl,
  withPublicOrderItemImages,
} from "../src/publicOrderItemImages.js";

const LOJA_A = "loja-a";
const LOJA_B = "loja-b";
const PEDIDO = "PedidoAaaaaaaaaaaaaa";
const NOW = Date.UTC(2026, 9, 21, 12, 0, 0);
const storage = (loja, file) =>
  `https://firebasestorage.googleapis.com/v0/b/masterpalm-58c46.appspot.com/o/lojas%2F${loja}%2Fprodutos%2F${file}?alt=media&token=tok-${file}`;
const IMG_ESTOJO = storage(LOJA_A, "estojo%2F00_1.jpg");
const IMG_ESTOJO_2 = storage(LOJA_A, "estojo%2F01_2.jpg");
const IMG_ANEL = storage(LOJA_A, "anel%2F00_1.jpg");
const THUMB_ANEL = storage(LOJA_A, "anel%2Fthumbnails%2F00_1.webp");
const IMG_LOJA_B = storage(LOJA_B, "segredo%2F00_1.jpg");

const ts = (ms) => ({toMillis: () => ms});

function fakeDb(docs, {failGetAll = false} = {}) {
  const reads = [];
  const snap = (path) => ({
    id: path.split("/").pop(),
    exists: docs.has(path),
    data: () => docs.get(path),
  });
  const ref = (path) => ({
    path,
    id: path.split("/").pop(),
    collection: (c) => col(`${path}/${c}`),
    get: async () => {
      reads.push(path);
      return snap(path);
    },
  });
  const col = (path) => ({doc: (id) => ref(`${path}/${id}`)});
  return {
    reads,
    collection: (c) => col(c),
    getAll: async (...refs) => {
      if (failGetAll) throw Object.assign(new Error("unavailable"), {code: 14});
      refs.forEach((r) => reads.push(r.path));
      return refs.map((r) => snap(r.path));
    },
  };
}

const mirrorPath = (loja = LOJA_A) => `lojas/${loja}/pedido_status_publico/${PEDIDO}`;
const produtoPath = (loja, id) => `lojas/${loja}/produtos/${id}`;

const itemEstojo = {
  productId: "prod-estojo",
  nome: "Estojo Veludo Rosa Anel/brinco/pingente/berloque",
  quantidade: 1,
  precoUnitario: 39.9,
  imagem: IMG_ESTOJO,
  imagemSnapshot: IMG_ESTOJO,
};
const itemAnel = {
  productId: "prod-anel",
  nome: "Anel Pedra Lux",
  quantidade: 1,
  precoUnitario: 34.6,
  imagem: IMG_ANEL,
  imagemSnapshot: IMG_ANEL,
};

const resumoOf = (itens) =>
  itens
    .map((item) => ({nome: item?.nome == null ? "" : String(item.nome).trim(), quantidade: Number(item?.quantidade) || 1}))
    .filter((item) => item.nome.length > 0);

const catalogo = () =>
  new Map([
    [produtoPath(LOJA_A, "prod-estojo"), {nome: "Estojo", imagens: [IMG_ESTOJO, IMG_ESTOJO_2], custo: 10, quantidade: 4}],
    [produtoPath(LOJA_A, "prod-anel"), {nome: "Anel", imagens: [IMG_ANEL], custoReal: 7, fornecedor: "X"}],
    [produtoPath(LOJA_B, "prod-segredo"), {nome: "Segredo", imagens: [IMG_LOJA_B]}],
  ]);

async function run(db, itens, {isNewOrder = true, dataCriacao = ts(NOW), itensResumo} = {}) {
  return withPublicOrderItemImages(db, {
    lojaId: LOJA_A,
    pedidoData: {itens, dataCriacao, total: 74.5, status: "pendente"},
    itensResumo: itensResumo ?? resumoOf(itens),
    mirrorRef: db.collection("lojas").doc(LOJA_A).collection("pedido_status_publico").doc(PEDIDO),
    isNewOrder,
    nowMs: NOW,
  });
}

test("pedido novo com um produto: snapshot da imagem do catálogo, só nome/quantidade/imagem", async () => {
  const db = fakeDb(catalogo());
  const out = await run(db, [itemAnel]);
  assert.deepEqual(out, [{nome: "Anel Pedra Lux", quantidade: 1, imagem: IMG_ANEL}]);
  assert.deepEqual(Object.keys(out[0]), ["nome", "quantidade", "imagem"]);
});

test("exemplo de dois produtos: cada item recebe a sua imagem (total R$ 74,50 não é tocado)", async () => {
  const db = fakeDb(catalogo());
  const out = await run(db, [itemEstojo, itemAnel]);
  assert.deepEqual(out, [
    {nome: "Estojo Veludo Rosa Anel/brinco/pingente/berloque", quantidade: 1, imagem: IMG_ESTOJO},
    {nome: "Anel Pedra Lux", quantidade: 1, imagem: IMG_ANEL},
  ]);
  assert.deepEqual(db.reads, [
    mirrorPath(),
    produtoPath(LOJA_A, "prod-estojo"),
    produtoPath(LOJA_A, "prod-anel"),
  ]);
});

test("imagem da galeria escolhida no carrinho é mantida quando pertence ao produto", async () => {
  const db = fakeDb(catalogo());
  const out = await run(db, [{...itemEstojo, imagem: IMG_ESTOJO_2, imagemSnapshot: IMG_ESTOJO_2}]);
  assert.equal(out[0].imagem, IMG_ESTOJO_2);
});

test("URL arbitrária vinda do carrinho é recusada; usa a capa do produto", async () => {
  for (const bad of [
    "https://evil.example/x.png",
    "data:image/png;base64,AAAA",
    "javascript:alert(1)",
    "http://firebasestorage.googleapis.com/x.jpg",
    `${IMG_ESTOJO}"><script>`,
    IMG_LOJA_B,
  ]) {
    const db = fakeDb(catalogo());
    const out = await run(db, [{...itemEstojo, imagem: bad, imagemSnapshot: bad}]);
    assert.equal(out[0].imagem, IMG_ESTOJO, bad);
  }
});

test("capa segue a regra do catálogo: ignora thumbnail gerada no início da lista", () => {
  assert.equal(catalogProductImages({imagens: [THUMB_ANEL, IMG_ANEL]}).cover, IMG_ANEL);
  assert.equal(catalogProductImages({imagens: [THUMB_ANEL]}).cover, THUMB_ANEL);
  assert.equal(catalogProductImages({imagem_principal: IMG_ANEL}).cover, IMG_ANEL);
  assert.equal(catalogProductImages({imageUrl: IMG_ANEL}).cover, IMG_ANEL);
  assert.equal(catalogProductImages({imagem_principal: IMG_ANEL, imagens: [IMG_ESTOJO]}).cover, IMG_ESTOJO);
  assert.equal(catalogProductImages({}).cover, "");
  assert.deepEqual(
    [...catalogProductImages({imagens: [IMG_ESTOJO, " ", 3], imagem_principal: IMG_ANEL}).all],
    [IMG_ESTOJO, IMG_ANEL],
  );
});

test("produto sem imagem ou inexistente: item sai sem o campo imagem", async () => {
  const docs = catalogo();
  docs.set(produtoPath(LOJA_A, "sem-foto"), {nome: "Sem foto", imagens: []});
  const db = fakeDb(docs);
  const out = await run(db, [
    {nome: "Sem foto", quantidade: 2, productId: "sem-foto"},
    {nome: "Apagado", quantidade: 1, productId: "apagado", imagemSnapshot: IMG_ANEL},
    {nome: "Sem id", quantidade: 1, imagemSnapshot: IMG_ANEL},
  ]);
  assert.deepEqual(out, [
    {nome: "Sem foto", quantidade: 2},
    {nome: "Apagado", quantidade: 1},
    {nome: "Sem id", quantidade: 1},
  ]);
});

test("produto apagado depois do pedido: a imagem continua (copiada do espelho), sem ler produtos", async () => {
  const docs = new Map([
    [mirrorPath(), {itensResumo: [{nome: "Anel Pedra Lux", quantidade: 1, imagem: IMG_ANEL}]}],
  ]);
  const db = fakeDb(docs);
  const out = await run(db, [itemAnel], {isNewOrder: false, dataCriacao: ts(NOW - 3 * 24 * 3600 * 1000)});
  assert.deepEqual(out, [{nome: "Anel Pedra Lux", quantidade: 1, imagem: IMG_ANEL}]);
  assert.deepEqual(db.reads, [mirrorPath()]);
});

test("produto editado depois do pedido: o espelho mantém a imagem do momento do pedido", async () => {
  const docs = catalogo();
  docs.set(produtoPath(LOJA_A, "prod-anel"), {imagens: [storage(LOJA_A, "anel%2Fnova.jpg")]});
  docs.set(mirrorPath(), {itensResumo: [{nome: "Anel Pedra Lux", quantidade: 1, imagem: IMG_ANEL}]});
  const db = fakeDb(docs);
  const out = await run(db, [itemAnel], {isNewOrder: false, dataCriacao: ts(NOW - 60 * 1000)});
  assert.equal(out[0].imagem, IMG_ANEL);
  assert.deepEqual(db.reads, [mirrorPath()]);
});

test("pedido legado (fora da janela, espelho sem imagem): continua sem imagem e não lê produtos", async () => {
  const docs = catalogo();
  docs.set(mirrorPath(), {itensResumo: [{nome: "Anel", quantidade: 1}]});
  const db = fakeDb(docs);
  const out = await run(db, [{nome: "Anel", quantidade: 1, productId: "prod-anel"}], {
    isNewOrder: false,
    dataCriacao: ts(NOW - PUBLIC_ORDER_IMAGE_DERIVATION_WINDOW_MS - 1),
  });
  assert.deepEqual(out, [{nome: "Anel", quantidade: 1}]);
  assert.deepEqual(db.reads, [mirrorPath()]);
});

test("update logo após a criação (eventos fora de ordem) ainda obtém a imagem", async () => {
  const db = fakeDb(catalogo());
  const out = await run(db, [itemAnel], {isNewOrder: false, dataCriacao: ts(NOW - 30 * 1000)});
  assert.equal(out[0].imagem, IMG_ANEL);
});

test("cross-tenant: só lê produtos da loja do pedido; IDs com path são ignorados", async () => {
  const db = fakeDb(catalogo());
  const out = await run(db, [
    {nome: "Segredo", quantidade: 1, productId: "prod-segredo", imagemSnapshot: IMG_LOJA_B},
    {nome: "Path", quantidade: 1, productId: "../../loja-b/produtos/prod-segredo"},
    {nome: "Barra", quantidade: 1, productId: "loja-b/produtos/prod-segredo"},
    {nome: "Reservado", quantidade: 1, productId: "__name__"},
  ]);
  assert.deepEqual(out.map((i) => i.imagem), [undefined, undefined, undefined, undefined]);
  assert.ok(db.reads.every((p) => p.startsWith(`lojas/${LOJA_A}/`)), db.reads.join(","));
  assert.deepEqual(db.reads, [mirrorPath(), produtoPath(LOJA_A, "prod-segredo")]);
  assert.equal(isSafeProductDocId("prod-anel"), true);
  for (const bad of ["", " a", "a/b", ".", "..", "__x__", "x".repeat(201), 12, null]) {
    assert.equal(isSafeProductDocId(bad), false, String(bad));
  }
});

test("privacidade: nada além de nome/quantidade/imagem sai para o espelho", async () => {
  const db = fakeDb(catalogo());
  const out = await run(db, [{...itemEstojo, custo: 10, margem: 0.5, fornecedor: "F", ownerUid: "u1", cor: "Rosa"}]);
  for (const item of out) {
    assert.deepEqual(Object.keys(item).filter((k) => !["nome", "quantidade", "imagem"].includes(k)), []);
  }
  const json = JSON.stringify(out);
  for (const leak of ["custo", "margem", "fornecedor", "ownerUid", "prod-estojo", "39.9", "quantidade\":4"]) {
    assert.ok(!json.includes(leak), leak);
  }
});

test("alinhamento com itensResumo: itens sem nome não deslocam as imagens", async () => {
  const db = fakeDb(catalogo());
  const itens = [{nome: " ", quantidade: 1, productId: "prod-estojo"}, null, itemAnel];
  const out = await run(db, itens);
  assert.deepEqual(out, [{nome: "Anel Pedra Lux", quantidade: 1, imagem: IMG_ANEL}]);
});

test("itensResumo divergente dos itens: nenhuma imagem é atribuída", async () => {
  const db = fakeDb(catalogo());
  const out = await run(db, [itemAnel, itemEstojo], {
    itensResumo: [{nome: "Outro", quantidade: 1}, {nome: "Anel Pedra Lux", quantidade: 1}],
  });
  assert.deepEqual(out, [{nome: "Outro", quantidade: 1}, {nome: "Anel Pedra Lux", quantidade: 1}]);
});

test("espelho anterior: imagem de outro item na mesma posição ou insegura não é copiada", async () => {
  const docs = new Map([
    [mirrorPath(), {itensResumo: [
      {nome: "Outro item", quantidade: 1, imagem: IMG_ESTOJO},
      {nome: "Anel Pedra Lux", quantidade: 1, imagem: "javascript:alert(1)"},
    ]}],
  ]);
  const db = fakeDb(docs);
  const out = await run(db, [itemAnel, {...itemEstojo, nome: "Anel Pedra Lux"}], {
    isNewOrder: false,
    dataCriacao: ts(NOW - 2 * PUBLIC_ORDER_IMAGE_DERIVATION_WINDOW_MS),
  });
  assert.deepEqual(out.map((i) => i.imagem), [undefined, undefined]);
});

test("falha ao ler produtos não bloqueia o espelho: itens saem sem imagem", async () => {
  const db = fakeDb(catalogo(), {failGetAll: true});
  const out = await run(db, [itemAnel]);
  assert.deepEqual(out, [{nome: "Anel Pedra Lux", quantidade: 1}]);
});

test("um único getAll com IDs sem repetição", async () => {
  const db = fakeDb(catalogo());
  const calls = [];
  const out = await resolvePublicOrderItemImages({
    itensResumo: resumoOf([itemAnel, {...itemAnel, quantidade: 2}]),
    itens: [itemAnel, {...itemAnel, quantidade: 2}],
    allowDerivation: true,
    loadProducts: async (ids) => {
      calls.push(ids);
      return new Map([["prod-anel", {imagens: [IMG_ANEL]}]]);
    },
  });
  assert.deepEqual(calls, [["prod-anel"]]);
  assert.deepEqual(out.map((i) => i.imagem), [IMG_ANEL, IMG_ANEL]);
  assert.equal(db.reads.length, 0);
});

test("sanitizePublicOrderImageUrl aceita só https absoluto e limpo", () => {
  assert.equal(sanitizePublicOrderImageUrl(` ${IMG_ANEL} `), IMG_ANEL);
  for (const bad of [
    "",
    null,
    42,
    "http://x.com/a.jpg",
    "data:image/png;base64,AA",
    "javascript:alert(1)",
    "//x.com/a.jpg",
    "/lojas/a.jpg",
    "https://user:pw@x.com/a.jpg",
    "https://x.com/a b.jpg",
    "https://x.com/a\".jpg",
    "https://x.com/<a>.jpg",
    `https://x.com/${"a".repeat(2050)}`,
  ]) {
    assert.equal(sanitizePublicOrderImageUrl(bad), "", String(bad).slice(0, 40));
  }
});

test("wiring: trigger usa o snapshot; espelho e portal mantêm o resto do payload", () => {
  const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
  const start = src.indexOf("export const syncPedidoStatusPublico");
  const end = src.indexOf("export const", start + 10);
  const trigger = src.slice(start, end);
  assert.match(trigger, /const payload = buildPedidoStatusPublico\(lojaId, pedidoId, afterData\);/);
  assert.match(trigger, /payload\.itensResumo = await withPublicOrderItemImages\(db, \{/);
  assert.match(trigger, /isNewOrder: !event\.data\?\.before\?\.exists,/);
  assert.match(trigger, /await mirrorRef\.set\(payload, \{ merge: false \}\);/);
  assert.match(trigger, /await upsertClientePortalFromPedido\(lojaId, pedidoId, afterData\);/);
  assert.equal((trigger.match(/payload\.\w+\s*=/g) || []).length, 1);

  const bStart = src.indexOf("function buildPedidoStatusPublico(");
  const builder = src.slice(bStart, src.indexOf("\n}\n", bStart));
  assert.match(builder, /nome: normalizeOptionalString\(item\?\.nome\) \|\| "",\n\s+quantidade: Number\(item\?\.quantidade\) \|\| 1,\n\s+\}\)\)/);
  assert.ok(!builder.includes("imagem"));
});
