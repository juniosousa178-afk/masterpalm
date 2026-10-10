/**
 * P0 Nathy — sendEmail / sendWhatsAppOrderConfirmation não enviam sorteio sem participação autoritativa.
 */
import test from "node:test";
import assert from "node:assert/strict";
import {
  executeSendEmail,
  executeSendWhatsApp,
  stripRaffleLines,
  hasRaffleMarkers,
  RAFFLE_NOT_ACTIVE,
  CLAIMS_COLLECTION,
} from "../src/raffleNotificationGuard.js";

const agora = new Date("2026-10-09T12:00:00Z");
const dia = 24 * 3600 * 1000;
const LOJA = "loja-a";
const OUTRA = "loja-b";
const CAMP = "camp-1";
const VENDA = "venda-123";
const PART = "venda_venda-123";
const NUM = "48213";
const EMAIL = "cliente@example.test";
const FONE = "(11) 98888-7777";

function createDb({ failCampaignLookup = false } = {}) {
  const docs = new Map();
  const doc = (path) => ({
    id: path.split("/").pop(),
    path,
    collection: (name) => coll(`${path}/${name}`),
    async get() {
      const data = docs.get(path);
      return { exists: data !== undefined, id: path.split("/").pop(), data: () => (data ? { ...data } : undefined) };
    },
    async create(data) {
      if (docs.has(path)) {
        const e = new Error("6 ALREADY_EXISTS: Document already exists");
        e.code = 6;
        throw e;
      }
      docs.set(path, data);
    },
    async delete() {
      docs.delete(path);
    },
  });
  const coll = (path, filters = [], lim = Infinity) => ({
    doc: (id) => doc(`${path}/${id}`),
    where: (f, op, v) => coll(path, [...filters, [f, op, v]], lim),
    limit: (n) => coll(path, filters, n),
    async get() {
      if (failCampaignLookup && path.endsWith("/campanhas_sorteio")) throw new Error("unavailable");
      const prefix = `${path}/`;
      const out = [];
      for (const [p, data] of docs) {
        if (!p.startsWith(prefix) || p.slice(prefix.length).includes("/")) continue;
        const ok = filters.every(([f, op, v]) => (op === "in" ? v.includes(data[f]) : data[f] === v));
        if (ok) out.push({ id: p.slice(prefix.length), ref: doc(p), data: () => ({ ...data }) });
      }
      const sliced = out.slice(0, lim);
      return { docs: sliced, empty: sliced.length === 0, size: sliced.length };
    },
  });
  return {
    collection: (name) => coll(name),
    _set: (path, data) => docs.set(path, data),
    _has: (path) => docs.has(path),
    _count: (prefix) => [...docs.keys()].filter((k) => k.startsWith(prefix)).length,
  };
}

const campanha = (over = {}) => ({
  ativa: true,
  status: "aberta",
  nome: "Campanha Teste",
  dataInicio: new Date(agora.getTime() - dia),
  dataFim: new Date(agora.getTime() + dia),
  ...over,
});

const participante = (over = {}) => ({
  numeroSorte: NUM,
  campanhaId: CAMP,
  lojaId: LOJA,
  vendaId: VENDA,
  pedidoId: VENDA,
  status: "valido",
  clienteEmail: EMAIL,
  clienteTelefone: "11988887777",
  dataParticipacao: new Date(agora.getTime() - 3600 * 1000),
  ...over,
});

function seedValid(db, { loja = LOJA, camp = CAMP, part = PART, partData = {} } = {}) {
  db._set(`lojas/${loja}`, { nome: "Loja A" });
  db._set(`lojas/${loja}/campanhas_sorteio/${camp}`, campanha());
  db._set(`lojas/${loja}/campanhas_sorteio/${camp}/participantes/${part}`, participante({ lojaId: loja, campanhaId: camp, ...partData }));
}

const structured = (over = {}) => ({
  notificationType: "raffle_participation",
  lojaId: LOJA,
  saleId: VENDA,
  campaignId: CAMP,
  participationId: PART,
  luckyNumber: NUM,
  ...over,
});

