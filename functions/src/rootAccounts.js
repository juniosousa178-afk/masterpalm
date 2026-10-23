/**
 * Conta root/programador (plano lifetime no backend, mesma lista que lib/utils/role_utils.dart).
 * Manter sincronizado com `rootEmails` em Dart e `isRootAdmin` em firestore.rules/storage.rules.
 * Só e-mails cuja caixa é controlada pela plataforma; nunca domínios de terceiros.
 */
export const ROOT_ACCOUNT_EMAILS = Object.freeze([
  "masterpalm26@gmail.com",
]);

export function isRootAccountEmail(email) {
  const n = String(email ?? "").trim().toLowerCase();
  return ROOT_ACCOUNT_EMAILS.includes(n);
}

/** Autoridade de plataforma num pedido autenticado: e-mail root com `email_verified === true` no ID token. */
export function isPlatformAdminToken(token) {
  return token?.email_verified === true && isRootAccountEmail(token?.email);
}

/** E-mail principal usado em scripts legados — também está em ROOT_ACCOUNT_EMAILS */
export const ROOT_EMAIL = "masterpalm26@gmail.com";
