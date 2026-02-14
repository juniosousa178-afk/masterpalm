/**
 * Normaliza URL do Instagram para formato válido.
 * Aceita: "username", "@username", "instagram.com/username", "https://instagram.com/username"
 */
export function normalizeInstagramUrl(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";

  // Já é URL completa
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    return trimmed.replace(/\/+$/, ""); // remove trailing slash
  }

  // Extrai o username (remove @, instagram.com/, etc.)
  let username = trimmed
    .replace(/^@/, "")
    .replace(/^https?:\/\/(www\.)?instagram\.com\//i, "")
    .replace(/\/.*$/, "")
    .trim();

  if (!username) return trimmed;

  return `https://instagram.com/${username}`;
}

/**
 * Verifica se o e-mail parece válido para mailto
 */
export function isValidEmail(value: string): boolean {
  const trimmed = value.trim();
  if (trimmed.length < 5 || !trimmed.includes("@")) return false;
  // Placeholder do config
  if (trimmed.includes("SEUDOMINIO") || trimmed.includes("SEU-")) return false;
  return true;
}

/**
 * Gera href mailto seguro - só usa quando e-mail é válido
 */
export function getMailtoHref(email: string): string {
  const trimmed = email.trim();
  if (!isValidEmail(trimmed)) return "#";
  return `mailto:${trimmed}`;
}