// Payloads reais dos clientes antigos (sem campos estruturados).
const oldPosPagamentoEmail = {
  to: EMAIL,
  subject: "🎉 Parabéns! Você está concorrendo - Loja A",
  html: `<html><body><h1>🎉 Parabéns, Maria!</h1><div class="numero-sorte"><h2>🎲 Seu Número da Sorte:</h2><div class="numero">${NUM}</div></div><p>✅ Você está participando da nossa promoção!</p></body></html>`,
};
const oldCampaignEngineEmail = {
  to: EMAIL,
  subject: "Confirmacao de participacao - Campanha Campanha Teste",
  html: `<!DOCTYPE html><html><body><h2>Participacao registrada</h2><p>Sua participacao na campanha <strong>Campanha Teste</strong> foi registrada com sucesso!</p><p>${NUM}</p></body></html>`,
  lojaId: LOJA,
};
const oldPosPagamentoWhatsApp = `Olá Maria, aqui é o atendente virtual da *LOJA A*.

Vim te avisar que seu pedido foi realizado com sucesso e já está em preparo. 😊

*Nº do pedido* ped-9

*Itens:*
➡ 1x Colar Letra

*Total do pedido:* R$ 129,90

---
🎲 *Seu Número da Sorte:* *${NUM}*
✅ Você está participando da nossa promoção!

Obrigado por comprar conosco! 💜
`;
const oldPosPagamentoWhatsAppFallback = `
🎉 *Parabéns, Maria!*

Obrigado por sua compra na *Loja A*!

🎲 *Seu Número da Sorte:*
*${NUM}*

✅ Você está participando da nossa promoção!

Obrigado por comprar conosco! 💜
`;
const oldCampaignEngineWhatsApp = `Ola, Maria!

Sua participacao na campanha Campanha Teste foi registrada com sucesso.

Numero da sorte: ${NUM}

Guarde este numero com carinho.
Loja: Loja A
`;

function emailHarness(db) {
  const sent = [];
  const call = (body) =>
    executeSendEmail({
      db,
      body,
      input: {
        to: String(body.to || ""),
        subject: String(body.subject || ""),
        html: body.html != null ? String(body.html) : "",
        text: body.text != null ? String(body.text) : "",
        lojaId: String(body.lojaId || ""),
      },
      smtpUser: "smtp@example.test",
      sendMail: async (opts) => {
        sent.push(opts);
      },
      agora,
    });
  return { sent, call };
}

function whatsHarness(db) {
  const sent = [];
  const call = (body) =>
    executeSendWhatsApp({
      db,
      body,
      lojaId: body.lojaId,
      phone: body.phone,
      message: body.message,
      send: async (lojaId, phone, msg) => {
        sent.push({ lojaId, phone, msg });
      },
      agora,
    });
  return { sent, call };
}

// ---------------------------------------------------------------- cliente antigo, zero campanha

test("OLD_CLIENT: e-mail PosPagamento antigo sem campanha ⇒ EMAIL_SEND_COUNT=0, 200 RAFFLE_NOT_ACTIVE", async () => {
  const db = createDb();
  db._set(`lojas/${LOJA}`, { nome: "Loja A" });
  const { sent, call } = emailHarness(db);
  const r = await call(oldPosPagamentoEmail);
  assert.equal(r.status, 200);
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(r.json.sent, false);
  assert.equal(sent.length, 0);
});

test("OLD_CLIENT: mesmo payload antigo com lojaId e sem campanha ⇒ 0 envios", async () => {
  const db = createDb();
  const { sent, call } = emailHarness(db);
  const r = await call({ ...oldPosPagamentoEmail, lojaId: LOJA });
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(r.json.reason, "no_active_campaign");
  assert.equal(sent.length, 0);
});

test("OLD_CLIENT: e-mail CampaignEngine antigo sem campanha ⇒ 0 envios (200 evita fallback SMTP local)", async () => {
  const db = createDb();
  const { sent, call } = emailHarness(db);
  const r = await call(oldCampaignEngineEmail);
  assert.equal(r.status, 200);
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(sent.length, 0);
});

test("OLD_CLIENT: número aleatório não persistido mesmo com campanha válida ⇒ 0 envios", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = emailHarness(db);
  const fake = { ...oldCampaignEngineEmail, html: oldCampaignEngineEmail.html.replace(NUM, "77777") };
  const r = await call(fake);
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(sent.length, 0);
});

