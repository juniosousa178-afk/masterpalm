/**
 * Payer (comprador) Mercado Pago — catálogo BR / PIX.
 *
 * Única fonte de regras de e-mail e CPF para `mpCatalogPayment` (type=pix),
 * alinhada ao app Flutter: `lib/screens/public_catalog/catalog_helpers.dart`
 * (e-mail) e [catalogIsValidCpfForMpPayer] (CPF com dígitos verificadores).
 * Alterações aqui ou no app devem manter o par equivalente.
 */

import { extractCatalogOrderBuyer } from "./catalogMpOrderHelpers.js";

export function normalizeEmail(value) {
  return String(value || "")
    .trim()
    .toLowerCase();
}

/** E-mail mínimo aceitável pelo Checkout/PIX MP (evita invalid_params por formato). */
export function isPlausibleBuyerEmailForMp(s) {
  const e = normalizeEmail(s);
  if (e.length < 6 || e.length > 254) return false;
  const at = e.indexOf("@");
  if (at < 1) return false;
  const domain = e.slice(at + 1);
  if (domain.length < 3 || !domain.includes(".")) return false;
  return true;
}

/** CPF: 11 dígitos e dígitos verificadores válidos. */
export function isValidCpfDigits(digits) {
  const s = String(digits || "").replace(/\D/g, "");
  if (s.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(s)) return false;
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += parseInt(s[i], 10) * (10 - i);
  let r = (sum * 10) % 11;
  if (r === 10) r = 0;
  if (r !== parseInt(s[9], 10)) return false;
  sum = 0;
  for (let i = 0; i < 10; i++) sum += parseInt(s[i], 10) * (11 - i);
  r = (sum * 10) % 11;
  if (r === 10) r = 0;
  return r === parseInt(s[10], 10);
}

/**
 * Monta objeto [payer] base a partir do pedido catálogo (Firestore).
 * E-mail: fallback `catalogo+{id}@mastepalm.com.br` se o do pedido for inválido.
 */
export function buildMpBuyerPayerForCatalog(order, orderId) {
  const { name, email, cpf, telefone } = extractCatalogOrderBuyer(order);
  const displayName = (name || "Cliente").trim().slice(0, 100) || "Cliente";
  let payerEmail = normalizeEmail(email);
  if (!isPlausibleBuyerEmailForMp(payerEmail)) {
    const id = String(orderId || "pedido")
      .replace(/[^a-z0-9_-]/gi, "")
      .slice(0, 48) || "pedido";
    payerEmail = `catalogo+${id}@mastepalm.com.br`;
  }
  const cpfDigits = String(cpf || "").replace(/\D/g, "");
  const payer = { name: displayName, email: payerEmail };
  if (cpfDigits.length === 11 && isValidCpfDigits(cpfDigits)) {
    payer.identification = { type: "CPF", number: cpfDigits };
  }
  const tel = String(telefone || "").replace(/\D/g, "");
  let d = tel;
  if (d.startsWith("55") && d.length > 11) d = d.slice(2);
  if (d.length >= 10 && d.length <= 11) {
    const ac = d.slice(0, 2);
    const num = d.slice(2);
    if (/^\d{2}$/.test(ac) && num.length >= 8 && num.length <= 9) {
      payer.phone = { area_code: ac, number: num };
    }
  }
  return payer;
}

const PIX_CPF_ERR =
  "CPF inválido para gerar o PIX. Confira o CPF no checkout (11 dígitos, sem erros) e tente novamente.";

/**
 * Resolve e-mail + CPF canônicos para o POST /v1/payments (payment_method_id=pix).
 * CPF do body do request tem prioridade; senão CPF já válido vindo do pedido (payer do servidor).
 */
export function resolveCatalogPixPayerForMp({ body, order, orderId }) {
  const email = body?.email;
  const cpf = body?.cpf;
  const serverPayer = buildMpBuyerPayerForCatalog(order, orderId);
  const emailBody = normalizeEmail(email);
  let emailStr = isPlausibleBuyerEmailForMp(emailBody) ? emailBody : serverPayer.email;
  if (!isPlausibleBuyerEmailForMp(emailStr)) {
    emailStr = serverPayer.email;
  }
  const cpfBody = cpf != null && cpf !== "" ? String(cpf).replace(/\D/g, "") : "";
  const fromServerId = serverPayer.identification?.number
    ? String(serverPayer.identification.number).replace(/\D/g, "")
    : "";
  let cpfLimpo = "";
  if (cpfBody.length === 11 && isValidCpfDigits(cpfBody)) {
    cpfLimpo = cpfBody;
  } else if (fromServerId.length === 11 && isValidCpfDigits(fromServerId)) {
    cpfLimpo = fromServerId;
  }
  if (cpfLimpo.length !== 11) {
    return { ok: false, code: "PIX_CPF_INVALID", error: PIX_CPF_ERR };
  }
  return { ok: true, emailStr, cpfLimpo, serverPayer };
}
