/**
 * Contrato server-side do `sendEmail`: só tipos explícitos, remetente autenticado da loja,
 * destinatário e conteúdo derivados de registos autoritativos (pedido, participação, cliente,
 * carrinho). Nunca aceita `to/subject/html/text` arbitrários.
 *
 *   order_confirmation       { lojaId, saleId [, campaignId, participationId, luckyNumber] }
 *   raffle_participation     { lojaId, saleId, campaignId, participationId, luckyNumber }
 *   abandoned_cart_reminder  { lojaId, clienteId | cartId [, to, link] }
 *
 * Pedidos sem `emailType` (clientes antigos) nunca enviam: conteúdo de sorteio devolve 200
 * RAFFLE_NOT_ACTIVE (cliente antigo não cai no SMTP local); o resto é recusado.
 */
import { createHash } from "node:crypto";
import {
  verifyStructuredParticipation,
  claimRaffleNotification,
  hasRaffleMarkers,
  readStructuredRaffleFields,
  RAFFLE_NOT_ACTIVE,
  RAFFLE_ALREADY_SENT,
} from "./raffleNotificationGuard.js";

export const EMAIL_TYPES = Object.freeze({
  ORDER_CONFIRMATION: "order_confirmation",
  RAFFLE_PARTICIPATION: "raffle_participation",
  ABANDONED_CART: "abandoned_cart_reminder",
});
export const EMAIL_CLAIMS_COLLECTION = "_email_send_claims";
export const ABANDONED_CART_COOLDOWN_MS = 10 * 60 * 1000;
export const DEFAULT_CATALOG_BASE = "https://app.mastepalm.com.br/loja";

const CATALOG_HOSTS = new Set([
  "app.mastepalm.com.br",
  "masterpalm-58c46.web.app",
  "masterpalm-58c46.firebaseapp.com",
]);
const MAX_CART_LINES = 30;
const TIME_ZONE = "America/Sao_Paulo";

function str(v) {
  return v == null ? "" : String(v).trim();
}

