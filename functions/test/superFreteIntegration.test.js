/**
 * node --test test/superFreteIntegration.test.js
 */

import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { HttpsError } from "firebase-functions/v2/https";

import {
  maskToken,
  detectLegacySuperFreteToken,
  stripSuperFreteLegacyFromPublic,
  fretesPublicWriteSafe,
  createSuperFreteHandlers,
  getSuperFreteApiBase,
  SUPERFRETE_API_BASE,
  SUPERFRETE_SANDBOX_BASE,
} from "../src/superFreteIntegration.js";
import { isRootAccountEmail } from "../src/rootAccounts.js";
import { makeSuperFreteMockDb } from "./mockSuperFreteDb.js";

const LOJA = "loja-sf-test";
const TOKEN = "sf_test_token_abcdefghijklmnop";
const UID = "owner_sf_uid";

function authReq(data = {}, uid = UID) {
  return {
    auth: { uid, token: { email: "owner@test.com" } },
    data,
  };
}

function anonReq(data = {}) {
  return { auth: null, data };
}

function makeHandlers(db, request, fetchImpl) {
  return createSuperFreteHandlers({
    db,
    canManageStoreConfigServerSide: async ({ lojaId, uid }) =>
      lojaId === LOJA && uid === UID,
    checkRateLimit: async () => {},
    getCallableIdentifier: () => "test-client",
    fetchWithTimeout: fetchImpl,
    collectionLojas: "lojas",
    request,
    overrides: fetchImpl ? { fetchWithTimeout: fetchImpl } : {},
  });
}

function okMeFetch() {
  return async () => ({
    status: 200,
    ok: true,
    async text() {
      return JSON.stringify({ name: "Loja Teste" });
    },
    async json() {
      return { name: "Loja Teste" };
    },
  });
}

function okQuoteFetch() {
  return async (url) => {
    if (String(url).includes("/me")) {
      return {
        status: 200,
        ok: true,
        async text() {
          return JSON.stringify({ name: "Loja Teste" });
        },
      };
    }
    return {
      status: 200,
      ok: true,
      async text() {
        return JSON.stringify([
          { id: 1, name: "PAC", price: 12.5, delivery_time: 5, company: { name: "Correios" } },
        ]);
      },
    };
  };
}

function invalidTokenFetch() {
  return async () => ({
    status: 401,
    ok: false,
    async text() {
      return "{}";
    },
  });
}

function unavailableFetch() {
  return async () => ({
    status: 503,
    ok: false,
    async text() {
      return "{}";
    },
  });
}

describe("helpers SuperFrete", () => {
  it("maskToken não expõe token completo", () => {
    assert.equal(maskToken(TOKEN), "••••mnop");
    assert.ok(!maskToken(TOKEN).includes(TOKEN.slice(0, -4)));
  });

  it("detectLegacySuperFreteToken encontra token público", () => {
    assert.equal(
      detectLegacySuperFreteToken({ superfrete: { token: "x" } }, {}),
      true,
    );
    assert.equal(detectLegacySuperFreteToken({}, { superfrete_token: "y" }), true);
    assert.equal(detectLegacySuperFreteToken({ integrations: { superfrete: { configured: true } } }, {}), false);
  });

  it("stripSuperFreteLegacyFromPublic remove token", () => {
    const cleaned = stripSuperFreteLegacyFromPublic({
      superfrete: { token: TOKEN, sandbox: true },
      superfrete_token: TOKEN,
    });
    assert.equal(cleaned.superfrete?.token, undefined);
    assert.equal(cleaned.superfrete_token, undefined);
    assert.equal(cleaned.superfrete?.sandbox, true);
  });

  it("fretesPublicWriteSafe bloqueia token", () => {
    assert.equal(fretesPublicWriteSafe({ superfrete: { token: "x" } }), false);
    assert.equal(
      fretesPublicWriteSafe({
        integrations: { superfrete: { configured: true, enabled: true } },
      }),
      true,
    );
  });

  it("getSuperFreteApiBase alterna produção e sandbox", () => {
    assert.equal(getSuperFreteApiBase(false), SUPERFRETE_API_BASE);
    assert.equal(getSuperFreteApiBase(true), SUPERFRETE_SANDBOX_BASE);
  });

  it("isRootAccountEmail reconhece contas root (regressão ROOT_EMAILS)", () => {
    assert.equal(isRootAccountEmail("masterpalm@gmail.com"), true);
    assert.equal(isRootAccountEmail("owner@test.com"), false);
  });
});

