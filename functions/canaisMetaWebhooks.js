/* ============================================================================
   CANAIS META - Webhooks para WhatsApp, Instagram e Messenger
   - Resposta automática a 10 intents
   - Busca de produtos no Firestore
   - Handover para humano
   - Horário comercial
   - Multi-tenant (cada loja com suas credenciais)
   ============================================================================ */

import { onRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { AsyncLocalStorage } from "node:async_hooks";
import {
  validateWhatsAppPostBody,
  validateWhatsAppChangeValue,
  validateTextMessage,
} from "./src/whatsapp_agent/webhookSecurityValidator.js";
import { resolveWhatsAppStoreByPhoneNumberId } from "./src/whatsapp_agent/channelResolverIndex.js";
import { buildMinimalFactualContext } from "./src/whatsapp_agent/minimalFactualContextBuilder.js";
import { isAlreadyProcessed } from "./src/whatsapp_agent/messageDeduper.js";
import { logWhatsAppWebhook } from "./src/whatsapp_agent/requestSafeLogger.js";
import { loadState, saveState } from "./src/whatsapp_agent/conversationStateStore.js";
import { resolveImplicitReference } from "./src/whatsapp_agent/implicitReferenceResolver.js";

/** Lazy: evita getFirestore() antes de initializeApp() no deploy/analyze */
function getDb() {
  return getFirestore();
}

// Configuração global
setGlobalOptions({
  region: "southamerica-east1",
  maxInstances: 10,
});

/** fetch com timeout para evitar espera infinita */
async function fetchWithTimeout(url, opts = {}, timeoutMs = 15000) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...opts, signal: controller.signal });
    clearTimeout(id);
    return res;
  } catch (e) {
    clearTimeout(id);
    if (e.name === "AbortError") throw new Error(`Request timeout after ${timeoutMs}ms`);
    throw e;
  }
}

const VERIFY_TOKEN = "masterpalm_verify_2026";

/** Intents de produto que usam query para searchProducts (FASE 3: merge com estado) */
const PRODUCT_INTENTS = new Set([
  "PRODUCT_PRICE",
  "PRODUCT_STOCK",
  "PRODUCT_SIZE",
  "PRODUCT_COLOR",
  "PRODUCT_PHOTO",
  "PRODUCT_DESCRIPTION",
]);

// Captura opcional (scope por request) dos produtos retornados por searchProducts
// para permitir atualização de estado (FASE 4) sem alterar textos do rule-based.
const productCaptureStorage = new AsyncLocalStorage();

// ============================================================================
// HELPERS - Classificação de Intents
// ============================================================================

function normalizeText(text) {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
}

function classifyIntent(messageText) {
  const text = normalizeText(messageText);

  // GREETING
  if (/^(oi|ola|olá|bom dia|boa tarde|boa noite|hey|opa)/i.test(text)) {
    return { intent: "GREETING", confidence: 0.9 };
  }

  // HANDOVER (falar com humano)
  if (/(atendente|humano|pessoa|funcionario|funcionário|alguem|alguém)/i.test(text)) {
    return { intent: "HANDOVER", confidence: 0.95 };
  }

  // PRODUCT_PRICE
  if (/(quanto custa|preço|valor|preco|quanto fica|quanto é|quanto e)/i.test(text)) {
    return { intent: "PRODUCT_PRICE", confidence: 0.8, query: text };
  }

  // PRODUCT_STOCK
  if (/(tem em estoque|disponivel|disponível|tem esse|tem esta|tem este)/i.test(text)) {
    return { intent: "PRODUCT_STOCK", confidence: 0.8, query: text };
  }

  // PRODUCT_SIZE
  if (/(tamanho|tam|medida|p m g|gg|pp|numero|número)/i.test(text)) {
    return { intent: "PRODUCT_SIZE", confidence: 0.7, query: text };
  }

  // PRODUCT_COLOR
  if (/(cor|cores|colorido|preto|branco|azul|vermelho|verde|amarelo|rosa)/i.test(text)) {
    return { intent: "PRODUCT_COLOR", confidence: 0.7, query: text };
  }

  // PRODUCT_PHOTO
  if (/(foto|imagem|picture|pic|manda foto|quero ver|mostra)/i.test(text)) {
    return { intent: "PRODUCT_PHOTO", confidence: 0.8, query: text };
  }

  // PRODUCT_DESCRIPTION
  if (/(detalhe|descri[cç]|como é|caracteristica|especifica[cç])/i.test(text)) {
    return { intent: "PRODUCT_DESCRIPTION", confidence: 0.7, query: text };
  }

  // SHIPPING
  if (/(frete|entreg|envio|enviar|quanto fica o frete|cep)/i.test(text)) {
    return { intent: "SHIPPING", confidence: 0.8 };
  }

  // PAYMENT
  if (/(pagamento|pagar|cart[aã]o|pix|boleto|dinheiro|aceita)/i.test(text)) {
    return { intent: "PAYMENT", confidence: 0.8 };
  }

  // BUSINESS_HOURS
  if (/(horario|horário|funciona|abre|fecha|aberto|fechado)/i.test(text)) {
    return { intent: "BUSINESS_HOURS", confidence: 0.8 };
  }

  // Default: não identificado
  return { intent: "UNKNOWN", confidence: 0.3 };
}

