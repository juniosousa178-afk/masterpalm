/**
 * E-mails automáticos de status de pedido (catálogo) — servidor (SMTP).
 * Acoplado a `lojas/{lojaId}/pre_pedidos/{pedidoId}` com deduplicação em
 * `emailsStatusEnviados` / `emailsStatusEnviadosEm`.
 *
 * O painel admin altera status em `pre_pedidos` (não em `lojas/.../pedidos` do histórico
 * pós-venda). Evita trigger duplicado no mesmo fluxo.
 */
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import nodemailer from "nodemailer";
import { normalizeEmail } from "./mpCatalogPayerBrasil.js";

const COL_LOJAS = "lojas";
const COL_PRE = "pre_pedidos";

/** Campos que ao mudar sozinhos não disparam nova leitura de “transição de status”. */
const IGNORED_FOR_MEANINGFUL = new Set([
  "emailsStatusEnviados",
  "emailsStatusEnviadosEm",
  "dataAtualizacao",
]);

function pedidoCodigoCurto(pedidoId) {
  const s = String(pedidoId || "");
  if (s.length >= 8) return s.slice(0, 8).toUpperCase();
  return s.toUpperCase();
}

function pickCodigoRastreio(data) {
  const a = data || {};
  const c = (a.codigoRastreio ?? a.codigo_rastreio ?? a.rastreio ?? "").toString().trim();
  return c.length > 0 ? c : null;
}

/**
 * Entregas que não exigem código de rastreio (retirada / combinar com vendedor).
 * Exportado para testes.
 */
export function freteExigeRastreio(pedidoData) {
  const f = pedidoData?.frete;
  if (!f || typeof f !== "object") return true;
  const tipo = String(f.tipo ?? "").toLowerCase();
  const nome = String(f.nome ?? "").toLowerCase();
  const blob = `${tipo} ${nome}`;
  const semCorreio = [
    "retirada",
    "retirar",
    "loja",
    "pickup",
    "combinar",
    "vendedor",
    "retira",
    "buscar",
  ];
  for (const w of semCorreio) {
    if (blob.includes(w)) return false;
  }
  return true;
}

function isCatalogoPrePedido(d) {
  if (!d || typeof d !== "object") return false;
  if (String(d.governancaStatus ?? "").trim() === "substituido") return false;
  const o = String(d.origem ?? "").toLowerCase();
  if (o.includes("catalogo")) return true;
  if (String(d.origemCheckout ?? "").trim().length > 0) return true;
  // legado: sem origem (pedidos antigos de catálogo)
  if (!o) return true;
  return false;
}

export function getMeaningfulChangedKeys(beforeData, afterData) {
  const b = beforeData && typeof beforeData === "object" ? beforeData : {};
  const a = afterData && typeof afterData === "object" ? afterData : {};
  const keys = new Set([...Object.keys(b), ...Object.keys(a)]);
  const changed = [];
  for (const k of keys) {
    if (IGNORED_FOR_MEANINGFUL.has(k)) continue;
    const vb = b[k] === undefined ? null : b[k];
    const va = a[k] === undefined ? null : a[k];
    if (JSON.stringify(vb) !== JSON.stringify(va)) changed.push(k);
  }
  return changed;
}

function normalizeStatus(s) {
  return String(s ?? "")
    .toLowerCase()
    .trim();
}

export function statusToTemplateKey(statusRaw) {
  const s = normalizeStatus(statusRaw);
  if (s === "embalando") return "em_preparacao";
  if (s === "em_preparacao") return "em_preparacao";
  if (s === "confirmado") return "confirmado";
  if (s === "enviado") return "enviado";
  if (s === "entregue") return "entregue";
  if (s === "recebido") return "recebido";
  return null;
}

/**
 * Lê `tipoEntregaEnvio` explícito (app admin). Não confundir com [classificarEntregaEnvio].
 */