describe("superFreteTestConnection", () => {
  it("1. usuário sem login não configura", async () => {
    const db = makeSuperFreteMockDb();
    const h = makeHandlers(db, anonReq({ lojaId: LOJA, token: TOKEN }), okMeFetch());
    await assert.rejects(
      () => h.superFreteTestConnection(),
      (e) => e instanceof HttpsError && e.code === "unauthenticated",
    );
  });

  it("2. usuário sem permissão não configura outra loja", async () => {
    const db = makeSuperFreteMockDb();
    const h = makeHandlers(
      db,
      authReq({ lojaId: "outra-loja", token: TOKEN }),
      okMeFetch(),
    );
    await assert.rejects(
      () => h.superFreteTestConnection(),
      (e) => e instanceof HttpsError && e.code === "permission-denied",
    );
  });

  it("3. token válido validado sem aparecer em retorno", async () => {
    const db = makeSuperFreteMockDb();
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, token: TOKEN, sandbox: false }),
      okMeFetch(),
    );
    const res = await h.superFreteTestConnection();
    assert.equal(res.ok, true);
    assert.equal(res.provider, "superfrete");
    assert.equal(res.displayName, "Loja Teste");
    assert.equal("token" in res, false);
    assert.ok(!JSON.stringify(res).includes(TOKEN));
  });

  it("4. token inválido retorna erro seguro", async () => {
    const db = makeSuperFreteMockDb();
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, token: TOKEN }),
      invalidTokenFetch(),
    );
    await assert.rejects(
      () => h.superFreteTestConnection(),
      (e) =>
        e instanceof HttpsError
        && e.code === "permission-denied"
        && e.message.includes("inválido")
        && e.details?.code === "TOKEN_INVALIDO",
    );
  });

  it("4b. sandbox usa host sandbox.superfrete.com", async () => {
    const db = makeSuperFreteMockDb();
    let calledUrl = "";
    const fetchImpl = async (url) => {
      calledUrl = String(url);
      return {
        status: 200,
        ok: true,
        async text() {
          return JSON.stringify({ name: "Sandbox" });
        },
      };
    };
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, token: TOKEN, sandbox: true }),
      fetchImpl,
    );
    await h.superFreteTestConnection();
    assert.ok(calledUrl.startsWith(SUPERFRETE_SANDBOX_BASE));
    assert.ok(!calledUrl.includes("api.superfrete.com"));
  });
});

describe("superFreteSaveConfig", () => {
  let db;

  beforeEach(() => {
    db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true, ownerUid: UID } },
      fretes: {
        [LOJA]: {
          superfrete: { token: "legacy_exposed_token" },
          superfrete_token: "legacy_exposed_token",
        },
      },
      draftConfig: {
        [LOJA]: {
          frete_config: { superfrete_token: "legacy_exposed_token" },
        },
      },
    });
  });

  it("5. grava token apenas em fretes_secrets", async () => {
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, token: TOKEN, cepOrigem: "01310100", sandbox: false }),
      okMeFetch(),
    );
    const res = await h.superFreteSaveConfig();
    assert.equal(res.ok, true);
    assert.equal(res.maskedToken, maskToken(TOKEN));
    assert.ok(!JSON.stringify(res).includes(TOKEN));

    const secret = db.state.fretesSecrets[LOJA];
    assert.equal(secret.superfrete.token, TOKEN);
    assert.equal(db.state.fretes[LOJA].superfrete?.token, undefined);
    assert.equal(db.state.fretes[LOJA].superfrete_token, undefined);
  });

  it("6. documento público não recebe token", async () => {
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, token: TOKEN, cepOrigem: "01310100" }),
      okMeFetch(),
    );
    await h.superFreteSaveConfig();
    const pub = db.state.fretes[LOJA];
    assert.equal(pub.integrations?.superfrete?.configured, true);
    assert.ok(!JSON.stringify(pub).includes(TOKEN));
  });

  it("7. remove campos legados de token após salvar", async () => {
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, token: TOKEN, cepOrigem: "01310100" }),
      okMeFetch(),
    );
    await h.superFreteSaveConfig();
    const draft = db.state.draftConfig[LOJA];
    assert.equal(draft.frete_config?.superfrete_token, undefined);
  });
});

describe("superFreteGetConfigStatus", () => {
  it("8. retorna apenas máscara", async () => {
    const db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true } },
      fretesSecrets: {
        [LOJA]: { superfrete: { token: TOKEN, sandbox: false, lastValidationStatus: "ok" } },
      },
      fretes: {
        [LOJA]: { integrations: { superfrete: { configured: true, enabled: true } } },
      },
    });
    const h = makeHandlers(db, authReq({ lojaId: LOJA }), okMeFetch());
    const res = await h.superFreteGetConfigStatus();
    assert.equal(res.configured, true);
    assert.equal(res.maskedToken, maskToken(TOKEN));
    assert.ok(!JSON.stringify(res).includes(TOKEN));
  });

  it("9. legacyTokenNeedsRotation detectado sem retornar token", async () => {
    const db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true } },
      fretes: { [LOJA]: { superfrete: { token: "legacy_only" } } },
    });
    const h = makeHandlers(db, authReq({ lojaId: LOJA }), okMeFetch());
    const res = await h.superFreteGetConfigStatus();
    assert.equal(res.legacyTokenNeedsRotation, true);
    assert.equal(res.maskedToken, "••••????");
    assert.ok(!JSON.stringify(res).includes("legacy_only"));
  });
});

