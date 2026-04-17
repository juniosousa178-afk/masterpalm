/**
 * Espelha config/payments → payments_public sem segredos (alinhado ao Dart PagamentosService.stripSecretsFromPaymentsMap).
 */

export function stripPaymentsSecretsForPublic(raw) {
  const out = raw && typeof raw === "object" ? JSON.parse(JSON.stringify(raw)) : {};
  if (out.mp && typeof out.mp === "object") {
    const m = { ...out.mp };
    delete m.access_token;
    delete m.token;
    delete m.refresh_token;
    out.mp = m;
  }
  if (out.pagseguro && typeof out.pagseguro === "object") {
    const p = { ...out.pagseguro };
    delete p.token;
    out.pagseguro = p;
  }
  if (out.ton && typeof out.ton === "object") {
    const t = { ...out.ton };
    delete t.client_secret;
    out.ton = t;
  }
  if (out.infinitpay && typeof out.infinitpay === "object") {
    const i = { ...out.infinitpay };
    delete i.api_key;
    out.infinitpay = i;
  }
  return out;
}