// ============================================================================
// HELPERS - Busca de Produtos
// ============================================================================

async function searchProducts(lojaId, query) {
  try {
    const normalized = normalizeText(query);
    const keywords = normalized.split(/\s+/).filter(w => w.length > 2);

    if (keywords.length === 0) {
      return [];
    }

    const productsRef = getDb()
      .collection("lojas")
      .doc(lojaId)
      .collection("produtos");

    const snapshot = await productsRef
      .where("ativo", "==", true)
      .limit(50)
      .get();

    if (snapshot.empty) {
      return [];
    }

    const results = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      const searchableText = normalizeText(
        `${data.nome || ""} ${data.descricao || ""} ${data.categoria || ""}`
      );

      let score = 0;
      keywords.forEach(keyword => {
        if (searchableText.includes(keyword)) {
          score += 1;
        }
      });

      if (score > 0) {
        results.push({
          id: doc.id,
          score,
          ...data,
        });
      }
    });

    // Ordenar por score
    results.sort((a, b) => b.score - a.score);
    const top = results.slice(0, 5); // Top 5

    // Captura opcional dos produtos retornados
    const store = productCaptureStorage.getStore();
    if (store && typeof store.captureFn === "function") {
      try {
        store.captureFn(top);
      } catch (_) {
        // nunca impedir o fluxo do bot
      }
    }

    return top;
  } catch (error) {
    console.error("Erro ao buscar produtos:", error);
    return [];
  }
}

// ============================================================================
// HELPERS - Composição de Respostas
// ============================================================================