describe("superFreteQuote / calcularSuperFreteSecure", () => {
  it("10. superFreteQuote rejeita token no payload", async () => {
    const db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true } },
    });
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, token: TOKEN, destinationCep: "20040020" }),
      okQuoteFetch(),
    );
    await assert.rejects(
      () => h.superFreteQuote(),
      (e) => e instanceof HttpsError && e.code === "invalid-argument",
    );
  });

  it("11. superFreteQuote lê token somente do documento secreto", async () => {
    const db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true } },
      fretes: { [LOJA]: { cepOrigem: "01310100" } },
      fretesSecrets: { [LOJA]: { superfrete: { token: TOKEN } } },
    });
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, destinationCep: "20040020", peso: 500 }),
      okQuoteFetch(),
    );
    const res = await h.superFreteQuote();
    assert.equal(res.sucesso, true);
    assert.ok(Array.isArray(res.opcoes));
    assert.ok(!JSON.stringify(res).includes(TOKEN));
  });

  it("12. calcularSuperFrete antigo não aceita token de cliente", async () => {
    const db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true } },
      fretesSecrets: { [LOJA]: { superfrete: { token: TOKEN } } },
      fretes: { [LOJA]: { cepOrigem: "01310100" } },
    });
    const h = makeHandlers(
      db,
      authReq({
        lojaId: LOJA,
        token: TOKEN,
        cepOrigem: "01310100",
        cepDestino: "20040020",
        peso: 500,
      }),
      okQuoteFetch(),
    );
    await assert.rejects(
      () => h.calcularSuperFreteSecure(),
      (e) => e instanceof HttpsError && e.code === "invalid-argument",
    );
  });

  it("13. API indisponível retorna erro seguro", async () => {
    const db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true } },
      fretes: { [LOJA]: { cepOrigem: "01310100" } },
      fretesSecrets: { [LOJA]: { superfrete: { token: TOKEN } } },
    });
    const h = makeHandlers(
      db,
      authReq({ lojaId: LOJA, destinationCep: "20040020", peso: 500 }),
      unavailableFetch(),
    );
    await assert.rejects(
      () => h.superFreteQuote(),
      (e) => e instanceof HttpsError && e.code === "unavailable",
    );
  });

  it("14. logs não possuem token (retorno sanitizado)", async () => {
    const logs = [];
    const origInfo = console.info;
    const origWarn = console.warn;
    console.info = (...args) => logs.push(args.join(" "));
    console.warn = (...args) => logs.push(args.join(" "));

    try {
      const db = makeSuperFreteMockDb({
        lojas: { [LOJA]: { published: true } },
        fretes: { [LOJA]: { cepOrigem: "01310100" } },
        fretesSecrets: { [LOJA]: { superfrete: { token: TOKEN } } },
      });
      const h = makeHandlers(
        db,
        authReq({ lojaId: LOJA, destinationCep: "20040020", peso: 500 }),
        okQuoteFetch(),
      );
      await h.superFreteQuote();
      const blob = logs.join("\n");
      assert.ok(!blob.includes(TOKEN));
      assert.ok(!blob.includes("Authorization"));
    } finally {
      console.info = origInfo;
      console.warn = origWarn;
    }
  });

  it("15. cálculo público respeita rate limit (hook chamado)", async () => {
    let rateKey = null;
    const db = makeSuperFreteMockDb({
      lojas: { [LOJA]: { published: true } },
      fretes: { [LOJA]: { cepOrigem: "01310100" } },
      fretesSecrets: { [LOJA]: { superfrete: { token: TOKEN } } },
    });
    const h = createSuperFreteHandlers({
      db,
      canManageStoreConfigServerSide: async () => true,
      checkRateLimit: async (name, id) => {
        rateKey = `${name}:${id}`;
      },
      getCallableIdentifier: () => "anon-ip",
      fetchWithTimeout: okQuoteFetch(),
      collectionLojas: "lojas",
      request: authReq({ lojaId: LOJA, destinationCep: "20040020", peso: 500 }),
    });
    await h.superFreteQuote();
    assert.equal(rateKey, `superFreteQuote:anon-ip:${LOJA}`);
  });
});
