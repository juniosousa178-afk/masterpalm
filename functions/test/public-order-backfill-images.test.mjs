import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

import {buildPedidoStatusPublico as buildStatusBackfill} from "../backfill_pedido_status_publico.js";
import {
  buildPedidoStatusPublico as buildFontesBackfill,
  runPedidoStatusPublico,
} from "../backfill_fontes_cliente_pedidos.js";
import {preservePublicOrderItemImages} from "../src/publicOrderItemImages.js";

const exitCodeAfterImport = process.exitCode;

const LOJA = "loja-a";
const PEDIDO = "PedidoAaaaaaaaaaaaaa";
const IMG_ESTOJO =
  "https://firebasestorage.googleapis.com/v0/b/masterpalm-58c46.appspot.com/o/lojas%2Floja-a%2Fprodutos%2Festojo%2F00_1.jpg?alt=media&token=t1";
const IMG_ANEL =
  "https://firebasestorage.googleapis.com/v0/b/masterpalm-58c46.appspot.com/o/lojas%2Floja-a%2Fprodutos%2Fanel%2F00_1.jpg?alt=media&token=t2";
const CART_IMG = "https://evil.example/tracker.png";

const prePedido = (overrides = {}) => ({
  status: "pendente",
  total: 189.8,
  dataCriacao: {seconds: 1, nanoseconds: 0},
  itens: [
    {productId: "prod-estojo", nome: "Estojo Veludo Rosa Anel/brinco/pingente/berloque", quantidade: 1, imagemSnapshot: CART_IMG},
    {productId: "prod-anel", nome: "Anel Pedra Lux", quantidade: 2, imagem: CART_IMG},
  ],
  ...overrides,
});

const mirrorItems = (imgs) => [
  {nome: "Estojo Veludo Rosa Anel/brinco/pingente/berloque", quantidade: 1, ...(imgs[0] ? {imagem: imgs[0]} : {})},
  {nome: "Anel Pedra Lux", quantidade: 2, ...(imgs[1] ? {imagem: imgs[1]} : {})},
];

const builders = [
  ["backfill_pedido_status_publico", buildStatusBackfill],
  ["backfill_fontes_cliente_pedidos", buildFontesBackfill],
];

for (const [name, build] of builders) {
  test(`${name}: imagem existente sobrevive ao rebuild`, () => {
    const out = build(LOJA, PEDIDO, prePedido(), mirrorItems([IMG_ESTOJO, IMG_ANEL]));
    assert.deepEqual(out.itensResumo, mirrorItems([IMG_ESTOJO, IMG_ANEL]));
  });

  test(`${name}: item legado sem imagem continua válido e sem campo imagem`, () => {
    const out = build(LOJA, PEDIDO, prePedido(), mirrorItems([null, null]));
    assert.deepEqual(out.itensResumo, mirrorItems([null, null]));
    for (const item of out.itensResumo) assert.deepEqual(Object.keys(item), ["nome", "quantidade"]);
    const semEspelho = build(LOJA, PEDIDO, prePedido());
    assert.deepEqual(semEspelho.itensResumo, mirrorItems([null, null]));
  });

  test(`${name}: imagem inválida/insegura não é introduzida`, () => {
    for (const bad of [
      "http://firebasestorage.googleapis.com/x.jpg",
      "javascript:alert(1)",
      "https://user:pw@host.example/x.jpg",
      'https://host.example/x.jpg" onerror="x',
      "data:image/png;base64,AAAA",
      "//host.example/x.jpg",
      42,
    ]) {
      const out = build(LOJA, PEDIDO, prePedido(), mirrorItems([bad, bad]));
      assert.deepEqual(out.itensResumo, mirrorItems([null, null]), String(bad));
    }
  });

  test(`${name}: imagem do carrinho (pré-pedido) nunca entra no espelho`, () => {
    const out = build(LOJA, PEDIDO, prePedido());
    assert.ok(!JSON.stringify(out).includes(CART_IMG));
  });

  test(`${name}: item trocado de posição/nome não herda imagem`, () => {
    const trocado = [mirrorItems([IMG_ANEL, IMG_ESTOJO])[1], mirrorItems([IMG_ANEL, IMG_ESTOJO])[0]];
    const out = build(LOJA, PEDIDO, prePedido(), trocado);
    assert.deepEqual(out.itensResumo, mirrorItems([null, null]));
  });

  test(`${name}: só nome/quantidade/imagem por item (allowlist)`, () => {
    const prev = mirrorItems([IMG_ESTOJO, IMG_ANEL]).map((i) => ({...i, preco: 99, productId: "x", custo: 1}));
    const out = build(LOJA, PEDIDO, prePedido(), prev);
    for (const item of out.itensResumo) {
      assert.deepEqual(Object.keys(item).sort(), ["imagem", "nome", "quantidade"]);
    }
  });
}

test("preservePublicOrderItemImages: >50 itens não carrega imagens (determinístico)", () => {
  const resumo = Array.from({length: 51}, (_, i) => ({nome: `Item ${i}`, quantidade: 1}));
  const prev = resumo.map((r) => ({...r, imagem: IMG_ANEL}));
  const out = preservePublicOrderItemImages(resumo, prev);
  assert.equal(out.length, 51);
  assert.ok(out.every((i) => !("imagem" in i)));
});