export function pickTipoEntregaEnvio(data) {
  if (!data || typeof data !== "object") return null;
  const t = String(
    data.tipoEntregaEnvio ?? data.tipo_entrega_envio ?? "",
  )
    .toLowerCase()
    .trim();
  if (t === "local" || t === "entrega_local" || t === "entrega local" || t === "motoboy")
    return "local";
  if (t === "rastreio" || t === "correios" || t === "transportadora" || t === "postagem")
    return "rastreio";
  if (
    t === "retirada" ||
    t === "retirada_ou_combinar" ||
    t === "combinar" ||
    t === "loja" ||
    t === "pickup"
  ) {
    return "retirada";
  }
  return null;
}

/**
 * Coleta texto de campos comuns de modalidade/frete para heurística.
 */
export function coletarBlobModalidadeEntrega(data) {
  if (!data || typeof data !== "object") return "";
  const parts = [];
  const p = (v) => {
    if (v == null) return;
    if (typeof v === "string") {
      if (v.trim().length) parts.push(v);
      return;
    }
    if (typeof v === "object") {
      for (const k of Object.keys(v)) {
        p(v[k]);
      }
    }
  };
  const chaves = [
    "tipoEntrega",
    "modalidadeEntrega",
    "formaEntrega",
    "metodoEntrega",
    "freteNome",
    "freteTipo",
    "entregaTipo",
    "shippingMethod",
    "entregaLocal",
    "retirada",
    "combinar",
  ];
  for (const ch of chaves) {
    p(data[ch]);
  }
  const f = data.frete;
  if (f && typeof f === "object") {
    p(f.tipo);
    p(f.nome);
  }
  return parts.join(" ").toLowerCase();
}

/**
 * Categoria da entrega para o e-mail de "enviado" (não reexportar categoria "local" de retirada).
 * Retornos: "transportadora" | "local" | "retirada_ou_combinar"
 */
export function inferirCategoriaEntrega(data) {
  const blob = coletarBlobModalidadeEntrega(data);
  const c = pickCodigoRastreio(data);
  if (c) {
    return "transportadora";
  }
  if (
    /retirad|retirar|pickup|combinar\s+com|combinar$|vendedor|na\s+loja|loja$|buscar|pick\s*-?\s*up/.test(
      blob,
    )
  ) {
    return "retirada_ou_combinar";
  }
  if (
    /entrega\s+local|entrega\s+pr[oó]pria|motoboy|moto-?boy|delivery\s+local|bike\s*boy|entregador|uber\s*entregas?/.test(
      blob,
    )
  ) {
    return "local";
  }
  if (
    /correio|correios|melhor[\s-]?envio|jadlog|total\s*express|loggi|frenet|transp\.?|transportadora|totvs|tms|sedex|pac|\.br\b|rastreio/.test(
      blob,
    )
  ) {
    return "transportadora";
  }
  if (!freteExigeRastreio(data)) {
    return "retirada_ou_combinar";
  }
  return "transportadora";
}

/**
 * Classifica entrega: explícito do admin (tipoEntregaEnvio) > sinais do pedido.
 */
export function classificarEntregaEnvio(data) {
  const ex = pickTipoEntregaEnvio(data);
  if (ex === "rastreio") return "transportadora";
  if (ex === "local") return "local";
  if (ex === "retirada") return "retirada_ou_combinar";
  return inferirCategoriaEntrega(data);
}

/**
 * Plano de envio do e-mail "enviado" (sempre dedupe em emailsStatusEnviados.enviado).
 */
export function resolveEnviadoSendPlan(after) {
  const c = pickCodigoRastreio(after);
  const categoria = classificarEntregaEnvio(after);

  if (categoria === "transportadora") {
    if (c) {
      return { action: "send", variant: "rastreio", codigo: c };
    }
    return { action: "defer", reason: "transportadora_sem_codigo" };
  }
  if (categoria === "local") {
    return { action: "send", variant: "local" };
  }
  if (categoria === "retirada_ou_combinar") {
    return { action: "send", variant: "retirada" };
  }
  return { action: "defer", reason: "categoria_indefinida" };
}

