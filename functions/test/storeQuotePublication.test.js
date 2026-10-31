/**
 * node --test test/storeQuotePublication.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { isStoreExplicitlyUnpublished, loadStoreForPublicQuote } from "../src/storeQuotePublication.js";
import { readMelhorEnvioSecrets } from "../src/melhorEnvioIntegration.js";
import { createSuperFreteHandlers } from "../src/superFreteIntegration.js";
import { makeDb } from "./shippingMemoryDb.js";

const STORE_A = "loja-a";
const STORE_B = "loja-b";

const load = (db, storeId) => loadStoreForPublicQuote({ db, collectionLojas: "lojas", storeId });

async function rejects(promise, code) {
  await assert.rejects(promise, (err) => {
    assert.equal(err.code, code);
    return true;
  });
}

describe("publicação da loja para cotação Melhor Envio", () => {
  it("published=true: permitido", async () => {
    const db = makeDb({ [`lojas/${STORE_A}`]: { published: true } });
    assert.deepEqual(await load(db, STORE_A), { published: true });
  });

  it("published ausente + publishedAt: permitido (modelo atual de publicação)", async () => {
    const db = makeDb({ [`lojas/${STORE_A}`]: { publishedAt: "2026-10-31T01:31:32.809Z", slug: STORE_A } });
    const data = await load(db, STORE_A);
    assert.equal(data.slug, STORE_A);
  });

  it("published=false: rejeitado", async () => {
    const db = makeDb({ [`lojas/${STORE_A}`]: { published: false, publishedAt: "2026-10-31T01:31:32.809Z" } });
    await rejects(load(db, STORE_A), "failed-precondition");
  });

  it("loja inexistente ou ID vazio: rejeitado", async () => {
    const db = makeDb({});
    await rejects(load(db, STORE_A), "not-found");
    await rejects(load(db, "  "), "invalid-argument");
  });

  it("outra loja: só lê o documento pedido e não usa token de outra loja", async () => {
    const db = makeDb({
      [`lojas/${STORE_A}`]: { published: true },
      [`lojas/${STORE_A}/config/fretes_secrets`]: { melhor_envio: { token: "me_token_loja_a_xxxxxxxx" } },
    });
    await rejects(load(db, STORE_B), "not-found");
    assert.deepEqual(db.reads, [`lojas/${STORE_B}`]);
    db.docs.set(`lojas/${STORE_B}`, { publishedAt: "2026-10-31T01:31:32.809Z" });
    await load(db, STORE_B);
    assert.equal(await readMelhorEnvioSecrets(db, "lojas", STORE_B), null);
  });

  it("predicado: só false explícito é despublicação", () => {
    assert.equal(isStoreExplicitlyUnpublished({ published: false }), true);
    for (const data of [{}, { published: true }, { published: null }, { published: "false" }, null, undefined]) {
      assert.equal(isStoreExplicitlyUnpublished(data), false);
    }
  });

  it("calcularMelhorEnvio usa a checagem alinhada e emite recibo melhor_envio", () => {
    const src = readFileSync(new URL("../index.js", import.meta.url), "utf8");
    const me = src.slice(src.indexOf("export const calcularMelhorEnvio"), src.indexOf("export const testarMelhorEnvioToken"));
    assert.match(me, /loadStoreForPublicQuote\(\{ db, collectionLojas: COLLECTION_LOJAS, storeId \}\)/);
    assert.doesNotMatch(me, /published !== true/);
    assert.match(me, /issueShippingQuoteReceipt\(\{[\s\S]*?provider: "melhor_envio"/);
  });

  it("mesma semântica da SuperFrete e das rules", async () => {
    const rules = readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8");
    assert.match(rules, /\(!\('published' in resource\.data\) \|\| resource\.data\.published == true\)/);
    for (const [data, allowed] of [[{ publishedAt: "x" }, true], [{ published: true }, true], [{ published: false }, false]]) {
      const db = makeDb({ [`lojas/${STORE_A}`]: data });
      const h = createSuperFreteHandlers({
        db,
        canManageStoreConfigServerSide: async () => false,
        checkRateLimit: async () => {},
        getCallableIdentifier: () => "anon",
        fetchWithTimeout: async () => { throw new Error("sem rede no teste"); },
        collectionLojas: "lojas",
        request: { auth: null, data: { lojaId: STORE_A, destinationCep: "20040020", peso: 1, altura: 1, largura: 1, comprimento: 1 } },
      });
      const sf = await h.superFreteQuote().then(() => "ok", (e) => e.code);
      const me = await load(db, STORE_A).then(() => "ok", (e) => e.code);
      assert.equal(me === "ok", allowed);
      assert.equal(sf === "failed-precondition", !allowed, `SuperFrete com ${JSON.stringify(data)}`);
    }
  });
});