async function composeResponse(lojaId, intent, messageText) {
  const { intent: intentType, query } = intent;

  switch (intentType) {
    case "GREETING":
      return "👋 Olá! Bem-vindo! Como posso ajudar você hoje? Estou aqui para responder sobre nossos produtos, preços, estoque e muito mais!";

    case "HANDOVER":
      // Marcar para handover humano
      return "🙋 Entendi! Vou transferir você para um de nossos atendentes. Por favor, aguarde um momento.";

    case "PRODUCT_PRICE": {
      if (!query) {
        return "💰 Para consultar preços, por favor me diga qual produto você procura. Exemplo: 'Quanto custa a camisa polo?'";
      }

      const products = await searchProducts(lojaId, query);
      if (products.length === 0) {
        return "😕 Desculpe, não encontrei produtos com essa descrição. Pode tentar com outras palavras?";
      }

      let response = "💰 *Produtos encontrados:*\n\n";
      products.forEach((p, idx) => {
        const price = p.preco ? `R$ ${p.preco.toFixed(2)}` : "Preço sob consulta";
        response += `${idx + 1}. *${p.nome}*\n   💵 ${price}\n\n`;
      });

      return response;
    }

    case "PRODUCT_STOCK": {
      if (!query) {
        return "📦 Para consultar estoque, me diga qual produto você procura. Exemplo: 'Tem camisa polo em estoque?'";
      }

      const products = await searchProducts(lojaId, query);
      if (products.length === 0) {
        return "😕 Não encontrei esse produto. Pode tentar com outras palavras?";
      }

      let response = "📦 *Disponibilidade:*\n\n";
      products.forEach((p, idx) => {
        const stock = p.estoque > 0 ? `✅ ${p.estoque} unidades` : "❌ Fora de estoque";
        response += `${idx + 1}. *${p.nome}*\n   ${stock}\n\n`;
      });

      return response;
    }

    case "PRODUCT_SIZE": {
      if (!query) {
        return "📏 Para consultar tamanhos, me diga qual produto você procura.";
      }

      const products = await searchProducts(lojaId, query);
      if (products.length === 0) {
        return "😕 Não encontrei esse produto.";
      }

      let response = "📏 *Tamanhos disponíveis:*\n\n";
      products.forEach((p, idx) => {
        const sizes = p.tamanhos?.join(", ") || p.tamanho || "Tamanho único";
        response += `${idx + 1}. *${p.nome}*\n   ${sizes}\n\n`;
      });

      return response;
    }

    case "PRODUCT_COLOR": {
      if (!query) {
        return "🎨 Para consultar cores, me diga qual produto você procura.";
      }

      const products = await searchProducts(lojaId, query);
      if (products.length === 0) {
        return "😕 Não encontrei esse produto.";
      }

      let response = "🎨 *Cores disponíveis:*\n\n";
      products.forEach((p, idx) => {
        const colors = p.cores?.join(", ") || p.cor || "Cor padrão";
        response += `${idx + 1}. *${p.nome}*\n   ${colors}\n\n`;
      });

      return response;
    }

    case "PRODUCT_PHOTO": {
      if (!query) {
        return "📸 Para ver fotos, me diga qual produto você procura.";
      }

      const products = await searchProducts(lojaId, query);
      if (products.length === 0) {
        return "😕 Não encontrei esse produto.";
      }

      // Por enquanto, retorna texto. Implementação de envio de imagem requer adapter específico
      let response = "📸 *Produtos encontrados:*\n\n";
      products.forEach((p, idx) => {
        const image = p.imagens?.[0] || p.imagemUrl || "Sem imagem";
        response += `${idx + 1}. *${p.nome}*\n   🔗 ${image}\n\n`;
      });

      return response;
    }

    case "PRODUCT_DESCRIPTION": {
      if (!query) {
        return "📝 Para ver detalhes, me diga qual produto você procura.";
      }

      const products = await searchProducts(lojaId, query);
      if (products.length === 0) {
        return "😕 Não encontrei esse produto.";
      }

      let response = "📝 *Detalhes dos produtos:*\n\n";
      products.forEach((p, idx) => {
        const desc = p.descricao || "Sem descrição disponível";
        response += `${idx + 1}. *${p.nome}*\n   ${desc.substring(0, 150)}...\n\n`;
      });

      return response;
    }

    case "SHIPPING":
      return "🚚 *Frete e Entrega:*\n\nCalculamos o frete no checkout baseado no seu CEP. Trabalhamos com Correios e transportadoras.\n\nDigite seu CEP que calculo para você!";

    case "PAYMENT":
      return "💳 *Formas de Pagamento:*\n\n✅ PIX (desconto)\n✅ Cartão de crédito\n✅ Boleto bancário\n✅ Mercado Pago\n\nPagamentos aprovados na hora!";

    case "BUSINESS_HOURS":
      return "🕐 *Horário de Atendimento:*\n\n📅 Segunda a Sexta: 9h às 18h\n📅 Sábado: 9h às 13h\n📅 Domingo: Fechado\n\nFora do horário, deixe sua mensagem que respondemos em breve!";

    default:
      return "🤖 Desculpe, não entendi. Posso ajudar com:\n\n• Preços e estoque\n• Tamanhos e cores\n• Fotos dos produtos\n• Frete e pagamento\n• Horário de atendimento\n\nO que você gostaria de saber?";
  }
}