test("OLD_CLIENT: e-mail PosPagamento antigo sem lojaId é bloqueado mesmo com campanha válida", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = emailHarness(db);
  const r = await call(oldPosPagamentoEmail);
  assert.equal(r.json.reason, "legacy_missing_loja");
  assert.equal(sent.length, 0);
});

test("OLD_CLIENT: WhatsApp PosPagamento antigo sem campanha ⇒ envia só a confirmação do pedido, sem sorteio", async () => {
  const db = createDb();
  const { sent, call } = whatsHarness(db);
  const r = await call({ lojaId: LOJA, phone: FONE, message: oldPosPagamentoWhatsApp });
  assert.equal(r.status, 200);
  assert.equal(r.json.raffleRemoved, true);
  assert.equal(sent.length, 1);
  assert.equal(hasRaffleMarkers(sent[0].msg), false);
  assert.ok(!sent[0].msg.includes(NUM));
  assert.ok(sent[0].msg.includes("*Nº do pedido* ped-9"));
  assert.ok(sent[0].msg.includes("Total do pedido"));
});

test("OLD_CLIENT: WhatsApp fallback antigo sem campanha ⇒ sem número da sorte", async () => {
  const db = createDb();
  const { sent, call } = whatsHarness(db);
  await call({ lojaId: LOJA, phone: FONE, message: oldPosPagamentoWhatsAppFallback });
  assert.equal(sent.length, 1);
  assert.equal(hasRaffleMarkers(sent[0].msg), false);
  assert.ok(!sent[0].msg.includes(NUM));
});

test("OLD_CLIENT: WhatsApp CampaignEngine antigo sem campanha ⇒ 0 envios", async () => {
  const db = createDb();
  const { sent, call } = whatsHarness(db);
  const r = await call({ lojaId: LOJA, phone: FONE, message: oldCampaignEngineWhatsApp });
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(sent.length, 0);
});

// ---------------------------------------------------------------- campanha válida

test("VALID: participação persistida + campos estruturados ⇒ 1 envio; retry ⇒ sem duplicado", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = emailHarness(db);
  const body = { to: EMAIL, subject: "Confirmacao de participacao - Campanha Campanha Teste", html: `<p>${NUM}</p>`, ...structured() };
  const r1 = await call(body);
  assert.equal(r1.json.sent, true);
  const r2 = await call(body);
  assert.equal(r2.json.duplicate, true);
  assert.equal(r2.json.sent, false);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].from, '"Loja A" <smtp@example.test>');
  assert.equal(db._count(`${CLAIMS_COLLECTION}/`), 1);
});

test("VALID: falha SMTP libera a reserva e o retry envia uma vez", async () => {
  const db = createDb();
  seedValid(db);
  let fail = true;
  const sent = [];
  const call = () =>
    executeSendEmail({
      db,
      body: structured(),
      input: { to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, text: "", lojaId: LOJA },
      smtpUser: "smtp@example.test",
      sendMail: async (o) => {
        if (fail) throw new Error("smtp down");
        sent.push(o);
      },
      agora,
    });
  await assert.rejects(call(), /smtp down/);
  assert.equal(db._count(`${CLAIMS_COLLECTION}/`), 0);
  fail = false;
  const r = await call();
  assert.equal(r.json.sent, true);
  assert.equal(sent.length, 1);
});

test("VALID: WhatsApp estruturado ⇒ envia mensagem completa uma vez; retry duplicado", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = whatsHarness(db);
  const body = { lojaId: LOJA, phone: FONE, message: oldPosPagamentoWhatsApp, ...structured() };
  await call(body);
  const r2 = await call(body);
  assert.equal(r2.json.duplicate, true);
  assert.equal(sent.length, 1);
  assert.ok(sent[0].msg.includes(NUM));
});

test("VALID: e-mail e WhatsApp têm reservas independentes", async () => {
  const db = createDb();
  seedValid(db);
  const e = emailHarness(db);
  const w = whatsHarness(db);
  await e.call({ to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, ...structured() });
  await w.call({ lojaId: LOJA, phone: FONE, message: oldCampaignEngineWhatsApp, ...structured() });
  assert.equal(e.sent.length, 1);
  assert.equal(w.sent.length, 1);
});

