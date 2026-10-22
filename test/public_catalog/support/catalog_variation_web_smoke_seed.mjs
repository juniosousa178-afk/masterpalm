// Fixtures do catálogo público para o smoke de variações (somente emulador).
// FIRESTORE_EMULATOR_HOST=127.0.0.1:8187 node test/public_catalog/support/catalog_variation_web_smoke_seed.mjs
import {createRequire} from "node:module";

const require = createRequire(new URL("../../../functions/package.json", import.meta.url));
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST obrigatório: este seed só roda no emulador.");
  process.exit(1);
}

const PROJECT_ID = "demo-masterpalm-catalog-variations";
const img = id => `https://picsum.photos/id/${id}/500/500`;
const grade = sizes => Object.fromEntries(sizes.map(s => [s, {"sem-cor": 2}]));
const ept = sizes => Object.fromEntries(sizes.map(s => [s, 2]));
const base = (id, nome, extra) => ({
  id,
  nome,
  slug: id,
  ativo: true,
  publicadoNoCatalogo: true,
  preco: 89.9,
  quantidade: 10,
  percentualDescontoPix: 5,
  divideSemJuros: true,
  maxParcelasSemJuros: 3,
  categoria: "Anéis",
  imagens: [img(1062)],
  ...extra,
});

const ring = ["12", "14", "16", "18", "20"];
const nine = ["10", "11", "12", "13", "14", "16", "18", "19", "20"];

export const PRODUCTS = [
  base("anel-solitario", "Anel Solitário Zircônia", {
    variacoes: grade(ring), estoquePorTamanho: ept(ring), tamanhos: ring,
    categorias: ["Anéis", "Promoções"], imagens: [img(1062)],
  }),
  base("pingente-cruz", "Pingente Cruz", {categoria: "Pingentes", imagens: [img(1080)]}),
  base("anel-aparador", "Anel Aparador Cravejado Zircônias Ródio Branco Extra Longo", {
    variacoes: grade(nine), estoquePorTamanho: ept(nine), preco: 129.9, imagens: [img(1069)],
  }),
  base("brinco-argola", "Brinco Argola Lisa", {
    variacoes: {"sem-tamanho": {"Prata": 3, "Rosa": 1}},
    estoquePorCor: {"Prata": 3, "Rosa": 1}, cores: ["Prata", "Rosa", "Dourado"],
    categoria: "Brincos", preco: 59.9, imagens: [img(1011)],
  }),
  base("anel-elos", "Anel Elos Coraçãozinho", {
    variacoes: {"16": {"Prata": 1}, "18": {"Rosa": 2}},
    estoquePorTamanho: {"16": 1, "18": 2}, preco: 37.9, imagens: [img(1025)],
  }),
  base("corrente-veneziana", "Corrente Veneziana", {
    estoquePorTamanho: {"40cm": 2, "45cm": 1, "50cm": 0}, tamanhos: ["40cm", "45cm", "50cm"],
    categoria: "Correntes", preco: 149.9, imagens: [img(1043)],
  }),
  base("pulseira-riviera", "Pulseira Riviera", {
    variacoes: grade(["17", "18", "19"]), estoquePorTamanho: ept(["17", "18", "19"]),
    percentualDescontoPix: 0, categoria: "Pulseiras", preco: 199.9, imagens: [img(1059)],
  }),
  base("colar-ponto-luz", "Colar Ponto de Luz", {
    percentualDescontoPix: 0, categoria: "Colares", preco: 79.9, imagens: [img(1074)],
  }),
];

const STORES = {
  "loja-smoke-classico": "padrao",
  "loja-smoke-minimal": "minimalista_nuvemshop",
};

const app = initializeApp({projectId: PROJECT_ID});
const db = getFirestore(app);
for (const [loja, layout] of Object.entries(STORES)) {
  const ref = db.collection("lojas").doc(loja);
  await ref.set({nome: `Smoke ${layout}`, name: `Smoke ${layout}`, slug: loja, ativo: true});
  await ref.collection("config").doc("config").set({
    nomeLoja: `Smoke ${layout}`,
    layoutCatalogo: layout,
    productCardSize: "medium",
    catalogoAtivo: true,
  });
  for (const p of PRODUCTS) {
    await ref.collection("produtos").doc(p.id).set({...p, lojaId: loja});
  }
}
console.log(`seeded ${PRODUCTS.length} produtos em ${Object.keys(STORES).join(", ")}`);
