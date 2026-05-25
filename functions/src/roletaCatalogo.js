import crypto from "node:crypto";

import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

const COLLECTION_LOJAS = "lojas";
const CONFIG_COLLECTION = "config";
const ROLETA_CONFIG_DOC = "roleta_sorte";

function toInt(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function toNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

export function normalizeRoletaTipo(raw) {
  const tipo = String(raw ?? "").trim().toLowerCase();
  if (tipo === "desconto_percentual") return "desconto";
  return tipo;
}

export function normalizePremioRoleta(raw, index) {
  const original = raw && typeof raw === "object" ? raw : {};
  const label = String(original.label ?? "").trim() || `Prêmio ${index + 1}`;
  const tipo = normalizeRoletaTipo(original.tipo);

  return {
    label,
    tipo,
    valor: Math.max(0, toNumber(original.valor, 0)),
    ativo: original.ativo !== false,
    quantidadeMaxima: Math.max(0, toInt(original.quantidadeMaxima, 0)),
    quantidadeUsada: Math.max(0, toInt(original.quantidadeUsada, 0)),
    diasValidade: Math.max(1, toInt(original.diasValidade, 30)),
  };
}

export function normalizePremiosRoleta(rawPremios) {
  if (!Array.isArray(rawPremios)) return [];
  return rawPremios.map((premio, index) => normalizePremioRoleta(premio, index));
}

function normalizeLojaId(lojaId) {
  const value = String(lojaId ?? "").trim();
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{1,119}$/.test(value)) {
    throw new HttpsError("invalid-argument", "lojaId inválido.");
  }
  return value;
}

function normalizeTotalCarrinho(totalCarrinho) {
  if (totalCarrinho == null) return null;
  const value = Number(totalCarrinho);
  if (!Number.isFinite(value) || value < 0) {
    throw new HttpsError("invalid-argument", "totalCarrinho inválido.");
  }
  return value;
}

function formatCurrencyBr(value) {
  return Number(value).toFixed(2).replace(".", ",");
}

function findFallbackNenhumIndex(premios) {
  const nenhumAtivoIndex = premios.findIndex((premio) => premio.ativo && premio.tipo === "nenhum");
  if (nenhumAtivoIndex >= 0) return nenhumAtivoIndex;

  const nenhumIndex = premios.findIndex((premio) => premio.tipo === "nenhum");
  if (nenhumIndex >= 0) return nenhumIndex;

  const ativoIndex = premios.findIndex((premio) => premio.ativo);
  if (ativoIndex >= 0) return ativoIndex;

  return 0;
}

function buildBusinessResponse(status, message, extra = {}) {
  return {
    ok: false,
    status,
    message,
    ...extra,
  };
}

export function gerarCodigoCupomTemporario() {
  return crypto.randomBytes(4).toString("hex").toUpperCase();
}

export function avaliarGiroRoleta({ config, totalCarrinho }) {
  if (!config || typeof config !== "object") {
    return buildBusinessResponse("config_invalid", "A roleta não está disponível no momento.");
  }

  const ativa = config.ativa === true;
  if (!ativa) {
    return buildBusinessResponse("inactive", "A roleta não está disponível no momento.");
  }

  const valorMinimo = Math.max(0, toNumber(config.valorMinimo, 0));
  if (totalCarrinho != null && totalCarrinho < valorMinimo) {
    const faltante = Math.max(0, valorMinimo - totalCarrinho);
    return buildBusinessResponse(
      "below_minimum",
      `Adicione mais R$ ${formatCurrencyBr(faltante)} ao carrinho para girar a roleta!`,
      { valorMinimo }
    );
  }

  const premios = normalizePremiosRoleta(config.premios);
  if (premios.length === 0) {
    return buildBusinessResponse("no_prizes", "A roleta está sem prêmios configurados.");
  }

  const possuiPremioAtivo = premios.some((premio) => premio.ativo);
  if (!possuiPremioAtivo) {
    return buildBusinessResponse("no_active_prizes", "A roleta está indisponível no momento.");
  }

  const frequenciaPremio = Math.max(1, toInt(config.frequenciaPremio, 10));
  const vendasDesdePremioAtual = Math.max(0, toInt(config.vendasDesdePremio, 0));
  const totalVendasAtual = Math.max(0, toInt(config.totalVendas, 0));
  const thresholdAtingido = vendasDesdePremioAtual >= frequenciaPremio - 1;

  let ganhou = false;
  let premioIndex = findFallbackNenhumIndex(premios);

  if (thresholdAtingido) {
    const elegiveis = [];
    for (let i = 0; i < premios.length; i += 1) {
      const premio = premios[i];
      if (!premio.ativo) continue;
      if (premio.tipo === "nenhum") continue;

      const quantidadeDisponivel =
        premio.quantidadeMaxima === 0 || premio.quantidadeUsada < premio.quantidadeMaxima;
      if (quantidadeDisponivel) {
        elegiveis.push(i);
      }
    }

    if (elegiveis.length > 0) {
      premioIndex = elegiveis[0];
      ganhou = true;
      premios[premioIndex] = {
        ...premios[premioIndex],
        quantidadeUsada: premios[premioIndex].quantidadeUsada + 1,
      };
    }
  }

  const premio = premios[premioIndex] ?? premios[0];
  const totalVendas = totalVendasAtual + 1;
  const vendasDesdePremio = thresholdAtingido ? 0 : vendasDesdePremioAtual + 1;
  const codigoCupomTemporario =
    ganhou && premio?.tipo === "desconto" ? gerarCodigoCupomTemporario() : null;

  return {
    ok: true,
    status: "ok",
    ganhou,
    premioIndex,
    premio,
    premios,
    totalVendas,
    vendasDesdePremio,
    frequenciaPremio,
    valorMinimo,
    codigoCupomTemporario,
  };
}

export async function runGirarRoletaCatalogo(db, { lojaId, totalCarrinho }) {
  const lojaIdNormalizado = normalizeLojaId(lojaId);
  const totalCarrinhoNormalizado = normalizeTotalCarrinho(totalCarrinho);
  const docRef = db
    .collection(COLLECTION_LOJAS)
    .doc(lojaIdNormalizado)
    .collection(CONFIG_COLLECTION)
    .doc(ROLETA_CONFIG_DOC);

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(docRef);
    if (!snap.exists || !snap.data()) {
      return buildBusinessResponse("config_not_found", "A roleta não está disponível no momento.");
    }

    const resultado = avaliarGiroRoleta({
      config: snap.data(),
      totalCarrinho: totalCarrinhoNormalizado,
    });

    if (!resultado.ok) {
      return resultado;
    }

    transaction.update(docRef, {
      totalVendas: resultado.totalVendas,
      vendasDesdePremio: resultado.vendasDesdePremio,
      premios: resultado.premios,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      ...resultado,
      lojaId: lojaIdNormalizado,
    };
  });
}