test("LEGACY_VALID: CampaignEngine antigo com participação real ⇒ 1 envio; retry sem duplicado", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = emailHarness(db);
  await call(oldCampaignEngineEmail);
  const r2 = await call(oldCampaignEngineEmail);
  assert.equal(r2.json.duplicate, true);
  assert.equal(sent.length, 1);
});

test("LEGACY_VALID: WhatsApp CampaignEngine antigo com participação real e mesmo telefone ⇒ 1 envio", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = whatsHarness(db);
  await call({ lojaId: LOJA, phone: "+55 11 98888-7777", message: oldCampaignEngineWhatsApp });
  await call({ lojaId: LOJA, phone: "+55 11 98888-7777", message: oldCampaignEngineWhatsApp });
  assert.equal(sent.length, 1);
  const outro = await call({ lojaId: LOJA, phone: "11 97777-0000", message: oldCampaignEngineWhatsApp });
  assert.equal(outro.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(sent.length, 1);
});

// ---------------------------------------------------------------- bloqueios estruturados

test("ZERO campanha: payload estruturado ⇒ 0 envios", async () => {
  const db = createDb();
  db._set(`lojas/${LOJA}/campanhas_sorteio/${CAMP}/participantes/${PART}`, participante());
  const { sent, call } = emailHarness(db);
  const r = await call({ to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, ...structured() });
  assert.equal(r.json.reason, "no_active_campaign");
  assert.equal(sent.length, 0);
});

test("AMBIGUOUS: duas campanhas ativas ⇒ 0 envios", async () => {
  const db = createDb();
  seedValid(db);
  db._set(`lojas/${LOJA}/campanhas_sorteio/camp-2`, campanha());
  const e = emailHarness(db);
  const w = whatsHarness(db);
  const r = await e.call({ to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, ...structured() });
  assert.equal(r.json.reason, "ambiguous_campaign");
  await e.call(oldCampaignEngineEmail);
  await w.call({ lojaId: LOJA, phone: FONE, message: oldCampaignEngineWhatsApp });
  assert.equal(e.sent.length, 0);
  assert.equal(w.sent.length, 0);
});

test("CROSS_TENANT: participação de outra loja não autoriza e-mail", async () => {
  const db = createDb();
  seedValid(db);
  seedValid(db, { loja: OUTRA, camp: "camp-b", part: "venda_x" });
  const { sent, call } = emailHarness(db);
  const outros = [
    structured({ campaignId: "camp-b", participationId: "venda_x" }),
    structured({ participationId: "venda_x" }),
    structured({ lojaId: OUTRA }),
  ];
  for (const s of outros) {
    const r = await call({ to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, ...s });
    assert.equal(r.json.code, RAFFLE_NOT_ACTIVE, JSON.stringify(s));
  }
  db._set(`lojas/${LOJA}/campanhas_sorteio/${CAMP}/participantes/forjada`, participante({ lojaId: OUTRA }));
  const r = await call({ to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, ...structured({ participationId: "forjada" }) });
  assert.equal(r.json.reason, "cross_tenant");
  assert.equal(sent.length, 0);
});

test("MISMATCH: número, venda, destinatário, status e período inválidos ⇒ 0 envios", async () => {
  const cases = [
    [{ luckyNumber: "11111" }, {}, "lucky_number_mismatch"],
    [{ saleId: "outra-venda" }, {}, "sale_mismatch"],
    [{}, { clienteEmail: "outro@example.test" }, "recipient_mismatch"],
    [{}, { status: "invalida" }, "participation_invalid"],
    [{}, { dataParticipacao: new Date(agora.getTime() - 2 * dia) }, "outside_campaign_window"],
    [{}, { dataParticipacao: null }, "outside_campaign_window"],
    [{ participationId: "inexistente" }, {}, "participation_not_found"],
    [{ luckyNumber: "" }, {}, "missing_fields"],
  ];
  for (const [over, partData, reason] of cases) {
    const db = createDb();
    seedValid(db, { partData });
    const { sent, call } = emailHarness(db);
    const r = await call({ to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, ...structured(over) });
    assert.equal(r.json.reason, reason, JSON.stringify(over) + JSON.stringify(partData));
    assert.equal(sent.length, 0);
  }
});

