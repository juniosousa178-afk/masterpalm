/**
 * Diagnóstico read-only da config MP em lojas/{lojaId}/config/payments.
 * Usa a mesma política de token que createPreference/mpCatalogPayment (mpLojaTokenPolicy.js).
 * Não expõe segredos — apenas comprimentos e flags.
 */

import { resolveStrictLojaMpAccessToken } from "./mpLojaTokenPolicy.js";

/** Espelha getLojaPaymentConfig (index.js): token efetivo para validação estrita. */
export function effectiveMpTokenFromPaymentsData(data) {
  if (!data || typeof data !== "object") return "";
  const mp = data.mp;
  if (mp && typeof mp === "object") {
    const a = String(mp.access_token ?? "").trim();
    const b = String(mp.token ?? "").trim();
    if (a) return a;
    if (b) return b;
  }
  return String(data.mp_access_token ?? "").trim();
}

/**
 * @param {string|null|undefined} publicKey
 * @returns {'missing'|'pk_prefixed'|'looks_like_access_token'|'other'}
 */
export function publicKeyShape(publicKey) {
  const pk = publicKey == null ? "" : String(publicKey).trim();
  if (!pk) return "missing";
  if (pk.startsWith("pk_live_") || pk.startsWith("pk_test_")) return "pk_prefixed";
  if (pk.startsWith("APP_USR-")) return "looks_like_access_token";
  return "other";
}

/**
 * Classifica o documento config/payments para rollout / saneamento (sem writes).
 *
 * status (exclusivo, ordem de prioridade):
 * - estado_inconclusivo
 * - connected_sem_token
 * - missing_token
 * - invalid_format
 * - token_presente_sem_identidade
 * - token_manual_sem_public_key_real
 * - ok_token_loja_valido
 *
 * @param {object|null|undefined} data — snapshot .data() de config/payments
 */
export function classifyLojaMpPaymentsData(data) {
  if (data == null || typeof data !== "object") {
    return {
      status: "estado_inconclusivo",
      wouldFailMpLojaTokenRequired: true,
      tokenLen: 0,
      connected: false,
      hasEmail: false,
      hasUserId: false,
      hasNickname: false,
      publicKeyShape: "missing",
      motivoPrincipal: "documento_ausente_ou_invalido",
      suggestedAction: "Revisar se config/payments existe para a loja.",
    };
  }

  const mp = data.mp && typeof data.mp === "object" ? data.mp : {};
  const connected = mp.connected === true;
  const hasEmail = String(mp.email ?? "").trim().length > 0;
  const hasUserId = String(mp.user_id ?? "").trim().length > 0;
  const hasNickname = String(mp.nickname ?? "").trim().length > 0;
  const hasIdentity = hasEmail || hasUserId || hasNickname;

  const effective = effectiveMpTokenFromPaymentsData(data);
  const strict = resolveStrictLojaMpAccessToken({ token: effective });
  const tokenLen = effective.length;
  const pkShape = publicKeyShape(mp.public_key);

  const wouldFail = !strict.ok;

  if (connected && wouldFail) {
    return {
      status: "connected_sem_token",
      wouldFailMpLojaTokenRequired: true,
      tokenLen,
      connected: true,
      hasEmail,
      hasUserId,
      hasNickname,
      publicKeyShape: pkShape,
      motivoPrincipal: "mp_connected_true_sem_token_aceitavel",
      suggestedAction:
        "Desconectar no app e configurar Access Token de produção (APP_USR-…) ou reconectar OAuth.",
    };
  }

  if (strict.reason === "missing") {
    return {
      status: "missing_token",
      wouldFailMpLojaTokenRequired: true,
      tokenLen: 0,
      connected,
      hasEmail,
      hasUserId,
      hasNickname,
      publicKeyShape: pkShape,
      motivoPrincipal: "sem_access_token_efetivo_em_mp_ou_legado",
      suggestedAction: "Configurar Access Token de produção em Pagamentos.",
    };
  }

  if (strict.reason === "invalid_format") {
    return {
      status: "invalid_format",
      wouldFailMpLojaTokenRequired: true,
      tokenLen,
      connected,
      hasEmail,
      hasUserId,
      hasNickname,
      publicKeyShape: pkShape,
      motivoPrincipal: "token_presente_mais_formato_nao_aceito_pela_politica",
      suggestedAction: "Substituir por Access Token de produção válido (APP_USR-…, tamanho adequado).",
    };
  }

  if (!hasIdentity) {
    return {
      status: "token_presente_sem_identidade",
      wouldFailMpLojaTokenRequired: false,
      tokenLen,
      connected,
      hasEmail,
      hasUserId,
      hasNickname,
      publicKeyShape: pkShape,
      motivoPrincipal: "token_valido_sem_email_user_nickname",
      suggestedAction:
        "Reconectar conta MP ou concluir fluxo manual para repor identidade (users/me). Pagamento loja pode funcionar.",
    };
  }

  if (pkShape === "missing" || pkShape === "looks_like_access_token") {
    return {
      status: "token_manual_sem_public_key_real",
      wouldFailMpLojaTokenRequired: false,
      tokenLen,
      connected,
      hasEmail,
      hasUserId,
      hasNickname,
      publicKeyShape: pkShape,
      motivoPrincipal:
        pkShape === "missing"
          ? "sem_public_key_para_exibicao_cliente"
          : "public_key_parece_access_token_antigo",
      suggestedAction:
        "Opcional: reconectar OAuth para pk_live; fluxo server-side de pedido segue com access token da loja.",
    };
  }

  return {
    status: "ok_token_loja_valido",
    wouldFailMpLojaTokenRequired: false,
    tokenLen,
    connected,
    hasEmail,
    hasUserId,
    hasNickname,
    publicKeyShape: pkShape,
    motivoPrincipal: "token_e_config_coerentes_com_politica_endurecida",
    suggestedAction: "Nenhuma ação necessária para erro MP_LOJA_TOKEN_REQUIRED.",
  };
}