const TEMPLATES = {
  recebido: {
    assunto: "Recebemos seu pedido 💛",
    corpo: ({ nomeCliente, nomeLoja }) =>
      `Olá, ${nomeCliente}! ✨\n\n` +
      `Que alegria ter você por aqui!\n\n` +
      `Seu pedido foi recebido com sucesso e já chegou para a nossa equipe. Agora vamos cuidar de cada detalhe com muito carinho para que tudo siga da melhor forma possível.\n\n` +
      `Em breve você receberá uma nova atualização por e-mail assim que o pedido for confirmado.\n\n` +
      `Obrigada por escolher a ${nomeLoja}. 💛`,
  },
  confirmado: {
    assunto: "Seu pedido foi confirmado ✨",
    corpo: ({ nomeCliente, nomeLoja }) =>
      `Olá, ${nomeCliente}!\n\n` +
      `Temos uma ótima notícia: seu pedido foi confirmado com sucesso. ✨\n\n` +
      `A partir de agora, nossa equipe dará continuidade ao preparo do seu pedido com todo cuidado e atenção.\n\n` +
      `Assim que ele entrar em preparação, avisaremos você por aqui.\n\n` +
      `Com carinho,\n` +
      `Equipe ${nomeLoja}`,
  },
  em_preparacao: {
    assunto: "Seu pedido está sendo preparado 💝",
    corpo: ({ nomeCliente, nomeLoja }) =>
      `Olá, ${nomeCliente}!\n\n` +
      `Seu pedido já está em preparação. 💝\n\n` +
      `Estamos separando tudo com carinho para que ele chegue até você do jeitinho esperado. Cada detalhe está sendo cuidado com atenção.\n\n` +
      `Assim que o pedido for enviado, avisaremos você por e-mail.\n\n` +
      `Obrigada pela confiança!\n` +
      `Equipe ${nomeLoja}`,
  },
  enviado: {
    assunto: "Seu pedido foi postado 🚚",
    corpo: ({ nomeCliente, nomeLoja, codigoRastreio }) =>
      `Olá, ${nomeCliente}!\n\n` +
      `Seu pedido foi postado e já está a caminho. 🚚✨\n\n` +
      `Código de rastreio:\n` +
      `${codigoRastreio}\n\n` +
      `Agora é só acompanhar a entrega e aguardar mais um pouquinho. Estamos muito felizes em fazer parte desse momento!\n\n` +
      `Com carinho,\n` +
      `Equipe ${nomeLoja}`,
  },
  /** Mesmo e-mail “único” em emailsStatusEnviados.enviado, corpo distinto. */
  enviadoLocal: {
    assunto: "Seu pedido saiu para entrega 🚚✨",
    corpo: ({ nomeCliente, nomeLoja }) =>
      `Olá, ${nomeCliente}!\n\n` +
      `Seu pedido saiu para entrega e dentro de instantes será entregue. 🚚✨\n\n` +
      `Estamos muito felizes em levar seu pedido até você. Preparamos tudo com muito carinho e esperamos que você ame cada detalhe!\n\n` +
      `Com carinho,\n` +
      `Equipe ${nomeLoja}`,
  },
  /** Retirada / combinar — não fala em “saiu para entrega” na rua. */
  enviadoRetirada: {
    assunto: "Seu pedido está pronto para combinar a entrega ✨",
    corpo: ({ nomeCliente, nomeLoja }) =>
      `Olá, ${nomeCliente}!\n\n` +
      `Seu pedido já avançou para a próxima etapa. ✨\n\n` +
      `Como a entrega foi escolhida como retirada ou combinação direta com a loja, nossa equipe seguirá com as orientações combinadas para que você receba tudo da melhor forma possível.\n\n` +
      `Com carinho,\n` +
      `Equipe ${nomeLoja}`,
  },
  entregue: {
    assunto: "Seu pedido foi entregue ✨",
    corpo: ({ nomeCliente, nomeLoja }) =>
      `Olá, ${nomeCliente}!\n\n` +
      `Seu pedido foi entregue. ✨\n\n` +
      `Esperamos que você ame cada detalhe e que sua compra tenha chegado com todo o carinho que preparamos para você.\n\n` +
      `Muito obrigada por confiar na ${nomeLoja}. Será uma alegria atender você novamente!\n\n` +
      `Com carinho,\n` +
      `Equipe ${nomeLoja}`,
  },
};

