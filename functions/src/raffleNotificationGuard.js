/**
 * Guard server-side para notificações de sorteio (sendEmail / sendWhatsAppOrderConfirmation).
 *
 * Contrato estruturado (clientes novos):
 *   notificationType: "raffle_participation"
 *   lojaId, saleId, campaignId, participationId, luckyNumber
 * Só envia se existir participação persistida, válida, da mesma loja, na ÚNICA campanha
 * ativa (gate autoritativo), com número/venda/destinatário coincidentes.
 *
 * Clientes antigos não enviam campos estruturados: o conteúdo de sorteio é reconhecido
 * por marcadores textuais (não existe alternativa estruturada nesses payloads) e exige
 * o mesmo vínculo autoritativo via número + destinatário; caso contrário não envia.
 */
import { createHash } from "node:crypto";
import { resolverCampanhaAtiva } from "./campanhaSorteioGate.js";

export const RAFFLE_NOTIFICATION_TYPE = "raffle_participation";
export const RAFFLE_NOT_ACTIVE = "RAFFLE_NOT_ACTIVE";
export const RAFFLE_ALREADY_SENT = "RAFFLE_ALREADY_SENT";
export const CLAIMS_COLLECTION = "_raffle_notification_claims";

const MARKERS = [
  /numero\s+da\s+sorte/,
  /voce\s+esta\s+concorrendo/,
  /participando\s+da\s+nossa\s+promocao/,
  /participacao\s+registrada/,
  /participacao\s+na\s+campanha/,
  /confirmacao\s+de\s+participacao/,
];

/** Mensagem só de sorteio (sem pedido/compra) não é reaproveitada sem o bloco de sorteio. */
const ORDER_SIGNAL = /\bpedido\b|\bcompra\b/;

const LEGACY_CANDIDATE_RE = /(?<!\d)\d{5}(?!\d)/g;
const MAX_LEGACY_CANDIDATES = 10;

export function normalizeForMarkers(raw) {
  return String(raw ?? "")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[*_~]/g, " ")
    .toLowerCase()
    .replace(/\s+/g, " ");
}

export function hasRaffleMarkers(...parts) {
  const txt = parts.map(normalizeForMarkers).join(" ");
  return MARKERS.some((re) => re.test(txt));
}

function str(v) {
  return v == null ? "" : String(v).trim();
}

/** Campos estruturados enviados por clientes novos. */
export function readStructuredRaffleFields(body) {
  const b = body || {};
  const type = str(b.notificationType || b.emailType || b.messageType).toLowerCase();
  const fields = {
    lojaId: str(b.lojaId || b.loja_id),
    saleId: str(b.saleId),
    campaignId: str(b.campaignId),
    participationId: str(b.participationId),
    luckyNumber: str(b.luckyNumber),
  };
  const declared =
    type === RAFFLE_NOTIFICATION_TYPE ||
    Boolean(fields.campaignId || fields.participationId || fields.luckyNumber || fields.saleId);
  return { declared, ...fields };
}

function asDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate();
  if (typeof v === "string" && v.trim()) {
    const d = new Date(v.trim());
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function digits(v) {
  let d = str(v).replace(/\D/g, "");
  if (d.length > 11 && d.startsWith("55")) d = d.slice(2);
  return d;
}

export function recipientMatches(participant, recipient) {
  if (recipient.email != null) {
    const want = str(recipient.email).toLowerCase();
    const got = str(participant.clienteEmail || participant.email).toLowerCase();
    return Boolean(want) && want === got;
  }
  if (recipient.phone != null) {
    const want = digits(recipient.phone);
    const got = digits(participant.clienteTelefone || participant.telefone);
    if (want.length < 10 || got.length < 10) return false;
    return want === got || want.endsWith(got) || got.endsWith(want);
  }
  return false;
}

function participationProblem(p, { lojaId, campaignId, saleId, luckyNumber, campanhaData, recipient }) {
  if (str(p.status) !== "valido") return "participation_invalid";
  const numero = str(p.numeroSorte ?? p.numero);
  if (!numero || (luckyNumber && numero !== luckyNumber)) return "lucky_number_mismatch";
  if (saleId) {
    const ids = [str(p.vendaId), str(p.pedidoId)].filter(Boolean);
    if (!ids.includes(saleId)) return "sale_mismatch";
  }
  if (str(p.lojaId) && str(p.lojaId) !== lojaId) return "cross_tenant";
  if (str(p.campanhaId) && str(p.campanhaId) !== campaignId) return "campaign_mismatch";
  const quando = asDate(p.dataParticipacao);
  const inicio = asDate(campanhaData?.dataInicio);
  const fim = asDate(campanhaData?.dataFim);
  if (!quando || !inicio || !fim || quando < inicio || quando > fim) return "outside_campaign_window";
  if (!recipientMatches(p, recipient)) return "recipient_mismatch";
  return null;
}

async function activeCampaign(db, { colLojas, lojaId, agora }) {
  try {
    const gate = await resolverCampanhaAtiva(db, { colLojas, lojaId, agora });
    if (gate.status === "ativa") return { campanha: gate.campanha };
    return { reason: gate.status === "ambigua" ? "ambiguous_campaign" : "no_active_campaign" };
  } catch (_) {
    return { reason: "campaign_lookup_failed" };
  }
}

/** Participação estruturada: tudo tem de bater com o documento persistido. */
export async function verifyStructuredParticipation(db, { colLojas = "lojas", fields, recipient, agora = new Date() }) {
  const { lojaId, saleId, campaignId, participationId, luckyNumber } = fields;
  if (!lojaId || !saleId || !campaignId || !participationId || !luckyNumber) {
    return { ok: false, reason: "missing_fields" };
  }
  const gate = await activeCampaign(db, { colLojas, lojaId, agora });
  if (!gate.campanha) return { ok: false, reason: gate.reason };
  if (gate.campanha.id !== campaignId) return { ok: false, reason: "campaign_mismatch" };

  let snap;
  try {
    snap = await db
      .collection(colLojas)
      .doc(lojaId)
      .collection("campanhas_sorteio")
      .doc(campaignId)
      .collection("participantes")
      .doc(participationId)
      .get();
  } catch (_) {
    return { ok: false, reason: "participation_lookup_failed" };
  }
  if (!snap.exists) return { ok: false, reason: "participation_not_found" };
  const problem = participationProblem(snap.data() || {}, {
    lojaId,
    campaignId,
    saleId,
    luckyNumber,
    campanhaData: gate.campanha.data,
    recipient,
  });
  if (problem) return { ok: false, reason: problem };
  return { ok: true, lojaId, campaignId, participationId };
}

/** Payload legado (sem campos estruturados): número no texto + destinatário têm de casar com 1 participação. */
export async function verifyLegacyParticipation(db, { colLojas = "lojas", lojaId, texts, recipient, agora = new Date() }) {
  if (!lojaId) return { ok: false, reason: "legacy_missing_loja" };
  const plain = texts.map(normalizeForMarkers).join(" ");
  const candidates = [...new Set(plain.match(LEGACY_CANDIDATE_RE) || [])].slice(0, MAX_LEGACY_CANDIDATES);
  if (candidates.length === 0) return { ok: false, reason: "legacy_no_number" };

  const gate = await activeCampaign(db, { colLojas, lojaId, agora });
  if (!gate.campanha) return { ok: false, reason: gate.reason };
  const campaignId = gate.campanha.id;

  let docs;
  try {
    const snap = await db
      .collection(colLojas)
      .doc(lojaId)
      .collection("campanhas_sorteio")
      .doc(campaignId)
      .collection("participantes")
      .where("numeroSorte", "in", candidates)
      .limit(MAX_LEGACY_CANDIDATES)
      .get();
    docs = snap.docs;
  } catch (_) {
    return { ok: false, reason: "participation_lookup_failed" };
  }
  const valid = docs.filter(
    (d) =>
      !participationProblem(d.data() || {}, {
        lojaId,
        campaignId,
        saleId: "",
        luckyNumber: "",
        campanhaData: gate.campanha.data,
        recipient,
      }),
  );
  if (valid.length !== 1) return { ok: false, reason: valid.length ? "legacy_ambiguous" : "participation_not_found" };
  return { ok: true, lojaId, campaignId, participationId: valid[0].id };
}

export function claimId(channel, { lojaId, campaignId, participationId }) {
  return createHash("sha256").update(`${channel}|${lojaId}|${campaignId}|${participationId}`).digest("hex");
}

/** Reserva idempotente por canal+participação. `null` ⇒ já enviado/reservado. */
export async function claimRaffleNotification(db, channel, verified, agora = new Date()) {
  const ref = db.collection(CLAIMS_COLLECTION).doc(claimId(channel, verified));
  try {
    await ref.create({
      channel,
      lojaId: verified.lojaId,
      campaignId: verified.campaignId,
      participationId: verified.participationId,
      claimedAt: agora,
    });
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

/**
 * Decide o destino de uma notificação.
 * @returns {Promise<{action: "send"} | {action: "send_raffle", claim: {release: () => Promise<void>}}
 *   | {action: "block", reason: string} | {action: "duplicate"}>}
 */
export async function evaluateRaffleNotification(db, { colLojas = "lojas", channel, body, texts, recipient, agora = new Date() }) {
  const fields = readStructuredRaffleFields(body);
  const markers = hasRaffleMarkers(...texts);
  if (!fields.declared && !markers) return { action: "send" };

  const verified = fields.declared
    ? await verifyStructuredParticipation(db, { colLojas, fields, recipient, agora })
    : await verifyLegacyParticipation(db, { colLojas, lojaId: fields.lojaId, texts, recipient, agora });
  if (!verified.ok) return { action: "block", reason: verified.reason };

  const claim = await claimRaffleNotification(db, channel, verified, agora);
  if (!claim) return { action: "duplicate" };
  return { action: "send_raffle", claim };
}

/** Remove o bloco de sorteio de uma mensagem de WhatsApp (mantém a confirmação do pedido). */
export function stripRaffleLines(message) {
  const lines = String(message ?? "").split("\n");
  const drop = new Array(lines.length).fill(false);
  for (let i = 0; i < lines.length; i++) {
    const n = normalizeForMarkers(lines[i]);
    if (!MARKERS.some((re) => re.test(n))) continue;
    drop[i] = true;
    if (/numero\s+da\s+sorte/.test(n) && !/\d{5}/.test(n)) {
      for (let j = i + 1; j < lines.length; j++) {
        if (!lines[j].trim()) continue;
        if (/^\s*\*?\s*\d{5}\s*\*?\s*$/.test(lines[j])) drop[j] = true;
        break;
      }
    }
    for (let j = i - 1; j >= 0; j--) {
      if (!lines[j].trim()) continue;
      if (lines[j].trim() === "---") drop[j] = true;
      break;
    }
  }
  return lines
    .filter((_, i) => !drop[i])
    .join("\n")
    .replace(/\n{3,}/g, "\n\n");
}

const blockedJson = (reason) => ({ ok: false, sent: false, code: RAFFLE_NOT_ACTIVE, reason });
const duplicateJson = () => ({ ok: true, sent: false, duplicate: true, code: RAFFLE_ALREADY_SENT });

/**
 * Núcleo do sendEmail após validação/rate-limit/SMTP.
 * Bloqueio devolve 200 para clientes antigos não caírem no fallback SMTP local.
 */
export async function executeSendEmail({ db, colLojas = "lojas", body, input, smtpUser, sendMail, agora = new Date() }) {
  const { to, subject, html, text, lojaId } = input;
  const decision = await evaluateRaffleNotification(db, {
    colLojas,
    channel: "email",
    body,
    texts: [subject, html, text],
    recipient: { email: to },
    agora,
  });
  if (decision.action === "block") {
    console.warn(
      JSON.stringify({ service: "sendEmail", event: "raffle_email_blocked", reason: decision.reason, lojaId: lojaId || null }),
    );
    return { status: 200, json: blockedJson(decision.reason) };
  }
  if (decision.action === "duplicate") return { status: 200, json: duplicateJson() };

  let displayName = "MasterPalm";
  if (lojaId) {
    try {
      const lojaSnap = await db.collection(colLojas).doc(lojaId).get();
      if (lojaSnap.exists) {
        const lojaData = lojaSnap.data() || {};
        const nome = String(lojaData.nome || lojaData.name || "").trim();
        if (nome) displayName = nome;
      }
    } catch (e) {
      console.warn("[sendEmail] falha ao resolver nome da loja:", lojaId, e?.message || e);
    }
  }

  try {
    await sendMail({
      from: `"${displayName}" <${smtpUser}>`,
      to,
      subject,
      html: html || undefined,
      text: text || undefined,
    });
  } catch (e) {
    if (decision.claim) await decision.claim.release();
    throw e;
  }
  return { status: 200, json: { ok: true, sent: true, message: "Email enviado" } };
}

/** Núcleo do sendWhatsAppOrderConfirmation após validação/rate-limit. */
export async function executeSendWhatsApp({ db, colLojas = "lojas", body, lojaId, phone, message, send, agora = new Date() }) {
  const decision = await evaluateRaffleNotification(db, {
    colLojas,
    channel: "whatsapp",
    body,
    texts: [message],
    recipient: { phone },
    agora,
  });
  if (decision.action === "duplicate") return { status: 200, json: duplicateJson() };

  let outgoing = String(message);
  if (decision.action === "block") {
    const stripped = stripRaffleLines(outgoing);
    console.warn(
      JSON.stringify({ service: "sendWhatsAppOrderConfirmation", event: "raffle_whatsapp_blocked", reason: decision.reason, lojaId }),
    );
    if (hasRaffleMarkers(stripped) || !ORDER_SIGNAL.test(normalizeForMarkers(stripped))) {
      return { status: 200, json: blockedJson(decision.reason) };
    }
    outgoing = stripped;
  }

  try {
    await send(lojaId, phone, outgoing);
  } catch (e) {
    if (decision.claim) await decision.claim.release();
    throw e;
  }
  return {
    status: 200,
    json: {
      ok: true,
      sent: true,
      message: "Mensagem enviada",
      ...(decision.action === "block" ? { raffleRemoved: true, code: RAFFLE_NOT_ACTIVE } : {}),
    },
  };
}