// ============================================================================
// HELPERS - Envio de Mensagens
// ============================================================================

async function sendWhatsAppMessage(phoneNumberId, accessToken, to, message) {
  const url = `https://graph.facebook.com/v18.0/${phoneNumberId}/messages`;

  const response = await fetchWithTimeout(
    url,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: to,
        type: "text",
        text: { body: message },
      }),
    },
    15000
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`WhatsApp API Error: ${error}`);
  }

  return await response.json();
}

async function sendInstagramMessage(recipientId, pageAccessToken, message) {
  const url = `https://graph.facebook.com/v18.0/me/messages`;

  const response = await fetchWithTimeout(
    url,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${pageAccessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        recipient: { id: recipientId },
        message: { text: message },
      }),
    },
    15000
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Instagram API Error: ${error}`);
  }

  return await response.json();
}

async function sendMessengerMessage(recipientId, pageAccessToken, message) {
  const url = `https://graph.facebook.com/v18.0/me/messages`;

  const response = await fetchWithTimeout(
    url,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${pageAccessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        recipient: { id: recipientId },
        message: { text: message },
      }),
    },
    15000
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Messenger API Error: ${error}`);
  }

  return await response.json();
}

// ============================================================================
// HELPERS - Identificação de Loja
// ============================================================================

async function findLojaByChannel(channel, channelId) {
  try {
    // Buscar em todas as lojas para encontrar qual tem esse canal configurado
    const lojasSnapshot = await getDb().collection("lojas").get();

    for (const lojaDoc of lojasSnapshot.docs) {
      const canalDoc = await getDb()
        .collection("lojas")
        .doc(lojaDoc.id)
        .collection("canais")
        .doc(channel)
        .get();

      if (canalDoc.exists) {
        const data = canalDoc.data();
        if (data.enabled) {
          // Para WhatsApp, comparar phone_number_id
          if (channel === "whatsapp" && data.phone_number_id === channelId) {
            return { lojaId: lojaDoc.id, config: data };
          }
          // Para Instagram, comparar ig_business_account_id
          if (channel === "instagram" && data.ig_business_account_id === channelId) {
            return { lojaId: lojaDoc.id, config: data };
          }
          // Para Messenger, comparar page_id
          if (channel === "messenger" && data.page_id === channelId) {
            return { lojaId: lojaDoc.id, config: data };
          }
        }
      }
    }

    return null;
  } catch (error) {
    console.error("Erro ao buscar loja:", error);
    return null;
  }
}

// ============================================================================
// WEBHOOK: WhatsApp
// ============================================================================

export const webhookWhatsApp = onRequest(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (req, res) => {
  // Log seguro: sem req.body (Lote 1)
  logWhatsAppWebhook(req.method);

  // GET: Verificação do webhook (inalterado)
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    if (mode === "subscribe" && token === VERIFY_TOKEN) {
      console.log("✅ WhatsApp webhook verificado");
      return res.status(200).send(challenge);
    } else {
      console.error("❌ Verificação falhou");
      return res.sendStatus(403);
    }
  }

  // POST: Processar mensagem (endurecido Lote 1)
  if (req.method === "POST") {
    const body = req.body;

    try {
      const postValidation = validateWhatsAppPostBody(body);
      if (!postValidation.valid) {
        logWhatsAppWebhook("POST", { event: "rejected", reason: postValidation.reason });
        return res.sendStatus(200);
      }
      if (postValidation.reason === "no entries") {
        return res.sendStatus(200);
      }

      if (body.object === "whatsapp_business_account") {
        for (const entry of body.entry || []) {
          for (const change of entry.changes || []) {
            if (change.field === "messages") {
              const value = change.value;
              const valueValidation = validateWhatsAppChangeValue(value);
              if (!valueValidation.valid) continue;
              const phoneNumberId = valueValidation.phoneNumberId;

              // Resolução sem varredura, com fallback defensivo
              let lojaInfo = await resolveWhatsAppStoreByPhoneNumberId(getDb, phoneNumberId);
              if (!lojaInfo) {
                lojaInfo = await findLojaByChannel("whatsapp", phoneNumberId);
              }
              if (!lojaInfo) {
                logWhatsAppWebhook("POST", { phoneNumberId, event: "loja_not_found" });
                continue;
              }

              const { lojaId, config } = lojaInfo;

              for (const message of value.messages || []) {
                const msgValidation = validateTextMessage(message);
                if (!msgValidation.valid) continue;

                const { from, messageText, messageId } = msgValidation;
                let effectiveMessageText = messageText;

                if (messageId && isAlreadyProcessed(messageId)) {
                  logWhatsAppWebhook("POST", { phoneNumberId, from, messageId, event: "skipped_duplicate" });
                  continue;
                }

                let state = null;
                try {
                  state = await loadState(getDb, lojaId, from);
                } catch (_) {
                  state = null;
                }

                // Referencia implícita (FASE 4), sem IA e sem obrigar estado.
                let implicitResolved = false;
                let resolvedImplicitProduct = null;
                try {
                  const implicit = resolveImplicitReference(effectiveMessageText, state);
                  if (implicit?.resolved && implicit?.rewrittenQuery) {
                    implicitResolved = true;
                    resolvedImplicitProduct = implicit.product || null;
                    effectiveMessageText = implicit.rewrittenQuery;
                  }
                } catch (_) {
                  // falha silenciosa: segue fluxo normal (Lote 1 + FASE 3)
                }

                let intent = classifyIntent(effectiveMessageText);

                // Se era referência implícita, reaproveita o último intent de produto (sem mudar textos do bot).
                if (
                  implicitResolved &&
                  state?.lastIntent &&
                  PRODUCT_INTENTS.has(state.lastIntent)
                ) {
                  intent = {
                    ...intent,
                    intent: state.lastIntent,
                    query: effectiveMessageText,
                  };
                }

                // Merge de query (FASE 3) apenas quando NÃO for referência implícita
                if (
                  !implicitResolved &&
                  state?.lastQuery &&
                  PRODUCT_INTENTS.has(intent?.intent) &&
                  intent?.query
                ) {
                  const mergedQuery = (state.lastQuery + " " + (intent.query || "").trim()).trim().slice(0, 120);
                  if (mergedQuery.length > 0) {
                    intent = { ...intent, query: mergedQuery };
                  }
                }

                buildMinimalFactualContext(lojaId, intent, effectiveMessageText);

                let capturedProducts = null;
                const responseText = await productCaptureStorage.run(
                  {
                    captureFn: (products) => {
                      capturedProducts = products;
                    },
                  },
                  async () => composeResponse(lojaId, intent, effectiveMessageText)
                );

                await sendWhatsAppMessage(
                  phoneNumberId,
                  config.access_token,
                  from,
                  responseText
                );

                if (from) {
                  const lastProducts =
                    Array.isArray(capturedProducts) && capturedProducts.length > 0
                      ? capturedProducts
                          .slice(0, 5)
                          .map((p) => ({ id: p?.id, nome: p?.nome, preco: p?.preco }))
                      : undefined;
                  const lastSelectedProduct =
                    implicitResolved && resolvedImplicitProduct
                      ? {
                          id: resolvedImplicitProduct?.id,
                          nome: resolvedImplicitProduct?.nome,
                          preco: resolvedImplicitProduct?.preco,
                        }
                      : undefined;

                  await saveState(getDb, lojaId, from, {
                    lastIntent: intent?.intent || "UNKNOWN",
                    lastQuery: PRODUCT_INTENTS.has(intent?.intent) && intent?.query
                      ? String(intent.query).trim().slice(0, 120)
                      : null,
                    lastProducts,
                    lastSelectedProduct,
                  });
                }

                logWhatsAppWebhook("POST", {
                  phoneNumberId,
                  from,
                  messageId,
                  intentType: intent?.intent,
                  event: "processed",
                });
              }
            }
          }
        }
      }

      return res.sendStatus(200);
    } catch (error) {
      console.error("❌ Erro ao processar WhatsApp:", error);
      return res.sendStatus(500);
    }
  }

  return res.sendStatus(405);
});

// ============================================================================
// WEBHOOK: Instagram
// ============================================================================

export const webhookInstagram = onRequest(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (req, res) => {
  console.log("📥 Instagram Webhook:", req.method, req.query, req.body);

  // GET: Verificação
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    if (mode === "subscribe" && token === VERIFY_TOKEN) {
      console.log("✅ Instagram webhook verificado");
      return res.status(200).send(challenge);
    } else {
      return res.sendStatus(403);
    }
  }

  // POST: Processar mensagem
  if (req.method === "POST") {
    const body = req.body;

    try {
      if (body.object === "instagram") {
        for (const entry of body.entry || []) {
          const igBusinessAccountId = entry.id;

          // Buscar loja
          const lojaInfo = await findLojaByChannel("instagram", igBusinessAccountId);
          if (!lojaInfo) {
            console.warn("⚠️ Loja não encontrada para IG account:", igBusinessAccountId);
            continue;
          }

          const { lojaId, config } = lojaInfo;

          for (const messaging of entry.messaging || []) {
            if (messaging.message && messaging.message.text) {
              const senderId = messaging.sender.id;
              const messageText = messaging.message.text;

              console.log(`📨 Instagram de ${senderId}: ${messageText}`);

              const intent = classifyIntent(messageText);
              const responseText = await composeResponse(lojaId, intent, messageText);

              await sendInstagramMessage(
                senderId,
                config.page_access_token,
                responseText
              );

              console.log("✅ Resposta Instagram enviada");
            }
          }
        }
      }

      return res.sendStatus(200);
    } catch (error) {
      console.error("❌ Erro Instagram:", error);
      return res.sendStatus(500);
    }
  }

  return res.sendStatus(405);
});

// ============================================================================
// WEBHOOK: Messenger
// ============================================================================

export const webhookMessenger = onRequest(
  { timeoutSeconds: 30, memory: "256MiB" },
  async (req, res) => {
  console.log("📥 Messenger Webhook:", req.method, req.query, req.body);

  // GET: Verificação
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    if (mode === "subscribe" && token === VERIFY_TOKEN) {
      console.log("✅ Messenger webhook verificado");
      return res.status(200).send(challenge);
    } else {
      return res.sendStatus(403);
    }
  }

  // POST: Processar mensagem
  if (req.method === "POST") {
    const body = req.body;

    try {
      if (body.object === "page") {
        for (const entry of body.entry || []) {
          const pageId = entry.id;

          // Buscar loja
          const lojaInfo = await findLojaByChannel("messenger", pageId);
          if (!lojaInfo) {
            console.warn("⚠️ Loja não encontrada para page:", pageId);
            continue;
          }

          const { lojaId, config } = lojaInfo;

          for (const messaging of entry.messaging || []) {
            if (messaging.message && messaging.message.text) {
              const senderId = messaging.sender.id;
              const messageText = messaging.message.text;

              console.log(`📨 Messenger de ${senderId}: ${messageText}`);

              const intent = classifyIntent(messageText);
              const responseText = await composeResponse(lojaId, intent, messageText);

              await sendMessengerMessage(
                senderId,
                config.page_access_token,
                responseText
              );

              console.log("✅ Resposta Messenger enviada");
            }
          }
        }
      }

      return res.sendStatus(200);
    } catch (error) {
      console.error("❌ Erro Messenger:", error);
      return res.sendStatus(500);
    }
  }

  return res.sendStatus(405);
});