async function loadLojaNome(db, lojaId) {
  const snap = await db.collection(COL_LOJAS).doc(String(lojaId)).get();
  if (!snap.exists) return "Loja";
  const d = snap.data() || {};
  return String(d.nome || d.name || "Loja").trim() || "Loja";
}

async function getSmtpTransporter(smtpUser, smtpPass) {
  if (!smtpUser || !smtpPass) return null;
  return nodemailer.createTransport({
    service: "gmail",
    auth: { user: smtpUser, pass: smtpPass },
  });
}

function clienteEmailValido(raw) {
  const e = normalizeEmail(raw || "");
  if (!e || !e.includes("@")) return null;
  if (e.startsWith("catalogo+")) return null;
  return e;
}

/**
 * @param {import("firebase-functions/v2/firestore").FirestoreEvent<import("firebase-functions/v2/firestore").Change<import("firebase-admin/firestore").DocumentSnapshot>>} event
 */
export function createOnPrePedidoClienteEmail(S_SMTP_EMAIL, S_SMTP_PASSWORD) {
  return onDocumentWritten(
    {
      document: `${COL_LOJAS}/{lojaId}/${COL_PRE}/{pedidoId}`,
      secrets: [S_SMTP_EMAIL, S_SMTP_PASSWORD],
    },
    async (event) => {
      const lojaId = event.params?.lojaId;
      const pedidoId = event.params?.pedidoId;
      const change = event.data;
      if (!lojaId || !pedidoId || !change) return;

      const beforeSnap = change.before;
      const afterSnap = change.after;
      if (!afterSnap?.exists) return;

      const db = getFirestore();
      const after = afterSnap.data() || {};
      const before = beforeSnap?.exists ? beforeSnap.data() || {} : null;

      if (!isCatalogoPrePedido(after)) {
        return;
      }

      const isCreate = !beforeSnap?.exists;
      if (!isCreate) {
        const changed = getMeaningfulChangedKeys(before, after);
        if (changed.length === 0) {
          return;
        }
      }

      const smtpUser = String((await S_SMTP_EMAIL.value()) || process.env.SMTP_EMAIL || "").trim();
      const smtpPass = String((await S_SMTP_PASSWORD.value()) || process.env.SMTP_PASSWORD || "").trim();
      const transporter = await getSmtpTransporter(smtpUser, smtpPass);
      if (!transporter) {
        console.log(
          "[onPrePedidoClienteEmail] SMTP não configurado — e-mails de status do cliente não enviados",
        );
        return;
      }

      const lojaNome = await loadLojaNome(db, lojaId);
      const cliente = after.cliente && typeof after.cliente === "object" ? after.cliente : {};
      const nomeCliente = String(cliente.nome || "Cliente").trim() || "Cliente";
      const emailCliente = clienteEmailValido(cliente.email);
      const sent = (after.emailsStatusEnviados && typeof after.emailsStatusEnviados === "object"
        ? after.emailsStatusEnviados
        : {}) || {};

      const ref = db.collection(COL_LOJAS).doc(lojaId).collection(COL_PRE).doc(pedidoId);

      async function markSent(key) {
        await ref.update({
          [`emailsStatusEnviados.${key}`]: true,
          [`emailsStatusEnviadosEm.${key}`]: FieldValue.serverTimestamp(),
          dataAtualizacao: FieldValue.serverTimestamp(),
        });
        console.log(
          `[onPrePedidoClienteEmail] Marcado envio único: lojaId=${lojaId} pedidoId=${pedidoId} key=${key}`,
        );
      }

      async function sendForKey(key) {
        if (sent[key] === true) {
          console.log(
            `[onPrePedidoClienteEmail] Já enviado (${key}) — skip lojaId=${lojaId} pedidoId=${pedidoId}`,
          );
          return;
        }
        if (!emailCliente) {
          console.log(
            `[onPrePedidoClienteEmail] Sem emailCliente — skip ${key} lojaId=${lojaId} pedidoId=${pedidoId}`,
          );
          return;
        }
        const T = TEMPLATES[key];
        if (!T) return;
        const corpo = T.corpo({ nomeCliente, nomeLoja: lojaNome });
        try {
          await transporter.sendMail({
            from: `"${lojaNome}" <${smtpUser}>`,
            to: emailCliente,
            subject: T.assunto,
            text: corpo,
          });
          console.log(
            `[onPrePedidoClienteEmail] E-mail ${key} enviado lojaId=${lojaId} pedidoId=${pedidoId} -> ${emailCliente}`,
          );
          await markSent(key);
        } catch (e) {
          console.warn(
            `[onPrePedidoClienteEmail] Falha ao enviar ${key} (não bloqueia):`,
            e?.message || e,
          );
        }
      }

      async function trySendEnviadoEmail() {
        if (statusToTemplateKey(after.status) !== "enviado") return;
        if (sent.enviado === true) {
          return;
        }
        const plan = resolveEnviadoSendPlan(after);
        if (plan.action === "defer") {
          console.log(
            `[onPrePedidoClienteEmail] enviado adiado (${plan.reason}) pedidoId=${pedidoId} lojaId=${lojaId}`,
          );
          return;
        }
        if (!emailCliente) {
          console.log(
            `[onPrePedidoClienteEmail] Sem emailCliente — skip enviado lojaId=${lojaId} pedidoId=${pedidoId}`,
          );
          return;
        }
        const T =
          plan.variant === "local"
            ? TEMPLATES.enviadoLocal
            : plan.variant === "retirada"
              ? TEMPLATES.enviadoRetirada
              : TEMPLATES.enviado;
        if (!T) return;
        const corpo =
          plan.variant === "local" || plan.variant === "retirada"
            ? T.corpo({ nomeCliente, nomeLoja: lojaNome })
            : T.corpo({
                nomeCliente,
                nomeLoja: lojaNome,
                codigoRastreio: plan.codigo || "—",
              });
        try {
          await transporter.sendMail({
            from: `"${lojaNome}" <${smtpUser}>`,
            to: emailCliente,
            subject: T.assunto,
            text: corpo,
          });
          console.log(
            `[onPrePedidoClienteEmail] E-mail enviado (${plan.variant}) pedidoId=${pedidoId} -> ${emailCliente}`,
          );
          await markSent("enviado");
        } catch (e) {
          console.warn(
            "[onPrePedidoClienteEmail] Falha e-mail enviado:",
            e?.message || e,
          );
        }
      }

      // 1) Recebido: criação do pré-pedido
      if (isCreate) {
        await sendForKey("recebido");
        return;
      }

      // 2) Transições por status
      const stBefore = normalizeStatus(before?.status);
      const stAfter = normalizeStatus(after.status);
      const keyAfter = statusToTemplateKey(after.status);

      if (stBefore === stAfter) {
        if (keyAfter === "enviado") {
          await trySendEnviadoEmail();
        }
        return;
      }

      if (!keyAfter || keyAfter === "recebido") return;

      if (keyAfter === "confirmado" || keyAfter === "entregue" || keyAfter === "em_preparacao") {
        await sendForKey(keyAfter);
        return;
      }

      if (keyAfter === "enviado") {
        await trySendEnviadoEmail();
      }
    },
  );
}