export function normalizeEmail(raw) {
  const e = str(raw).toLowerCase();
  if (!e || e.length > 254) return null;
  return /^[^\s@<>()[\]",;:\\]+@[^\s@<>()[\]",;:\\]+\.[^\s@<>()[\]",;:\\]+$/.test(e) ? e : null;
}

function validDocId(v) {
  const s = str(v);
  if (!s || s.length > 256 || s.includes("/") || s === "." || s === ".." || /^__.*__$/.test(s)) return null;
  return s;
}

export function escapeHtml(v) {
  return String(v ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function digits(v) {
  let d = str(v).replace(/\D/g, "");
  if (d.length > 11 && d.startsWith("55")) d = d.slice(2);
  return d;
}

function phonesMatch(a, b) {
  const x = digits(a);
  const y = digits(b);
  if (x.length < 10 || y.length < 10) return false;
  return x === y || x.endsWith(y) || y.endsWith(x);
}

function asDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate();
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function formatDate(d) {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: TIME_ZONE, day: "2-digit", month: "2-digit", year: "numeric" }).format(d);
}

function money(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(2) : "0.00";
}

function hashId(...parts) {
  return createHash("sha256").update(parts.join("|")).digest("hex");
}

const reply = (status, json) => ({ status, json });
const fail = (status, code, error) => reply(status, { ok: false, sent: false, code, error });
const raffleBlocked = (reason) => reply(200, { ok: false, sent: false, code: RAFFLE_NOT_ACTIVE, reason });
const duplicate = (code) => reply(200, { ok: true, sent: false, duplicate: true, code });

/** Dono/admin/membro owner|admin, users.store_id da própria loja, ou vendedor ativo com permissão de vendas. */
export async function isStoreEmailSender(db, { colLojas = "lojas", lojaId, uid }) {
  const base = db.collection(colLojas).doc(lojaId);
  const [loja, seller, member, user] = await Promise.all([
    base.get(),
    base.collection("vendedores").doc(uid).get(),
    base.collection("members").doc(uid).get(),
    db.collection("users").doc(uid).get(),
  ]);
  if (!loja.exists) return false;
  const data = loja.data() || {};
  if (data.ownerUid === uid) return true;
  if (data.admins && data.admins[uid] === true) return true;
  if (member.exists) {
    const role = str(member.data()?.role);
    if (role === "owner" || role === "admin") return true;
  }
  if (user.exists) {
    const ud = user.data() || {};
    const storeId = str(ud.store_id || ud.storeId);
    if (storeId && storeId === lojaId && (!data.ownerUid || data.ownerUid === uid)) return true;
  }
  if (seller.exists && seller.data()?.ativo === true) {
    const perms = seller.data()?.permissoes || {};
    if (perms.vendas === true || perms.sale === true || !Object.keys(perms).length) return true;
  }
  return false;
}

async function storeDisplayName(db, colLojas, lojaId) {
  try {
    const snap = await db.collection(colLojas).doc(lojaId).get();
    const d = snap.exists ? snap.data() || {} : {};
    const nome = str(d.nome || d.name).replace(/["\r\n<>]/g, "");
    if (nome) return nome;
  } catch (e) {
    console.warn("[sendEmail] falha ao resolver nome da loja:", lojaId, e?.message || e);
  }
  return "MasterPalm";
}

async function claimOnce(db, id, data) {
  const ref = db.collection(EMAIL_CLAIMS_COLLECTION).doc(id);
  try {
    await ref.create(data);
  } catch (e) {
    const code = e?.code;
    if (code === 6 || code === "already-exists" || /already exists/i.test(String(e?.message || ""))) return null;
    throw e;
  }
  return {
    release: async () => {
      try {
        await ref.delete();
      } catch (_) {}
    },
  };
}

/** Janela mínima entre lembretes para o mesmo alvo. `null` ⇒ ainda em cooldown. */
async function claimCooldown(db, id, data, agora) {
  const ref = db.collection(EMAIL_CLAIMS_COLLECTION).doc(id);
  const snap = await ref.get();
  const prev = snap.exists ? snap.data() || {} : null;
  const last = asDate(prev?.sentAt);
  if (last && agora.getTime() - last.getTime() < ABANDONED_CART_COOLDOWN_MS) return null;
  await ref.set({ ...data, sentAt: agora });
  return {
    release: async () => {
      try {
        if (prev) await ref.set(prev);
        else await ref.delete();
      } catch (_) {}
    },
  };
}

// ------------------------------------------------------------------ templates

export function renderOrderConfirmation({ nome, lojaNome, total, cupomRoleta, raffleNumber }) {
  const n = escapeHtml(nome || "Cliente");
  const loja = escapeHtml(lojaNome);
  const cupomCodigo = str(cupomRoleta?.codigo);
  const cupomDesconto = Number(cupomRoleta?.desconto);
  const cupom = cupomCodigo
    ? `
      <div class="cupom">
        <h3 style="margin: 0 0 10px 0; color: #856404;">🎁 Você também ganhou na Roleta da Sorte!</h3>
        <p style="margin: 5px 0; color: #856404;">Cupom de desconto de <strong>${Number.isFinite(cupomDesconto) ? cupomDesconto.toFixed(0) : "0"}%</strong> para sua próxima compra:</p>
        <div class="cupom-codigo">${escapeHtml(cupomCodigo)}</div>
        <p style="margin: 10px 0 0 0; font-size: 12px; color: #856404;">📅 Válido por 60 dias | 🔄 Use na próxima compra</p>
      </div>`
    : "";
  const corpo = raffleNumber
    ? `
      <div class="numero-sorte">
        <h2>🎲 Seu Número da Sorte:</h2>
        <div class="numero">${escapeHtml(raffleNumber)}</div>
      </div>
      <p style="text-align: center; color: #28a745; font-weight: bold;">✅ Você está participando da nossa promoção!</p>
      <p>Seu número da sorte foi registrado e você está concorrendo a prêmios incríveis. Fique de olho no sorteio!</p>`
    : `
      <p>Seu pedido foi confirmado com sucesso. Em breve você receberá as atualizações do andamento.</p>`;
  const subject = raffleNumber
    ? `🎉 Parabéns! Você está concorrendo - ${lojaNome}`
    : `✅ Pedido confirmado - ${lojaNome}`;
  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { padding: 30px; }
    .numero-sorte { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; margin: 20px 0; }
    .numero-sorte h2 { margin: 0 0 10px 0; font-size: 18px; }
    .numero-sorte .numero { font-size: 48px; font-weight: bold; letter-spacing: 5px; }
    .cupom { background: #fff3cd; border: 2px dashed #ffc107; padding: 20px; border-radius: 10px; margin: 20px 0; text-align: center; }
    .cupom-codigo { font-size: 24px; font-weight: bold; color: #856404; letter-spacing: 2px; }
    .footer { background-color: #f8f9fa; padding: 20px; text-align: center; font-size: 12px; color: #6c757d; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>${raffleNumber ? "🎉 Parabéns" : "✅ Pedido confirmado"}, ${n}!</h1>
    </div>
    <div class="content">
      <p>Obrigado por sua compra de <strong>R$ ${money(total)}</strong> na <strong>${loja}</strong>!</p>
${corpo}
${cupom}
      <p style="margin-top: 30px; text-align: center;">Obrigado por comprar conosco! 💜</p>
    </div>
    <div class="footer">
      <p>${loja} - Todos os direitos reservados</p>
      <p>Este é um email automático, por favor não responda.</p>
    </div>
  </div>
</body>
</html>`;
  return { subject, html };
}

export function renderRaffleParticipation({ clienteNome, numero, campanhaNome, dataSorteio, lojaNome }) {
  const primeiroNome = str(clienteNome).split(/\s+/)[0] || "Cliente";
  const data = dataSorteio ? formatDate(dataSorteio) : "Em breve";
  const subject = `Confirmacao de participacao - Campanha ${campanhaNome}`;
  const text = `Ola ${primeiroNome},

Sua participacao na campanha "${campanhaNome}" foi registrada com sucesso!

Seu numero da sorte: ${numero}

Guarde este numero com carinho. Ele e valido para o sorteio conforme as regras da campanha.

Data do sorteio: ${data}

Loja: ${lojaNome}

Desejamos boa sorte!

Atenciosamente,
Equipe ${lojaNome}
`;
  const html = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;">
<h2>Participacao registrada</h2>
<p>Ola ${escapeHtml(primeiroNome)},</p>
<p>Sua participacao na campanha <strong>${escapeHtml(campanhaNome)}</strong> foi registrada com sucesso!</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:4px;">${escapeHtml(numero)}</p>
<p>Data do sorteio: ${escapeHtml(data)}</p>
<p>Loja: ${escapeHtml(lojaNome)}</p>
<p>Desejamos boa sorte!</p>
</body></html>`;
  return { subject, html, text };
}

export function renderAbandonedCart({ nomeCliente, lojaNome, link, itens }) {
  const nome = str(nomeCliente) || "cliente";
  const lines = [`Olá, ${nome}!`, "", `Você deixou itens no carrinho da ${lojaNome}. Que tal finalizar sua compra?`, ""];
  const lista = (Array.isArray(itens) ? itens : []).slice(0, MAX_CART_LINES);
  if (lista.length) {
    lines.push("Itens:");
    for (const raw of lista) {
      const p = raw && typeof raw === "object" ? raw : {};
      const n = str(p.nome || p.name || p.produtoNome) || "Produto";
      const q = Number.isFinite(Number(p.quantidade)) && Number(p.quantidade) > 0 ? Math.trunc(Number(p.quantidade)) : 1;
      const extras = [str(p.cor) && `cor ${str(p.cor)}`, str(p.tamanho) && `tam ${str(p.tamanho)}`].filter(Boolean).join(", ");
      lines.push(extras ? `  • ${q}x ${n} (${extras})` : `  • ${q}x ${n}`);
    }
    lines.push("");
  }
  lines.push(`Acesse seu carrinho: ${link}`, "", "Se já finalizou a compra, ignore este e-mail.");
  const text = `${lines.join("\n")}\n`;
  const html = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;font-size:14px;color:#333;line-height:1.5;">${escapeHtml(text).replace(/\n/g, "<br>")}</body></html>`;
  return { subject: `Você deixou itens no carrinho - ${lojaNome}`, html, text };
}

// ------------------------------------------------------------------ links

async function activeCustomDomain(db, colLojas, lojaId) {
  const hosts = new Set();
  const pick = (m) => {
    if (!m || typeof m !== "object") return;
    const host = str(m.dominioCatalogo || m.dominio_catalogo).toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "");
    const status = str(m.dominioStatus || m.dominio_status).toLowerCase();
    if (host && host.includes(".") && status === "ativo") hosts.add(host);
  };
  const base = db.collection(colLojas).doc(lojaId);
  for (const ref of [base.collection("config").doc("config"), base.collection("draft_config").doc("config")]) {
    try {
      const snap = await ref.get();
      if (!snap.exists) continue;
      const d = snap.data() || {};
      pick(d);
      pick(d.draft);
      pick(d.published);
    } catch (_) {}
  }
  return hosts;
}

/** Link do lembrete: só https para o catálogo MasterPalm ou domínio próprio ativo da loja. */
export async function resolveCatalogLink(db, { colLojas = "lojas", lojaId, link, cartId }) {
  const fallback = `${DEFAULT_CATALOG_BASE}/${encodeURIComponent(lojaId)}${cartId ? `?cart=${encodeURIComponent(cartId)}` : ""}`;
  const raw = str(link);
  if (!raw) return { ok: true, link: fallback };
  let u;
  try {
    u = new URL(raw);
  } catch (_) {
    return { ok: false };
  }
  if (u.protocol !== "https:" || u.username || u.password || u.port) return { ok: false };
  const host = u.hostname.toLowerCase();
  if (CATALOG_HOSTS.has(host)) {
    if (host === "app.mastepalm.com.br" && !u.pathname.startsWith("/loja")) return { ok: false };
    return { ok: true, link: u.toString() };
  }
  const custom = await activeCustomDomain(db, colLojas, lojaId);
  return custom.has(host) ? { ok: true, link: u.toString() } : { ok: false };
}

// ------------------------------------------------------------------ handlers

async function handleOrderConfirmation(ctx) {
  const { db, colLojas, body, lojaId, agora } = ctx;
  const saleId = validDocId(body.saleId);
  if (!saleId) return fail(400, "INVALID_ARGUMENT", "saleId obrigatório");

  let pedidoDoc;
  try {
    const snap = await db.collection(colLojas).doc(lojaId).collection("pedidos").where("vendaId", "==", saleId).limit(1).get();
    pedidoDoc = snap.docs[0];
  } catch (e) {
    console.error("[sendEmail] order lookup failed:", e?.message || e);
    return fail(503, "ORDER_LOOKUP_FAILED", "Não foi possível validar o pedido");
  }
  if (!pedidoDoc) return fail(404, "ORDER_NOT_FOUND", "Pedido não encontrado");
  const pedido = pedidoDoc.data() || {};
  if (str(pedido.lojaId) && str(pedido.lojaId) !== lojaId) return fail(403, "CROSS_TENANT", "Pedido de outra loja");

  const cliente = pedido.cliente && typeof pedido.cliente === "object" ? pedido.cliente : {};
  const to = normalizeEmail(cliente.email);
  if (!to) return fail(422, "RECIPIENT_NOT_AVAILABLE", "Pedido sem e-mail do cliente");
  if (str(body.to) && normalizeEmail(body.to) !== to) return fail(422, "RECIPIENT_MISMATCH", "Destinatário não corresponde ao pedido");

  const orderClaim = await claimOnce(db, hashId(EMAIL_TYPES.ORDER_CONFIRMATION, lojaId, pedidoDoc.id), {
    emailType: EMAIL_TYPES.ORDER_CONFIRMATION,
    lojaId,
    pedidoId: pedidoDoc.id,
    claimedAt: agora,
  });
  if (!orderClaim) return duplicate("EMAIL_ALREADY_SENT");

  let raffleClaim = null;
  let raffleNumber = "";
  let raffleReason = null;
  const fields = {
    lojaId,
    saleId,
    campaignId: str(body.campaignId),
    participationId: str(body.participationId),
    luckyNumber: str(body.luckyNumber),
  };
  if (fields.campaignId || fields.participationId || fields.luckyNumber) {
    try {
      const verified = await verifyStructuredParticipation(db, { colLojas, fields, recipient: { email: to }, agora });
      if (!verified.ok) raffleReason = verified.reason;
      else {
        raffleClaim = await claimRaffleNotification(db, "email", verified, agora);
        if (raffleClaim) raffleNumber = fields.luckyNumber;
        else raffleReason = "raffle_already_sent";
      }
    } catch (e) {
      await orderClaim.release();
      throw e;
    }
    if (raffleReason) {
      console.warn(JSON.stringify({ service: "sendEmail", event: "raffle_block_removed", reason: raffleReason, lojaId }));
    }
  }

  const lojaNome = await storeDisplayName(db, colLojas, lojaId);
  const total = pedido.total ?? pedido.valorTotal ?? pedido.subtotal ?? 0;
  const { subject, html } = renderOrderConfirmation({
    nome: str(cliente.nome) || "Cliente",
    lojaNome,
    total,
    cupomRoleta: pedido.cupomRoleta,
    raffleNumber,
  });
  return {
    send: { to, subject, html, lojaNome },
    claims: [orderClaim, raffleClaim].filter(Boolean),
    extra: { raffleIncluded: Boolean(raffleNumber), ...(raffleReason ? { raffleCode: RAFFLE_NOT_ACTIVE, raffleReason } : {}) },
  };
}

async function handleRaffleParticipation(ctx) {
  const { db, colLojas, body, lojaId, agora } = ctx;
  const fields = {
    lojaId,
    saleId: str(body.saleId),
    campaignId: str(body.campaignId),
    participationId: str(body.participationId),
    luckyNumber: str(body.luckyNumber),
  };
  if (![fields.saleId, fields.campaignId, fields.participationId].every(validDocId) || !fields.luckyNumber) {
    return raffleBlocked("missing_fields");
  }

  let participant;
  try {
    const snap = await db
      .collection(colLojas)
      .doc(lojaId)
      .collection("campanhas_sorteio")
      .doc(fields.campaignId)
      .collection("participantes")
      .doc(fields.participationId)
      .get();
    participant = snap.exists ? snap.data() || {} : null;
  } catch (_) {
    return raffleBlocked("participation_lookup_failed");
  }
  if (!participant) return raffleBlocked("participation_not_found");
  const to = normalizeEmail(participant.clienteEmail || participant.email);
  if (!to) return raffleBlocked("recipient_not_available");
  if (str(body.to) && normalizeEmail(body.to) !== to) return raffleBlocked("recipient_mismatch");

  const verified = await verifyStructuredParticipation(db, { colLojas, fields, recipient: { email: to }, agora });
  if (!verified.ok) {
    console.warn(JSON.stringify({ service: "sendEmail", event: "raffle_email_blocked", reason: verified.reason, lojaId }));
    return raffleBlocked(verified.reason);
  }
  const claim = await claimRaffleNotification(db, "email", verified, agora);
  if (!claim) return duplicate(RAFFLE_ALREADY_SENT);

  const campanha = verified.campaignData || {};
  const lojaNome = await storeDisplayName(db, colLojas, lojaId);
  const content = renderRaffleParticipation({
    clienteNome: str(verified.participation?.clienteNome) || "Cliente",
    numero: str(verified.participation?.numeroSorte ?? verified.participation?.numero) || fields.luckyNumber,
    campanhaNome: str(campanha.nome || campanha.titulo) || "Campanha",
    dataSorteio: asDate(campanha.dataSorteio) || asDate(campanha.dataFim),
    lojaNome,
  });
  return { send: { to, ...content, lojaNome }, claims: [claim], extra: {} };
}

async function knownCustomerEmailForPhones(db, colLojas, lojaId, email, phones) {
  const usable = phones.filter((p) => digits(p).length >= 10);
  if (!usable.length) return false;
  const snap = await db.collection(colLojas).doc(lojaId).collection("clientes").where("email", "==", email).limit(5).get();
  return snap.docs.some((d) => {
    const c = d.data() || {};
    return [c.telefone, c.whatsapp].some((t) => usable.some((p) => phonesMatch(t, p)));
  });
}

async function handleAbandonedCart(ctx) {
  const { db, colLojas, body, lojaId, agora } = ctx;
  const cartId = str(body.cartId) ? validDocId(body.cartId) : null;
  const clienteId = !cartId && str(body.clienteId) ? validDocId(body.clienteId) : null;
  if (!cartId && !clienteId) return fail(400, "INVALID_ARGUMENT", "cartId ou clienteId obrigatório");

  const base = db.collection(colLojas).doc(lojaId);
  const ref = cartId ? base.collection("carrinhos_abandonados").doc(cartId) : base.collection("clientes").doc(clienteId);
  const snap = await ref.get();
  if (!snap.exists) return fail(404, "CART_NOT_FOUND", "Carrinho não encontrado");
  const d = snap.data() || {};

  const nome = cartId ? str(d.clienteNome || d.nome) : str(d.nome);
  const authEmail = normalizeEmail(cartId ? d.clienteEmail || d.email || d.cliente_email : d.email);
  const phones = cartId ? [d.clienteTelefone, d.telefone, d.whatsapp, d.clienteWhatsapp] : [d.telefone, d.whatsapp];
  const itensRaw = cartId ? d.produtos ?? d.itens ?? d.items : d.carrinho;
  const itens = Array.isArray(itensRaw) ? itensRaw : [];
  if (!itens.length) return fail(422, "CART_EMPTY", "Carrinho vazio");

  let to = authEmail;
  if (to) {
    if (str(body.to) && normalizeEmail(body.to) !== to) return fail(422, "RECIPIENT_MISMATCH", "Destinatário não corresponde ao carrinho");
  } else {
    const requested = normalizeEmail(body.to);
    if (!requested) return fail(422, "RECIPIENT_NOT_AVAILABLE", "Carrinho sem e-mail do cliente");
    if (!(await knownCustomerEmailForPhones(db, colLojas, lojaId, requested, phones))) {
      return fail(422, "RECIPIENT_NOT_VERIFIED", "E-mail não pertence a um cliente desta loja com o mesmo telefone");
    }
    to = requested;
  }

  const resolved = await resolveCatalogLink(db, { colLojas, lojaId, link: body.link, cartId });
  if (!resolved.ok) return fail(400, "INVALID_LINK", "Link fora do catálogo da loja");

  const target = cartId ? `cart:${cartId}` : `cliente:${clienteId}`;
  const claim = await claimCooldown(db, hashId(EMAIL_TYPES.ABANDONED_CART, lojaId, target), {
    emailType: EMAIL_TYPES.ABANDONED_CART,
    lojaId,
    target,
  }, agora);
  if (!claim) return fail(429, "EMAIL_COOLDOWN", "Lembrete enviado recentemente para este carrinho");

  const lojaNome = await storeDisplayName(db, colLojas, lojaId);
  const content = renderAbandonedCart({ nomeCliente: nome, lojaNome, link: resolved.link, itens });
  return { send: { to, ...content, lojaNome }, claims: [claim], extra: { to } };
}

const HANDLERS = {
  [EMAIL_TYPES.ORDER_CONFIRMATION]: handleOrderConfirmation,
  [EMAIL_TYPES.RAFFLE_PARTICIPATION]: handleRaffleParticipation,
  [EMAIL_TYPES.ABANDONED_CART]: handleAbandonedCart,
};

/**
 * Núcleo do `sendEmail` (HTTP). `verifyIdToken(token)` → `{uid}`; `limitUser(uid)` lança se exceder.
 * @returns {Promise<{status: number, json: object}>}
 */
export async function handleSendEmailRequest({
  db,
  colLojas = "lojas",
  body: rawBody,
  idToken,
  verifyIdToken,
  limitUser = async () => {},
  smtpUser,
  sendMail,
  agora = new Date(),
}) {
  const body = rawBody && typeof rawBody === "object" ? rawBody : {};
  const emailType = str(body.emailType);
  const handler = Object.prototype.hasOwnProperty.call(HANDLERS, emailType) ? HANDLERS[emailType] : null;

  if (!handler) {
    const legacyRaffle =
      hasRaffleMarkers(body.subject, body.assunto, body.html, body.text) || readStructuredRaffleFields(body).declared;
    console.warn(
      JSON.stringify({ service: "sendEmail", event: "raw_email_rejected", emailType: emailType || null, raffle: legacyRaffle }),
    );
    if (legacyRaffle) return raffleBlocked("legacy_raw_email_disabled");
    return fail(400, "EMAIL_TYPE_REQUIRED", "Tipo de e-mail não suportado");
  }
  if (["subject", "assunto", "html", "text", "mensagem"].some((k) => body[k] != null)) {
    return fail(400, "RAW_CONTENT_NOT_ALLOWED", "Conteúdo do e-mail é gerado no servidor");
  }

  const lojaId = validDocId(body.lojaId);
  if (!lojaId) return fail(400, "INVALID_ARGUMENT", "lojaId obrigatório");

  if (!idToken) return fail(401, "UNAUTHENTICATED", "Login obrigatório");
  let uid;
  try {
    uid = str((await verifyIdToken(idToken))?.uid);
  } catch (_) {
    uid = "";
  }
  if (!uid) return fail(401, "UNAUTHENTICATED", "Sessão inválida");
  await limitUser(uid);
  if (!(await isStoreEmailSender(db, { colLojas, lojaId, uid }))) {
    console.warn(JSON.stringify({ service: "sendEmail", event: "sender_not_member", emailType, lojaId }));
    return fail(403, "PERMISSION_DENIED", "Sem permissão para esta loja");
  }

  const plan = await handler({ db, colLojas, body, lojaId, agora });
  if (!plan.send) return plan;

  try {
    await sendMail({
      from: `"${plan.send.lojaNome}" <${smtpUser}>`,
      to: plan.send.to,
      subject: plan.send.subject,
      html: plan.send.html,
      text: plan.send.text || undefined,
    });
  } catch (e) {
    for (const c of plan.claims) await c.release();
    throw e;
  }
  return reply(200, { ok: true, sent: true, emailType, message: "Email enviado", ...plan.extra });
}
