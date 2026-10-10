/**
 * P0 Nathy — sendEmail / sendWhatsAppOrderConfirmation não enviam sorteio sem participação autoritativa.
 */
import test from "node:test";
import assert from "node:assert/strict";
import {
  executeSendWhatsApp,
  stripRaffleLines,
  hasRaffleMarkers,
  RAFFLE_NOT_ACTIVE,
  CLAIMS_COLLECTION,
} from "../src/raffleNotificationGuard.js";
import {
  agora,
  LOJA,
  OUTRA,
  CAMP,
  PART,
  NUM,
  EMAIL,
  FONE,
  createDb,
  campanha,
  participante,
  seedStore,
  seedValid,
  raffleBody,
  emailHarness,
} from "./_emailFakeDb.mjs";

const structured = (over = {}) => ({
  notificationType: "raffle_participation",
  lojaId: LOJA,
  saleId: "venda-123",
  campaignId: CAMP,
  participationId: PART,
  luckyNumber: NUM,
  ...over,
});

// Payloads reais dos clientes antigos (sem emailType).
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

// ---------------------------------------------------------------- cliente antigo (sem emailType)

test("OLD_CLIENT: e-mail PosPagamento antigo sem campanha ⇒ EMAIL_SEND_COUNT=0, 200 RAFFLE_NOT_ACTIVE", async () => {
  const db = createDb();
  seedStore(db);
  const { sent, call } = emailHarness(db, { token: null });
  const r = await call(oldPosPagamentoEmail);
  assert.equal(r.status, 200);
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(r.json.sent, false);
  assert.equal(sent.length, 0);
});

test("OLD_CLIENT: e-mail CampaignEngine antigo ⇒ 0 envios (200 evita fallback SMTP local)", async () => {
  const db = createDb();
  const { sent, call } = emailHarness(db, { token: null });
  const r = await call(oldCampaignEngineEmail);
  assert.equal(r.status, 200);
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(sent.length, 0);
});

test("OLD_CLIENT: payload cru de sorteio nunca envia, nem com participação real e token válido", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = emailHarness(db);
  for (const body of [oldCampaignEngineEmail, oldPosPagamentoEmail, { ...oldPosPagamentoEmail, ...structured() }]) {
    const r = await call(body);
    assert.equal(r.status, 200);
    assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
    assert.equal(r.json.reason, "legacy_raw_email_disabled");
  }
  assert.equal(sent.length, 0);
  assert.equal(db._count(`${CLAIMS_COLLECTION}/`), 0);
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

test("VALID: raffle_participation autenticado ⇒ 1 envio ao participante; retry ⇒ sem duplicado", async () => {
  const db = createDb();
  seedValid(db);
  const { sent, call } = emailHarness(db);
  const r1 = await call(raffleBody());
  assert.equal(r1.status, 200);
  assert.equal(r1.json.sent, true);
  const r2 = await call(raffleBody());
  assert.equal(r2.json.duplicate, true);
  assert.equal(r2.json.sent, false);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, EMAIL);
  assert.equal(sent[0].from, '"Loja A" <smtp@example.test>');
  assert.ok(sent[0].html.includes(NUM));
  assert.ok(sent[0].html.includes("Campanha Teste"));
  assert.ok(sent[0].text.includes("Ola Maria"));
  assert.equal(db._count(`${CLAIMS_COLLECTION}/`), 1);
});

test("VALID: falha SMTP libera a reserva e o retry envia uma vez", async () => {
  const db = createDb();
  seedValid(db);
  let fail = true;
  const { sent, call } = emailHarness(db, { failSend: () => fail });
  await assert.rejects(call(raffleBody()), /smtp down/);
  assert.equal(db._count(`${CLAIMS_COLLECTION}/`), 0);
  fail = false;
  const r = await call(raffleBody());
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
  await e.call(raffleBody());
  await w.call({ lojaId: LOJA, phone: FONE, message: oldCampaignEngineWhatsApp, ...structured() });
  assert.equal(e.sent.length, 1);
  assert.equal(w.sent.length, 1);
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

test("ZERO campanha: raffle_participation ⇒ 0 envios", async () => {
  const db = createDb();
  seedStore(db);
  db._set(`lojas/${LOJA}/campanhas_sorteio/${CAMP}/participantes/${PART}`, participante());
  const { sent, call } = emailHarness(db);
  const r = await call(raffleBody());
  assert.equal(r.status, 200);
  assert.equal(r.json.code, RAFFLE_NOT_ACTIVE);
  assert.equal(r.json.reason, "no_active_campaign");
  assert.equal(sent.length, 0);
});

test("AMBIGUOUS: duas campanhas ativas ⇒ 0 envios", async () => {
  const db = createDb();
  seedValid(db);
  db._set(`lojas/${LOJA}/campanhas_sorteio/camp-2`, campanha());
  const e = emailHarness(db);
  const w = whatsHarness(db);
  const r = await e.call(raffleBody());
  assert.equal(r.json.reason, "ambiguous_campaign");
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
    raffleBody({ campaignId: "camp-b", participationId: "venda_x" }),
    raffleBody({ participationId: "venda_x" }),
  ];
  for (const b of outros) {
    const r = await call(b);
    assert.equal(r.json.code, RAFFLE_NOT_ACTIVE, JSON.stringify(b));
  }
  const alheia = await call(raffleBody({ lojaId: OUTRA, campaignId: "camp-b", participationId: "venda_x" }));
  assert.equal(alheia.status, 403);
  db._set(`lojas/${LOJA}/campanhas_sorteio/${CAMP}/participantes/forjada`, participante({ lojaId: OUTRA }));
  const r = await call(raffleBody({ participationId: "forjada" }));
  assert.equal(r.json.reason, "cross_tenant");
  assert.equal(sent.length, 0);
});

test("MISMATCH: número, venda, destinatário, status e período inválidos ⇒ 0 envios", async () => {
  const cases = [
    [{ luckyNumber: "11111" }, {}, "lucky_number_mismatch"],
    [{ saleId: "outra-venda" }, {}, "sale_mismatch"],
    [{ to: "outro@example.test" }, {}, "recipient_mismatch"],
    [{}, { status: "invalida" }, "participation_invalid"],
    [{}, { dataParticipacao: new Date(agora.getTime() - 2 * 24 * 3600 * 1000) }, "outside_campaign_window"],
    [{}, { dataParticipacao: null }, "outside_campaign_window"],
    [{ participationId: "inexistente" }, {}, "participation_not_found"],
    [{ luckyNumber: "" }, {}, "missing_fields"],
  ];
  for (const [over, partData, reason] of cases) {
    const db = createDb();
    seedValid(db, { partData });
    const { sent, call } = emailHarness(db);
    const r = await call(raffleBody(over));
    assert.equal(r.json.reason, reason, JSON.stringify(over) + JSON.stringify(partData));
    assert.equal(sent.length, 0);
  }
});

test("FAIL_CLOSED: falha ao ler campanhas ⇒ 0 envios", async () => {
  const db = createDb({ failCampaignLookup: true });
  seedStore(db);
  db._set(`lojas/${LOJA}/campanhas_sorteio/${CAMP}/participantes/${PART}`, participante());
  const { sent, call } = emailHarness(db);
  const r = await call(raffleBody());
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
