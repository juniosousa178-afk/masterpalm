/**
 * Extrai o username do Instagram de uma URL ou string
 */
export function extractInstagramUsername(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    const match = trimmed.match(/instagram\.com\/([^/?]+)/i);
    return match ? match[1].replace(/\/$/, "") : "";
  }
  return trimmed.replace(/^@/, "").split("/")[0].trim();
}

/**
 * Retorna URL do Instagram que abre no app nativo no celular.
 * Android: intent URL (abre no app)
 * iOS: instagram:// (abre no app)
 * Desktop: https (abre no navegador)
 */
export function getInstagramAppUrl(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "https://instagram.com";
  const username = extractInstagramUsername(trimmed);
  if (!username) return trimmed.startsWith("http") ? trimmed : `https://instagram.com/${trimmed.replace(/^@/, "")}`;

  const webUrl = `https://www.instagram.com/${username}/`;

  if (typeof window === "undefined") return webUrl;

  const ua = navigator.userAgent || "";
  const isAndroid = /Android/i.test(ua);
  const isIOS = /iPhone|iPad|iPod/i.test(ua);

  if (isAndroid) {
    const fallback = encodeURIComponent(webUrl);
    return `intent://www.instagram.com/${username}/#Intent;scheme=https;package=com.instagram.android;S.browser_fallback_url=${fallback};end`;
  }
  if (isIOS) {
    return `instagram://user?username=${username}`;
  }
  return webUrl;
}

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
