/**
 * Contas root/programador (plano lifetime no backend, mesma lista que lib/utils/role_utils.dart).
 * Manter sincronizado com `rootEmails` em Dart.
 */
export const ROOT_ACCOUNT_EMAILS = Object.freeze([
  "masterpalm26@gmail.com",
  "masterpalm@gmail.com",
  "admin@masterpalm.com",
]);

export function isRootAccountEmail(email) {
  const n = String(email ?? "").trim().toLowerCase();
  return ROOT_ACCOUNT_EMAILS.includes(n);
}

/** E-mail principal usado em scripts legados — também está em ROOT_ACCOUNT_EMAILS */
export const ROOT_EMAIL = "masterpalm@gmail.com";
