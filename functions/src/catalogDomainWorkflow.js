/**
 * Domínio próprio do catálogo: solicitação (Firestore operacional + mirror em draft_config),
 * verificação DNS (CNAME) e ativação idempotente em catalog_domains (sem confiar no cliente).
 */

import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import dns from "node:dns/promises";

const COL_LOJAS = "lojas";
const COL_DOM_OP = "dominios_catalogo";
const COL_CATALOG_MAP = "catalog_domains";
const DRAFT_COL = "draft_config";
const DRAFT_ID = "config";

export const EXPECTED_CNAME_TARGET = "masterpalm-58c46.web.app";

export function normalizeCatalogDomainInput(raw) {
  let s = String(raw ?? "").trim().toLowerCase();
  if (!s) return "";
  s = s.replace(/^https?:\/\//, "");
  const slash = s.indexOf("/");
  if (slash >= 0) s = s.substring(0, slash);
  const colon = s.indexOf(":");
  if (colon >= 0) s = s.substring(0, colon);
  while (s.endsWith(".")) s = s.substring(0, s.length - 1);
  return s;
}

export function finalCatalogFqdnFromUserInput(normalizedUser) {
  if (!normalizedUser) return "";
  if (normalizedUser.startsWith("catalogo.")) return normalizedUser;
  return `catalogo.${normalizedUser}`;
}

function normDnsTarget(s) {
  let x = String(s ?? "").trim().toLowerCase();
  while (x.endsWith(".")) x = x.substring(0, x.length - 1);
  return x;
}

function isValidCatalogHostname(hostNorm) {
  if (!hostNorm || hostNorm.length > 253) return false;
  const labels = hostNorm.split(".");
  if (labels.length < 2) return false;
  for (const lab of labels) {
    if (!lab || lab.length > 63) return false;
    if (!/^[a-z0-9-]+$/.test(lab)) return false;
    if (lab.startsWith("-") || lab.endsWith("-")) return false;
  }
  return true;
}

async function assertCanManageStore(db, lojaId, auth) {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Login necessário.");
  }
  const uid = auth.uid;
  const lojaIdStr = String(lojaId || "").trim();
  if (!lojaIdStr) {
    throw new HttpsError("invalid-argument", "lojaId é obrigatório.");
  }

  const lojaRef = db.collection(COL_LOJAS).doc(lojaIdStr);
  const lojaSnap = await lojaRef.get();
  if (!lojaSnap.exists) {
    throw new HttpsError("not-found", "Loja não encontrada.");
  }
  const d = lojaSnap.data() || {};
  const owner = (d.ownerUid || "").toString();
  if (owner && owner === uid) return;

  const memSnap = await lojaRef.collection("members").doc(uid).get();
  if (memSnap.exists) {
    const role = (memSnap.data()?.role || "").toString();
    if (role === "owner" || role === "admin") return;
  }

  const userSnap = await db.collection("users").doc(uid).get();
  if (userSnap.exists) {
    const ud = userSnap.data() || {};
    const sid = (ud.store_id ?? ud.storeId ?? "").toString().trim();
    if (sid === lojaIdStr && (!owner || owner === uid)) return;
  }

  throw new HttpsError("permission-denied", "Sem permissão para gerenciar o domínio desta loja.");
}

async function mergeDraftDominio(db, lojaId, { dominioCatalogo, dominioStatus, dominioUpdatedAt, dominioProvider }) {
  const ref = db.collection(COL_LOJAS).doc(lojaId).collection(DRAFT_COL).doc(DRAFT_ID);
  const prov = (dominioProvider ?? "").toString().trim();
  await ref.set(
    {
      dominioCatalogo,
      dominioStatus,
      dominioUpdatedAt,
      dominioProvider: prov,
    },
    { merge: true },
  );
}

export async function runCatalogDomainSubmit(db, { auth, lojaId, dominioUserInput, providerId }) {
  await assertCanManageStore(db, lojaId, auth);
  const userNorm = normalizeCatalogDomainInput(dominioUserInput);
  if (!userNorm) {
    throw new HttpsError("invalid-argument", "Informe o domínio.");
  }
  const hostFinal = finalCatalogFqdnFromUserInput(userNorm);
  if (!isValidCatalogHostname(hostFinal)) {
    throw new HttpsError("invalid-argument", "Domínio inválido.");
  }

  const hostNorm = hostFinal;
  const nowMs = Date.now();
  const uid = auth.uid;
  const lojaIdStr = String(lojaId).trim();
  const opRef = db.collection(COL_LOJAS).doc(lojaIdStr).collection(COL_DOM_OP).doc(hostNorm);

  const provTrim = providerId ? String(providerId).trim() : "";

  await opRef.set(
    {
      host: hostFinal,
      hostNormalized: hostNorm,
      lojaId: lojaIdStr,
      providerId: provTrim || null,
      requestedBy: uid,
      requestedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      status: "solicitado",
      dnsStatus: "nao_verificado",
      dnsObservedTarget: null,
      expectedTarget: EXPECTED_CNAME_TARGET,
      verified: false,
      activatedAt: null,
      lastCheckAt: null,
      lastError: null,
      mode: "subdomain_catalog",
      suggestedSubdomain: hostFinal !== userNorm ? hostFinal : null,
      userInputHost: userNorm,
    },
    { merge: true },
  );

  await mergeDraftDominio(db, lojaIdStr, {
    dominioCatalogo: hostFinal,
    dominioStatus: "solicitado",
    dominioUpdatedAt: nowMs,
    dominioProvider: provTrim,
  });

  return {
    hostFinal,
    userInputHost: userNorm,
    status: "solicitado",
    dominioUpdatedAt: nowMs,
    providerId: provTrim || null,
  };
}