function fakeDb(docs) {
  const writes = [];
  const reads = [];
  const ref = (path) => ({
    path,
    id: path.split("/").pop(),
    collection: (c) => col(`${path}/${c}`),
    get: async () => {
      reads.push(path);
      return {id: path.split("/").pop(), exists: docs.has(path), data: () => docs.get(path)};
    },
    set: async (data, opts) => {
      writes.push({path, data, opts});
    },
  });
  const col = (path) => {
    const query = {
      doc: (id) => ref(`${path}/${id}`),
      orderBy: () => query,
      limit: () => query,
      startAfter: () => query,
      get: async () => {
        const prefix = `${path}/`;
        const found = [...docs.keys()]
          .filter((k) => k.startsWith(prefix) && !k.slice(prefix.length).includes("/"))
          .sort()
          .map((k) => ({id: k.slice(prefix.length), ref: ref(k), data: () => docs.get(k)}));
        return {empty: found.length === 0, docs: found};
      },
    };
    return query;
  };
  return {writes, reads, collection: (c) => col(c)};
}

const prePath = (id) => `lojas/${LOJA}/pre_pedidos/${id}`;
const mirPath = (id) => `lojas/${LOJA}/pedido_status_publico/${id}`;

test("backfill_fontes modo pedido-status-publico: espelho com foto e dados iguais não é regravado", async () => {
  const pre = prePedido();
  const mirror = {...buildFontesBackfill(LOJA, PEDIDO, pre), itensResumo: mirrorItems([IMG_ESTOJO, IMG_ANEL])};
  const db = fakeDb(new Map([[prePath(PEDIDO), pre], [mirPath(PEDIDO), mirror]]));
  const stats = await runPedidoStatusPublico({db, lojaId: LOJA, limit: 10, startAfter: "", dryRun: false});
  assert.equal(stats.skipped, 1);
  assert.equal(stats.updated, 0);
  assert.equal(db.writes.length, 0);
});

test("backfill_fontes modo pedido-status-publico: status mudou, regrava mantendo a foto", async () => {
  const pre = prePedido({status: "enviado"});
  const mirror = {...buildFontesBackfill(LOJA, PEDIDO, prePedido()), itensResumo: mirrorItems([IMG_ESTOJO, IMG_ANEL])};
  const db = fakeDb(new Map([[prePath(PEDIDO), pre], [mirPath(PEDIDO), mirror]]));
  const stats = await runPedidoStatusPublico({db, lojaId: LOJA, limit: 10, startAfter: "", dryRun: false});
  assert.equal(stats.updated, 1);
  assert.equal(db.writes.length, 1);
  assert.equal(db.writes[0].data.status, "enviado");
  assert.deepEqual(db.writes[0].data.itensResumo, mirrorItems([IMG_ESTOJO, IMG_ANEL]));
  assert.ok(!db.reads.some((p) => p.includes("/produtos/") || p.includes("estoque") || p.includes("draft")));
});

test("backfill_fontes modo pedido-status-publico: legado sem foto e espelho ausente ficam sem foto", async () => {
  const db = fakeDb(new Map([
    [prePath("P1"), prePedido({status: "enviado"})],
    [mirPath("P1"), {...buildFontesBackfill(LOJA, "P1", prePedido()), itensResumo: mirrorItems([null, null])}],
    [prePath("P2"), prePedido()],
  ]));
  const stats = await runPedidoStatusPublico({db, lojaId: LOJA, limit: 10, startAfter: "", dryRun: false});
  assert.equal(stats.updated, 1);
  assert.equal(stats.created, 1);
  for (const w of db.writes) {
    assert.deepEqual(w.data.itensResumo, mirrorItems([null, null]));
    assert.ok(!JSON.stringify(w.data).includes(CART_IMG));
  }
});

test("backfill_fontes modo pedido-status-publico: foto inválida existente é removida, não propagada", async () => {
  const db = fakeDb(new Map([
    [prePath(PEDIDO), prePedido()],
    [mirPath(PEDIDO), {...buildFontesBackfill(LOJA, PEDIDO, prePedido()), itensResumo: mirrorItems(["javascript:alert(1)", IMG_ANEL])}],
  ]));
  await runPedidoStatusPublico({db, lojaId: LOJA, limit: 10, startAfter: "", dryRun: false});
  assert.equal(db.writes.length, 1);
  assert.deepEqual(db.writes[0].data.itensResumo, mirrorItems([null, IMG_ANEL]));
});

test("backfill_fontes dry-run não escreve", async () => {
  const db = fakeDb(new Map([[prePath(PEDIDO), prePedido({status: "enviado"})], [mirPath(PEDIDO), {itensResumo: mirrorItems([IMG_ESTOJO, null])}]]));
  const stats = await runPedidoStatusPublico({db, lojaId: LOJA, limit: 10, startAfter: "", dryRun: true});
  assert.equal(stats.updated, 1);
  assert.equal(db.writes.length, 0);
});

test("backfill_pedido_status_publico nunca regrava espelho existente", () => {
  const src = readFileSync(new URL("../backfill_pedido_status_publico.js", import.meta.url), "utf8");
  const skip = src.indexOf("if (publicSnap.exists)");
  const build = src.indexOf("buildPedidoStatusPublico(args.lojaId");
  assert.ok(skip > 0 && build > skip, "skip de espelho existente deve vir antes do build");
});

test("importar os scripts de backfill não executa main()", () => {
  assert.notEqual(exitCodeAfterImport, 1);
});
