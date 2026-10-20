import {test} from "node:test";
import assert from "node:assert/strict";

import {APP_ORDER_BASE, legacyOrderRedirectTarget} from "../src/publicOrderRedirect.js";

test("link antigo do WhatsApp abre a página pública do pedido na mesma loja", () => {
  assert.equal(
    legacyOrderRedirectTarget("/c/nathy-pratas-e-folheados", {pedido: "0Lg9UdsMyGdR7yPDfVhC"}),
    "https://app.mastepalm.com.br/pedido/0Lg9UdsMyGdR7yPDfVhC?loja=nathy-pratas-e-folheados",
  );
});

test("preserva maiúsculas do lojaId (redirect de catálogo normaliza para minúsculas)", () => {
  const url = new URL(legacyOrderRedirectTarget("/c/LojaABC_1", {pedido: "abcDEF0123456789wxyz"}));
  assert.equal(url.searchParams.get("loja"), "LojaABC_1");
  assert.equal(url.pathname, "/pedido/abcDEF0123456789wxyz");
});

test("destino é sempre o app canônico (sem open redirect / sem domínio apex)", () => {
  const url = new URL(legacyOrderRedirectTarget("/c/loja-a", {pedido: "p1"}));
  assert.equal(url.origin, APP_ORDER_BASE);
  assert.equal(url.origin, "https://app.mastepalm.com.br");
});

test("sem ?pedido= mantém o redirect de catálogo (retorna null)", () => {
  assert.equal(legacyOrderRedirectTarget("/c/nathy-pratas-e-folheados", {}), null);
  assert.equal(legacyOrderRedirectTarget("/c/nathy-pratas-e-folheados", undefined), null);
  assert.equal(legacyOrderRedirectTarget("/c/loja", {pedido: ""}), null);
});

test("rejeita referências inválidas ou com caracteres de controle de URL", () => {
  for (const pedido of ["../x", "a b", "a/b", "a?b", "a#b", "a&b", "%2F", "x".repeat(129)]) {
    assert.equal(legacyOrderRedirectTarget("/c/loja-a", {pedido}), null, pedido);
  }
  for (const path of ["/c/", "/c", "/c/loja%2Fb", "/c/a/b", "/c/%E0%A4%A", "/c/loja%20a", "/c/https:%2F%2Fevil.com"]) {
    assert.equal(legacyOrderRedirectTarget(path, {pedido: "p1"}), null, path);
  }
});

test("pedido repetido na query (array) é rejeitado", () => {
  assert.equal(legacyOrderRedirectTarget("/c/loja-a", {pedido: ["p1", "p2"]}), null);
});

test("lojas diferentes com o mesmo id de pedido geram links distintos (tenant explícito)", () => {
  const a = new URL(legacyOrderRedirectTarget("/c/loja-a", {pedido: "MESMOID"}));
  const b = new URL(legacyOrderRedirectTarget("/c/loja-b", {pedido: "MESMOID"}));
  assert.equal(a.searchParams.get("loja"), "loja-a");
  assert.equal(b.searchParams.get("loja"), "loja-b");
  assert.notEqual(a.toString(), b.toString());
});