export async function runCatalogDomainVerify(db, { auth, lojaId, hostNormalized }) {
  await assertCanManageStore(db, lojaId, auth);
  const hostNorm = normalizeCatalogDomainInput(hostNormalized);
  if (!hostNorm) {
    throw new HttpsError("invalid-argument", "Host ausente.");
  }
  const lojaIdStr = String(lojaId).trim();
  const opRef = db.collection(COL_LOJAS).doc(lojaIdStr).collection(COL_DOM_OP).doc(hostNorm);
  const opSnap = await opRef.get();
  if (!opSnap.exists) {
    throw new HttpsError(
      "failed-precondition",
      'Solicitação não encontrada. Toque em "Adicionar domínio" antes de verificar.',
    );
  }
  const op = opSnap.data() || {};
  if ((op.lojaId || "").toString().trim() !== lojaIdStr) {
    throw new HttpsError("permission-denied", "Esta solicitação não pertence à loja atual.");
  }

  let dnsObservedJoined = null;
  let dnsDiag = "lookup_failed";

  try {
    const cnames = await dns.resolveCname(hostNorm);
    if (!Array.isArray(cnames) || cnames.length === 0) {
      dnsDiag = "sem_cname";
    } else {
      const targets = cnames.map(normDnsTarget);
      dnsObservedJoined = targets.join(", ");
      const exp = normDnsTarget(EXPECTED_CNAME_TARGET);
      const ok = targets.some((t) => t === exp);
      dnsDiag = ok ? "ok" : "incompativel";
    }
  } catch (e) {
    const code = e?.code;
    console.warn("[catalogDomainVerify] resolveCname", hostNorm, code, e?.message || e);
    if (code === "ENOTFOUND" || code === "ENODATA") {
      dnsDiag = "sem_cname";
    } else {
      dnsDiag = "lookup_failed";
    }
  }

  const ts = FieldValue.serverTimestamp();
  let newStatus;
  let verified = false;
  let lastError = null;
  let activatedAt = null;
  const prov = (op.providerId ?? "").toString().trim();

  if (dnsDiag === "ok") {
    verified = true;
    const mapRef = db.collection(COL_CATALOG_MAP).doc(hostNorm);
    let conflict = false;
    await db.runTransaction(async (tx) => {
      const ms = await tx.get(mapRef);
      if (ms.exists) {
        const ex = (ms.data()?.lojaId || "").toString().trim();
        if (ex && ex !== lojaIdStr) {
          conflict = true;
          return;
        }
      }
      tx.set(
        mapRef,
        {
          host: hostNorm,
          lojaId: lojaIdStr,
          status: "active",
          verified: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });

    if (conflict) {
      newStatus = "erro";
      verified = false;
      dnsDiag = "conflito_mapa";
      lastError = "Este domínio já está vinculado a outra loja. Entre em contato com o suporte.";
    } else {
      newStatus = "ativo";
      activatedAt = ts;
    }
  } else if (dnsDiag === "lookup_failed") {
    newStatus = "erro";
    verified = false;
    lastError = "Não foi possível consultar o DNS agora. Tente novamente em alguns minutos.";
  } else {
    newStatus = "pendente_dns";
    verified = false;
    if (dnsDiag === "incompativel") {
      lastError = `O CNAME precisa apontar para ${EXPECTED_CNAME_TARGET}. Observado: ${dnsObservedJoined || "—"}.`;
    } else {
      lastError = `Não encontramos um CNAME válido para ${hostNorm}. Confira o provedor e aguarde a propagação.`;
    }
  }

  await opRef.set(
    {
      dnsStatus: dnsDiag,
      dnsObservedTarget: dnsObservedJoined,
      expectedTarget: EXPECTED_CNAME_TARGET,
      verified,
      status: newStatus,
      lastCheckAt: ts,
      updatedAt: ts,
      lastError: lastError || null,
      activatedAt: activatedAt || null,
    },
    { merge: true },
  );

  const nowMs = Date.now();
  await mergeDraftDominio(db, lojaIdStr, {
    dominioCatalogo: hostNorm,
    dominioStatus: newStatus,
    dominioUpdatedAt: nowMs,
    dominioProvider: prov,
  });

  return {
    hostNormalized: hostNorm,
    status: newStatus,
    dnsStatus: dnsDiag,
    dnsObservedTarget: dnsObservedJoined,
    expectedTarget: EXPECTED_CNAME_TARGET,
    verified,
    lastError: lastError || null,
    dominioUpdatedAt: nowMs,
  };
}
