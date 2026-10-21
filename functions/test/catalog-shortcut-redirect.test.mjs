import {test} from "node:test";
import assert from "node:assert/strict";

import {
  CATALOG_SHORTCUT_DEFAULT_BASE,
  catalogShortcutBase,
  catalogShortcutKey,
  catalogShortcutRootUrl,
  catalogShortcutStoreUrl,
} from "../src/catalogShortcutRedirect.js";
import {legacyOrderRedirectTarget} from "../src/publicOrderRedirect.js";

const APP = "https://app.mastepalm.com.br";

/** Mesma ordem de decisão do handler redirectCatalogo, com o índice simulado. */
function resolveShortcut(path, query, webBaseEnv, index) {
  const order = legacyOrderRedirectTarget(path, query);
  if (order) return order;
  const base = catalogShortcutBase(webBaseEnv);
  const short = catalogShortcutKey(path);
  if (!short) return catalogShortcutRootUrl(base);
  const slug = index[short];
  return slug ? catalogShortcutStoreUrl(base, slug) : catalogShortcutRootUrl(base);
}

test("WEB_BASE_URL v4: /c/valid-slug vai para /loja/valid-slug no app", () => {
  const index = {"valid-slug": "valid-slug"};
  assert.equal(resolveShortcut("/c/valid-slug", {}, APP, index), `${APP}/loja/valid-slug`);
  assert.equal(resolveShortcut("/c/Valid-Slug", {}, APP, index), `${APP}/loja/valid-slug`);
  assert.equal(resolveShortcut("/c/", {}, APP, index), `${APP}/`);
  assert.equal(resolveShortcut("/c/desconhecido", {}, APP, index), `${APP}/`);
});

test("linkCurto resolve para o slug do índice (não para o texto da URL)", () => {
  const index = {nathy: "nathy-pratas-e-folheados"};
  assert.equal(resolveShortcut("/c/nathy", {}, APP, index), `${APP}/loja/nathy-pratas-e-folheados`);
});

test("base: só origem HTTPS; resto cai no app canônico", () => {
  assert.equal(CATALOG_SHORTCUT_DEFAULT_BASE, APP);
  assert.equal(catalogShortcutBase(APP), APP);
  assert.equal(catalogShortcutBase(`${APP}/`), APP);
  assert.equal(catalogShortcutBase(` ${APP} `), APP);
  assert.equal(catalogShortcutBase(`${APP}/qualquer/path?x=1`), APP);
  for (const bad of [undefined, null, "", "  ", "app.mastepalm.com.br", "http://app.mastepalm.com.br",
    "javascript:alert(1)", "//evil.com", "https://user:pw@evil.com", 42]) {
    assert.equal(catalogShortcutBase(bad), APP, String(bad));
  }
});

test("legado /c/<loja>?pedido=<id> continua indo para a página pública do pedido", () => {
  for (const base of [APP, "https://mastepalm.com.br", undefined]) {
    assert.equal(
      resolveShortcut("/c/nathy-pratas-e-folheados", {pedido: "0Lg9UdsMyGdR7yPDfVhC"}, base, {}),
      `${APP}/pedido/0Lg9UdsMyGdR7yPDfVhC?loja=nathy-pratas-e-folheados`,
    );
  }
});

test("pedido malformado cai no atalho de catálogo (sem abrir pedido)", () => {
  const index = {"loja-a": "loja-a"};
  for (const pedido of ["../x", "a b", "a/b", "https://evil.com", "%2F", ["p1", "p2"], ""]) {
    assert.equal(resolveShortcut("/c/loja-a", {pedido}, APP, index), `${APP}/loja/loja-a`, String(pedido));
  }
});

test("slug malformado vira um único segmento codificado em /loja/", () => {
  for (const slug of ["a/b", "../admin", "x?y=1", "x#frag", "a b", "loja-ção"]) {
    const url = new URL(catalogShortcutStoreUrl(APP, slug));
    assert.equal(url.origin, APP, slug);
    assert.equal(url.search, "", slug);
    assert.equal(url.hash, "", slug);
    const segs = url.pathname.split("/").filter(Boolean);
    assert.equal(segs.length, 2, slug);
    assert.equal(segs[0], "loja", slug);
    assert.equal(decodeURIComponent(segs[1]), slug, slug);
  }
});

test("tentativa de open redirect não sai do domínio do app", () => {
  const index = {
    "https://evil.com": "https://evil.com",
    "//evil.com": "//evil.com",
    "evil": "@evil.com",
  };
  for (const path of ["/c/https://evil.com", "/c//evil.com", "/c/evil", "/c/https:%2F%2Fevil.com",
    "/c/%2F%2Fevil.com", "/c/..%2F..%2F"]) {
    const target = new URL(resolveShortcut(path, {}, APP, index));
    assert.equal(target.origin, APP, path);
    assert.ok(target.pathname === "/" || target.pathname.startsWith("/loja/"), path);
  }
  for (const pedido of ["https://evil.com", "//evil.com"]) {
    const target = new URL(resolveShortcut("/c/https:%2F%2Fevil.com", {pedido}, APP, {}));
    assert.equal(target.origin, APP, pedido);
  }
});

test("WEB_BASE_URL v3 (apex) é o que o secret antigo produzia — documenta a causa", () => {
  assert.equal(
    resolveShortcut("/c/valid-slug", {}, "https://mastepalm.com.br", {"valid-slug": "valid-slug"}),
    "https://mastepalm.com.br/loja/valid-slug",
  );
});