test("FAIL_CLOSED: falha ao ler campanhas ⇒ 0 envios", async () => {
  const db = createDb({ failCampaignLookup: true });
  const { sent, call } = emailHarness(db);
  const r = await call({ to: EMAIL, subject: "s", html: `<p>${NUM}</p>`, ...structured() });
  assert.equal(r.json.reason, "campaign_lookup_failed");
  await call(oldCampaignEngineEmail);
  assert.equal(sent.length, 0);
});

test("WhatsApp estruturado não verificado ⇒ remove sorteio e mantém confirmação do pedido", async () => {
  const db = createDb();
  const { sent, call } = whatsHarness(db);
  await call({ lojaId: LOJA, phone: FONE, message: oldPosPagamentoWhatsApp, ...structured() });
  assert.equal(sent.length, 1);
  assert.equal(hasRaffleMarkers(sent[0].msg), false);
  assert.ok(!sent[0].msg.includes(NUM));
});

// ---------------------------------------------------------------- e-mails normais

test("NORMAL: confirmação de pedido PosPagamento (sem sorteio, sem lojaId) envia", async () => {
  const db = createDb();
  const { sent, call } = emailHarness(db);
  const r = await call({
    to: EMAIL,
    subject: "✅ Pedido confirmado - Loja A",
    html: '<html><body><h1>✅ Pedido confirmado, Maria!</h1><p>Obrigado por sua compra de <strong>R$ 129.90</strong> na <strong>Loja A</strong>!</p><p>Seu pedido foi confirmado com sucesso. Em breve você receberá as atualizações do andamento.</p><div class="cupom"><h3>🎁 Você também ganhou na Roleta da Sorte!</h3><div class="cupom-codigo">ROLETA10</div></div></body></html>',
  });
  assert.equal(r.json.sent, true);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].from, '"MasterPalm" <smtp@example.test>');
});

test("NORMAL: lembrete de carrinho abandonado (to/subject/html/text/lojaId) envia", async () => {
  const db = createDb();
  db._set(`lojas/${LOJA}`, { nome: "Loja A" });
  seedValid(db);
  const { sent, call } = emailHarness(db);
  const r = await call({
    to: EMAIL,
    subject: "Você deixou itens no carrinho - Loja A",
    html: "<p>Olá Maria, seus itens 12345 ainda estão no carrinho.</p>",
    text: "Olá Maria, seus itens ainda estão no carrinho.",
    lojaId: LOJA,
  });
  assert.equal(r.json.sent, true);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].from, '"Loja A" <smtp@example.test>');
  assert.equal(sent[0].text, "Olá Maria, seus itens ainda estão no carrinho.");
});

test("NORMAL: e-mails normais repetidos não são deduplicados", async () => {
  const db = createDb();
  const { sent, call } = emailHarness(db);
  const body = { to: EMAIL, subject: "Pedido enviado", text: "Seu pedido saiu para entrega." };
  await call(body);
  await call(body);
  assert.equal(sent.length, 2);
  assert.equal(db._count(`${CLAIMS_COLLECTION}/`), 0);
});

test("NORMAL: WhatsApp de confirmação sem sorteio envia inalterado", async () => {
  const db = createDb();
  const { sent, call } = whatsHarness(db);
  const msg = oldPosPagamentoWhatsApp.replace(/---\n🎲[^\n]*\n✅[^\n]*\n/, "");
  const r = await call({ lojaId: LOJA, phone: FONE, message: msg });
  assert.equal(r.json.sent, true);
  assert.equal(r.json.raffleRemoved, undefined);
  assert.equal(sent[0].msg, msg);
});

test("stripRaffleLines remove separador, rótulo e número", () => {
  const out = stripRaffleLines(oldPosPagamentoWhatsApp);
  assert.ok(!out.includes("---"));
  assert.ok(!out.includes(NUM));
  assert.ok(out.includes("Obrigado por comprar conosco"));
});
