/**
 * P0 — sendEmail deixa de ser relay aberto: tipos explícitos, usuário da loja autenticado,
 * destinatário/conteúdo derivados de registos autoritativos.
 * node --test test/emailContracts.test.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";
import { hasRaffleMarkers, RAFFLE_NOT_ACTIVE, CLAIMS_COLLECTION } from "../src/raffleNotificationGuard.js";
import { EMAIL_CLAIMS_COLLECTION, ABANDONED_CART_COOLDOWN_MS, escapeHtml } from "../src/emailContracts.js";
import {
  agora,
  LOJA,
  OUTRA,
  VENDA,
  NUM,
  EMAIL,
  createDb,
  seedStore,
  seedValid,
  seedPedido,
  raffleBody,
  emailHarness,
} from "./_emailFakeDb.mjs";

const orderBody = (over = {}) => ({ emailType: "order_confirmation", lojaId: LOJA, saleId: VENDA, ...over });
const raffleFields = { campaignId: "camp-1", participationId: "venda_venda-123", luckyNumber: NUM };

function seedCliente(db, id = "cli-1", over = {}) {
  seedStore(db);
  db._set(`lojas/${LOJA}/clientes/${id}`, {
    nome: "Maria Silva",
    email: EMAIL,
    telefone: "11988887777",
    carrinho: [{ nome: "Colar Letra", quantidade: 2, cor: "Dourado", tamanho: "" }],
    ...over,
  });
}

function seedCart(db, id = "cart-1", over = {}) {
  seedStore(db);
  db._set(`lojas/${LOJA}/carrinhos_abandonados/${id}`, {
    clienteNome: "Maria Silva",
    clienteEmail: EMAIL,
    clienteTelefone: "11988887777",
    produtos: [{ nome: "Brinco Gota", quantidade: 1 }],
    ...over,
  });
}

// ---------------------------------------------------------------- relay aberto fechado

test("ABUSE: e-mail arbitrário (to/subject/html) sem tipo ⇒ 400 e 0 envios, com ou sem token", async () => {
  const db = createDb();
  seedStore(db);
  for (const token of [null, "tok-owner"]) {
    const { sent, call } = emailHarness(db, { token });
    const r = await call({ to: "vitima@example.test", subject: "Promo", html: "<a href='https://phish.test'>clique</a>", lojaId: LOJA });
    assert.equal(r.status, 400);
    assert.equal(r.json.code, "EMAIL_TYPE_REQUIRED");
    assert.equal(sent.length, 0);
  }
});

test("ABUSE: tipo desconhecido / protótipo ⇒ 400", async () => {
  const db = createDb();
  seedStore(db);
  const { sent, call } = emailHarness(db);
  for (const emailType of ["generic", "raw", "__proto__", "constructor", "toString"]) {
    const r = await call({ emailType, lojaId: LOJA, to: EMAIL, text: "x" });
    assert.equal(r.status, 400, emailType);
  }
  assert.equal(sent.length, 0);
});

test("ABUSE: tipo válido com conteúdo cru (subject/html/text) ⇒ 400 RAW_CONTENT_NOT_ALLOWED", async () => {
  const db = createDb();
  seedPedido(db);
  const { sent, call } = emailHarness(db);
  for (const extra of [{ html: "<p>x</p>" }, { subject: "x" }, { text: "x" }]) {
    const r = await call(orderBody(extra));
    assert.equal(r.json.code, "RAW_CONTENT_NOT_ALLOWED");
  }
  assert.equal(sent.length, 0);
});

test("ABUSE: sem token / token inválido ⇒ 401; usuário de outra loja ⇒ 403", async () => {
  const db = createDb();
  seedPedido(db);
  seedStore(db, { loja: OUTRA, owner: "owner-b" });
  const { sent, call } = emailHarness(db);
  assert.equal((await call(orderBody(), { token: null })).status, 401);
  assert.equal((await call(orderBody(), { token: "forjado" })).status, 401);
  assert.equal((await call(orderBody(), { token: "tok-intruso" })).status, 403);
  assert.equal((await call(orderBody(), { token: "tok-outra" })).status, 403);
  assert.equal(sent.length, 0);
});

test("ABUSE: loja inexistente ⇒ 403", async () => {
  const db = createDb();
  const { sent, call } = emailHarness(db);
  const r = await call(orderBody({ lojaId: "nao-existe" }));
  assert.equal(r.status, 403);
  assert.equal(sent.length, 0);
});

test("ABUSE: lojaId/saleId com path traversal ⇒ 400", async () => {
  const db = createDb();
  seedPedido(db);
  const { sent, call } = emailHarness(db);
  assert.equal((await call(orderBody({ lojaId: "loja-a/pedidos" }))).status, 400);
  assert.equal((await call(orderBody({ saleId: "../x" }))).status, 400);
  assert.equal(sent.length, 0);
});

test("AUTH: vendedor ativo, membro admin e users.store_id autorizam; vendedor inativo não", async () => {
  const cases = [
    [(db) => db._set(`lojas/${LOJA}/vendedores/intruso-9`, { ativo: true, permissoes: { vendas: true } }), 200],
    [(db) => db._set(`lojas/${LOJA}/vendedores/intruso-9`, { ativo: false }), 403],
    [(db) => db._set(`lojas/${LOJA}/vendedores/intruso-9`, { ativo: true, permissoes: { produtos: true } }), 403],
    [(db) => db._set(`lojas/${LOJA}/members/intruso-9`, { role: "admin" }), 200],
    [(db) => db._set(`users/intruso-9`, { store_id: LOJA }), 403],
  ];
  for (const [seed, status] of cases) {
    const db = createDb();
    seedPedido(db);
    seed(db);
    const { call } = emailHarness(db, { token: "tok-intruso" });
    const r = await call(orderBody());
    assert.equal(r.status, status, seed.toString());
  }
});

// ---------------------------------------------------------------- order_confirmation

test("ORDER: confirmação normal vai para o e-mail do pedido, com total do pedido e sem sorteio", async () => {
  const db = createDb();
  seedPedido(db, { over: { cupomRoleta: { codigo: "ROLETA10", desconto: 10 } } });
  const { sent, call } = emailHarness(db);
  const r = await call(orderBody());
  assert.equal(r.status, 200);
  assert.equal(r.json.sent, true);
  assert.equal(r.json.raffleIncluded, false);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, EMAIL);
  assert.equal(sent[0].from, '"Loja A" <smtp@example.test>');
  assert.equal(sent[0].subject, "✅ Pedido confirmado - Loja A");
  assert.ok(sent[0].html.includes("R$ 129.90"));
  assert.ok(sent[0].html.includes("ROLETA10"));
  assert.equal(hasRaffleMarkers(sent[0].subject, sent[0].html), false);
});

test("ORDER: destinatário diferente do pedido ⇒ 422; pedido inexistente ⇒ 404; sem e-mail ⇒ 422", async () => {
  const db = createDb();
  seedPedido(db);
  seedPedido(db, { id: "ped-sem-email", venda: "venda-2", over: { cliente: { nome: "X" } } });
  const { sent, call } = emailHarness(db);
  assert.equal((await call(orderBody({ to: "atacante@example.test" }))).json.code, "RECIPIENT_MISMATCH");
  assert.equal((await call(orderBody({ saleId: "venda-x" }))).status, 404);
  assert.equal((await call(orderBody({ saleId: "venda-2" }))).json.code, "RECIPIENT_NOT_AVAILABLE");
  assert.equal(sent.length, 0);
});

test("ORDER: pedido marcado com outra loja ⇒ 403 CROSS_TENANT", async () => {
  const db = createDb();
  seedPedido(db, { over: { lojaId: OUTRA } });
  const { sent, call } = emailHarness(db);
  const r = await call(orderBody());
  assert.equal(r.json.code, "CROSS_TENANT");
  assert.equal(sent.length, 0);
});

test("ORDER: retry do mesmo pedido não duplica; falha SMTP libera e o retry envia", async () => {
  const db = createDb();
  seedPedido(db);
  let fail = true;
  const { sent, call } = emailHarness(db, { failSend: () => fail });
  await assert.rejects(call(orderBody()), /smtp down/);
  assert.equal(db._count(`${EMAIL_CLAIMS_COLLECTION}/`), 0);
  fail = false;
  assert.equal((await call(orderBody())).json.sent, true);
  const r = await call(orderBody());
  assert.equal(r.json.duplicate, true);
  assert.equal(r.json.code, "EMAIL_ALREADY_SENT");
  assert.equal(sent.length, 1);
});

test("ORDER + sorteio válido ⇒ número incluído uma vez; WhatsApp/CampaignEngine não reenviam o e-mail", async () => {
  const db = createDb();
  seedValid(db);
  seedPedido(db);
  const { sent, call } = emailHarness(db);
  const r = await call(orderBody(raffleFields));
  assert.equal(r.json.raffleIncluded, true);
  assert.ok(sent[0].html.includes(NUM));
  assert.ok(sent[0].subject.startsWith("🎉 Parabéns! Você está concorrendo"));
  const again = await call(raffleBody());
  assert.equal(again.json.duplicate, true);
  assert.equal(sent.length, 1);
  assert.equal(db._count(`${CLAIMS_COLLECTION}/`), 1);
});

test("ORDER + sorteio NÃO verificado (zero campanha / número forjado) ⇒ confirmação sem sorteio", async () => {
  for (const seed of [
    (db) => seedPedido(db),
    (db) => {
      seedValid(db);
      seedPedido(db);
    },
  ]) {
    const db = createDb();
    seed(db);
    const { sent, call } = emailHarness(db);
    const r = await call(orderBody({ ...raffleFields, luckyNumber: "77777" }));
    assert.equal(r.json.sent, true);
    assert.equal(r.json.raffleIncluded, false);
    assert.equal(r.json.raffleCode, RAFFLE_NOT_ACTIVE);
    assert.equal(hasRaffleMarkers(sent[0].subject, sent[0].html), false);
    assert.ok(!sent[0].html.includes("77777"));
    assert.ok(!sent[0].html.includes(NUM));
  }
});

test("ORDER: nome do cliente é escapado (sem HTML injetado)", async () => {
  const db = createDb();
  seedPedido(db, { over: { cliente: { nome: "<img src=x onerror=alert(1)>", email: EMAIL } } });
  const { sent, call } = emailHarness(db);
  await call(orderBody());
  assert.ok(!sent[0].html.includes("<img"));
  assert.ok(sent[0].html.includes(escapeHtml("<img src=x onerror=alert(1)>")));
});

// ---------------------------------------------------------------- abandoned_cart_reminder

test("CART: lembrete por clienteId usa e-mail, nome e itens do cliente", async () => {
  const db = createDb();
  seedCliente(db);
  const { sent, call } = emailHarness(db);
  const r = await call({ emailType: "abandoned_cart_reminder", lojaId: LOJA, clienteId: "cli-1" });
  assert.equal(r.status, 200);
  assert.equal(r.json.to, EMAIL);
  assert.equal(sent[0].to, EMAIL);
  assert.equal(sent[0].subject, "Você deixou itens no carrinho - Loja A");
  assert.ok(sent[0].text.includes("2x Colar Letra (cor Dourado)"));
  assert.ok(sent[0].text.includes(`https://app.mastepalm.com.br/loja/${LOJA}`));
  assert.equal(hasRaffleMarkers(sent[0].subject, sent[0].html, sent[0].text), false);
});

test("CART: lembrete por cartId com link do catálogo e cooldown por carrinho", async () => {
  const db = createDb();
  seedCart(db);
  const { sent, call } = emailHarness(db);
  const link = `https://app.mastepalm.com.br/loja/${LOJA}?cart=cart-1`;
  const body = { emailType: "abandoned_cart_reminder", lojaId: LOJA, cartId: "cart-1", link };
  assert.equal((await call(body)).json.sent, true);
  assert.ok(sent[0].text.includes(link));
  const r2 = await call(body);
  assert.equal(r2.status, 429);
  assert.equal(r2.json.code, "EMAIL_COOLDOWN");
  const depois = new Date(agora.getTime() + ABANDONED_CART_COOLDOWN_MS + 1000);
  assert.equal((await call(body, { agora: depois })).json.sent, true);
  assert.equal(sent.length, 2);
});

test("CART: destinatário arbitrário é recusado; e-mail sem cadastro só se for cliente da loja com o mesmo telefone", async () => {
  const db = createDb();
  seedCart(db, "cart-1");
  seedCart(db, "cart-2", { clienteEmail: "", email: "" });
  const { sent, call } = emailHarness(db);
  const base = { emailType: "abandoned_cart_reminder", lojaId: LOJA };
  assert.equal((await call({ ...base, cartId: "cart-1", to: "outro@example.test" })).json.code, "RECIPIENT_MISMATCH");
  assert.equal((await call({ ...base, cartId: "cart-2", to: "vitima@example.test" })).json.code, "RECIPIENT_NOT_VERIFIED");
  assert.equal((await call({ ...base, cartId: "cart-2" })).json.code, "RECIPIENT_NOT_AVAILABLE");
  db._set(`lojas/${LOJA}/clientes/cli-9`, { email: "maria2@example.test", telefone: "+55 (11) 98888-7777" });
  const ok = await call({ ...base, cartId: "cart-2", to: "Maria2@Example.test" });
  assert.equal(ok.json.sent, true);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, "maria2@example.test");
});

test("CART: link fora do catálogo ⇒ 400; domínio próprio ativo da loja ⇒ aceito", async () => {
  const db = createDb();
  seedCart(db);
  const { sent, call } = emailHarness(db);
  const base = { emailType: "abandoned_cart_reminder", lojaId: LOJA, cartId: "cart-1" };
  for (const link of ["https://phish.test/loja", "http://app.mastepalm.com.br/loja/x", "https://user:pw@app.mastepalm.com.br/loja", "javascript:alert(1)", "https://app.mastepalm.com.br/admin"]) {
    assert.equal((await call({ ...base, link })).json.code, "INVALID_LINK", link);
  }
  db._set(`lojas/${LOJA}/config/config`, { published: { dominioCatalogo: "loja.example.test", dominioStatus: "ativo" } });
  assert.equal((await call({ ...base, link: "https://loja.example.test/?cart=cart-1" })).json.sent, true);
  assert.equal(sent.length, 1);
});

test("CART: domínio próprio não ativo é recusado", async () => {
  const db = createDb();
  seedCart(db);
  db._set(`lojas/${LOJA}/config/config`, { dominioCatalogo: "loja.example.test", dominioStatus: "dns_ok" });
  const { sent, call } = emailHarness(db);
  const r = await call({ emailType: "abandoned_cart_reminder", lojaId: LOJA, cartId: "cart-1", link: "https://loja.example.test/" });
  assert.equal(r.json.code, "INVALID_LINK");
  assert.equal(sent.length, 0);
});

test("CART: carrinho vazio / inexistente ⇒ não envia", async () => {
  const db = createDb();
  seedCart(db, "cart-1", { produtos: [] });
  const { sent, call } = emailHarness(db);
  const base = { emailType: "abandoned_cart_reminder", lojaId: LOJA };
  assert.equal((await call({ ...base, cartId: "cart-1" })).json.code, "CART_EMPTY");
  assert.equal((await call({ ...base, cartId: "nao-existe" })).status, 404);
  assert.equal((await call({ ...base })).status, 400);
  assert.equal(sent.length, 0);
});

test("CART: falha SMTP restaura o cooldown anterior", async () => {
  const db = createDb();
  seedCart(db);
  let fail = true;
  const { sent, call } = emailHarness(db, { failSend: () => fail });
  const body = { emailType: "abandoned_cart_reminder", lojaId: LOJA, cartId: "cart-1" };
  await assert.rejects(call(body), /smtp down/);
  assert.equal(db._count(`${EMAIL_CLAIMS_COLLECTION}/`), 0);
  fail = false;
  assert.equal((await call(body)).json.sent, true);
  assert.equal(sent.length, 1);
});

test("CART: itens com HTML são escapados", async () => {
  const db = createDb();
  seedCart(db, "cart-1", { produtos: [{ nome: "<script>x</script>", quantidade: 1 }] });
  const { sent, call } = emailHarness(db);
  await call({ emailType: "abandoned_cart_reminder", lojaId: LOJA, cartId: "cart-1" });
  assert.ok(!sent[0].html.includes("<script>"));
});
