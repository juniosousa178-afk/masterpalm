/**
 * IA para a loja: sugestão de descrição e chat de dicas.
 * Usa Gemini (gratuito) por padrão; OpenAI (ChatGPT, pago) como alternativa.
 * Secrets: GEMINI_API_KEY (recomendado) e/ou OPENAI_API_KEY.
 */

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta";
// Modelos atuais (gemini-2.0-flash pode retornar 404 em alguns projetos/regiões)
const GEMINI_MODELS = ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"];

const OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions";
const OPENAI_MODEL = "gpt-4o-mini";

const MSG_QUOTA_GEMINI =
  "Limite de uso do Gemini excedido. Tente em alguns minutos ou use em Google AI Studio.";

function mensagemAmigavelGemini(status, errBody) {
  try {
    const j = JSON.parse(errBody);
    const msg = (j?.error?.message || "").toLowerCase();
    if (status === 404 || msg.includes("not found") || msg.includes("não encontrado")) {
      return "Modelo Gemini não disponível para esta chave. Crie uma chave em Google AI Studio (aistudio.google.com) e ative a API Generative Language.";
    }
    if (status === 403 || msg.includes("permission") || msg.includes("forbidden")) {
      return "Chave do Gemini inválida ou API não ativada. Verifique em aistudio.google.com/app/apikey e ative a API.";
    }
    if (status === 401 || msg.includes("invalid") || msg.includes("api key")) {
      return "Chave do Gemini (GEMINI_API_KEY) inválida. Gere uma nova em aistudio.google.com/app/apikey.";
    }
    if (status === 429 || msg.includes("quota") || msg.includes("resource_exhausted")) {
      return MSG_QUOTA_GEMINI;
    }
  } catch (_) {}
  return `Erro Gemini (${status}). Verifique a chave em Google AI Studio.`;
}

/**
 * Junta todo o texto retornado pelo Gemini (vários `parts` = resposta longa; usar só [0] cortava no meio).
 */
function extractGeminiCandidateText(data) {
  const cand = data?.candidates?.[0];
  if (!cand) return null;
  const parts = cand.content?.parts;
  if (!Array.isArray(parts)) return null;
  const chunks = [];
  for (const p of parts) {
    if (p && typeof p.text === "string" && p.text.length) chunks.push(p.text);
  }
  if (chunks.length === 0) return null;
  const joined = chunks.join("");
  const fr = cand.finishReason;
  if (fr === "MAX_TOKENS") {
    console.warn("[aiLoja] Gemini finishReason=MAX_TOKENS — considere aumentar maxOutputTokens ou encurtar o prompt.");
  }
  return joined.trim();
}

/**
 * Chama o Gemini generateContent (REST). Tenta vários modelos se um retornar 404.
 */
async function generateWithGemini(apiKey, prompt, systemInstruction) {
  const body = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0.7, maxOutputTokens: 8192 },
  };
  if (systemInstruction) body.systemInstruction = { parts: [{ text: systemInstruction }] };

  let lastError;
  for (const model of GEMINI_MODELS) {
    const url = `${GEMINI_BASE}/models/${model}:generateContent`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const errBody = await res.text();
    if (res.ok) {
      const data = JSON.parse(errBody);
      const text = extractGeminiCandidateText(data);
      if (text) return text;
    }
    lastError = new Error(mensagemAmigavelGemini(res.status, errBody));
    if (res.status === 404) continue;
    throw lastError;
  }
  throw lastError;
}

/**
 * Chama a API OpenAI (ChatGPT) chat/completions.
 */
async function generateWithOpenAI(apiKey, prompt, systemInstruction) {
  const messages = [];
  if (systemInstruction) messages.push({ role: "system", content: systemInstruction });
  messages.push({ role: "user", content: prompt });
  const res = await fetch(OPENAI_CHAT_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey.trim()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      messages,
      max_tokens: 4096,
      temperature: 0.7,
    }),
  });
  const body = await res.text();
  if (!res.ok) {
    const msg = (() => {
      try {
        const j = JSON.parse(body);
        const err = j?.error?.message || body;
        if (res.status === 429 || String(err).toLowerCase().includes("quota")) {
          return "Limite de uso da OpenAI excedido. Tente em alguns minutos.";
        }
        return err.slice(0, 200);
      } catch (_) {
        return body.slice(0, 200);
      }
    })();
    throw new Error(`OpenAI API error ${res.status}: ${msg}`);
  }
  const data = JSON.parse(body);
  const text = data?.choices?.[0]?.message?.content;
  if (!text) throw new Error("Resposta da IA sem texto");
  return text.trim();
}

/** Detecta se o erro é de limite/quota (429) para tentar fallback. */
function isQuotaError(err) {
  const msg = String(err?.message || err).toLowerCase();
  return msg.includes("429") || msg.includes("quota") || msg.includes("excedido") || msg.includes("resource_exhausted");
}

/**
 * Gera texto: OpenAI por padrão (se configurado). Permite escolher via preferirModelo: 'openai' | 'gemini'.
 * Em caso de limite excedido (429), tenta automaticamente a outra API se disponível.
 */
async function generate(openaiKey, geminiKey, prompt, systemInstruction, preferirModelo) {
  const hasGemini = geminiKey && String(geminiKey).trim().length > 0;
  const hasOpenAI = openaiKey && String(openaiKey).trim().length > 0;
  const pref = (preferirModelo || "gemini").toLowerCase();

  const tryOpenAI = () => generateWithOpenAI(String(openaiKey).trim(), prompt, systemInstruction);
  const tryGemini = () => generateWithGemini(String(geminiKey).trim(), prompt, systemInstruction);

  const attempts = [];
  if (pref === "gemini" && hasGemini) {
    attempts.push({ fn: tryGemini, name: "Gemini" });
    // OpenAI desabilitado temporariamente; apenas Gemini.
  } else if (hasOpenAI) {
    attempts.push({ fn: tryOpenAI, name: "OpenAI" });
    if (hasGemini) attempts.push({ fn: tryGemini, name: "Gemini" });
  } else if (hasGemini) {
    attempts.push({ fn: tryGemini, name: "Gemini" });
  }

  if (attempts.length === 0) {
    throw new Error(
      "Nenhuma IA configurada. Configure GEMINI_API_KEY (grátis) em aistudio.google.com/app/apikey ou OPENAI_API_KEY e defina no Firebase Secret Manager."
    );
  }

  const runAttempts = async () => {
    let lastError;
    for (const { fn, name } of attempts) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        if (isQuotaError(e) && attempts.length > 1) {
          console.warn(`[aiLoja] Limite ${name} excedido, tentando fallback...`);
          continue;
        }
        throw e;
      }
    }
    throw lastError;
  };

  const retryDelays = [10000, 20000]; // 10s e 20s (Gemini free: 15 req/min)
  for (let attempt = 0; ; attempt++) {
    try {
      return await runAttempts();
    } catch (e) {
      const delay = retryDelays[attempt];
      if (isQuotaError(e) && delay) {
        console.warn(`[aiLoja] Limite excedido, aguardando ${delay / 1000}s para retry ${attempt + 1}/${retryDelays.length}...`);
        await new Promise((r) => setTimeout(r, delay));
        continue;
      }
      throw e;
    }
  }
}

/**
 * Sugere uma descrição de produto para e-commerce.
 */
export async function sugerirDescricaoProduto(openaiKey, geminiKey, params) {
  const nome = (params.nome || "").trim();
  if (!nome) throw new Error("Nome do produto é obrigatório");
  const categoria = (params.categoria || "").trim() || "Geral";
  const subcategoria = (params.subcategoria || "").trim();
  const prompt = `Gere uma descrição curta e atrativa para um produto de e-commerce em português do Brasil.
Produto: ${nome}
Categoria: ${categoria}${subcategoria ? `\nSubcategoria: ${subcategoria}` : ""}

Requisitos:
- 2 a 4 frases, tom profissional e vendedor
- Destaque benefícios e características que vendem
- Sem emojis, sem título, apenas o parágrafo da descrição
- Resposta contendo somente o texto da descrição, nada mais`;
  return generate(openaiKey, geminiKey, prompt, undefined, params.preferirModelo);
}

/**
 * Chat de dicas e ideias para o dono da loja.
 * modo "tutorial_tela": tutor passo a passo para telas do MasterPalm (nomeTela obrigatório).
 */
export async function chatDicasLoja(openaiKey, geminiKey, params) {
  const historico = Array.isArray(params.historico) ? params.historico : [];
  const modo = (params.modo || "").trim();
  const nomeTela = (params.nomeTela || "").trim();
  const mensagem = (params.mensagem || "").trim();

  if (modo === "tutorial_tela") {
    if (!nomeTela) throw new Error("nomeTela é obrigatório no modo tutorial");
    const systemInstruction = `Você é o tutor oficial do aplicativo MasterPalm (gestão de loja no Brasil: estoque, vendas, catálogo web, pedidos, campanhas e sorteios, roleta da sorte, fretes, cupons, Pix, Mercado Pago, relatórios, vendedores, notas fiscais, integrações).
Responda sempre em português do Brasil, tom didático e acolhedor.
Para o tutorial inicial: seja completo (vários parágrafos permitidos). Use Markdown: ## para seções, listas numeradas nos passos, **negrito** só quando ajudar.
Não invente botões ou menus que não existiriam em um ERP de loja; descreva fluxos plausíveis alinhados ao nome da tela.
Se a tela for "Campanhas e Sorteios", cubra campanhas de sorteio (números por compra) e a Roleta da sorte (prêmios, valor mínimo) como recursos relacionados.`;

    if (historico.length === 0) {
      const prompt = `O lojista abriu a Ajuda e quer aprender a usar esta área do app: "${nomeTela}".

Gere um tutorial com EXATAMENTE estas seções (títulos em Markdown ##):

## Resumo
Um parágrafo: o que essa tela/área faz, para quem é útil.

## Passo a passo
Lista numerada (5 a 12 passos) de como encontrar no app, configurar e usar no dia a dia. Seja específico.

## Exemplos práticos
Dois cenários fictícios com valores (ex.: "Loja de roupas", "pedido de R$ 120") mostrando como usar a funcionalidade.

## Dicas rápidas
Bullet points (4 a 6) com atalhos mentais e boas práticas.

Não use emojis excessivos (no máximo 1 ou 2 no texto inteiro).`;
      return generate(openaiKey, geminiKey, prompt, systemInstruction, params.preferirModelo);
    }

    const contexto = historico
      .slice(-10)
      .map((m) => `${m.role === "user" ? "Lojista" : "Tutor"}: ${m.content}`)
      .join("\n");
    const pergunta = mensagem || "Responda de forma útil e objetiva, mantendo o foco nesta tela.";
    const prompt = `Tela em foco no MasterPalm: "${nomeTela}".

Histórico da conversa:
${contexto}

Pergunta ou pedido de esclarecimento do lojista:
${pergunta}

Responda como Tutor MasterPalm (Markdown permitido).`;
    return generate(openaiKey, geminiKey, prompt, systemInstruction, params.preferirModelo);
  }

  if (!mensagem) throw new Error("Mensagem é obrigatória");
  const systemInstruction = `Você é um assistente especializado em ajudar donos de loja e e-commerce.
Responda sempre em português do Brasil, de forma prática e objetiva.
Dê dicas de vendas, marketing, estoque, atendimento, precificação e ideias para crescer a loja.
Seja conciso (1 a 3 parágrafos) e acolhedor.`;
  let prompt = mensagem;
  if (historico.length > 0) {
    const contexto = historico
      .slice(-10)
      .map((m) => `${m.role === "user" ? "Cliente" : "Assistente"}: ${m.content}`)
      .join("\n");
    prompt = `Histórico da conversa:\n${contexto}\n\nCliente: ${mensagem}\n\nAssistente:`;
  }
  return generate(openaiKey, geminiKey, prompt, systemInstruction, params.preferirModelo);
}

// ---------- Novas funções IA MasterPalm ----------

const SYS_IA_LOJA =
  "Você é um assistente para e-commerce no Brasil. Responda sempre em português, de forma clara e objetiva. Seja conciso.";

/** Sugere título otimizado para produto (curto, palavras-chave). */
export async function sugerirTituloProduto(openaiKey, geminiKey, params) {
  const nome = (params.nome || "").trim();
  if (!nome) throw new Error("Nome do produto é obrigatório");
  const categoria = (params.categoria || "").trim() || "Geral";
  const prompt = `Crie um título de produto otimizado para e-commerce e buscas.
Produto: ${nome}
Categoria: ${categoria}

Requisitos: até 60 caracteres, palavras-chave que vendem, sem emojis. Responda só com o título, nada mais.`;
  return generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
}

/** Gera variações de descrição: para feed, WhatsApp e Instagram. */
export async function sugerirVariacoesDescricao(openaiKey, geminiKey, params) {
  const nome = (params.nome || "").trim();
  const descricaoAtual = (params.descricaoAtual || "").trim();
  if (!nome) throw new Error("Nome do produto é obrigatório");
  const prompt = `Produto: ${nome}
${descricaoAtual ? `Descrição atual: ${descricaoAtual}\n` : ""}

Gere 3 variações de texto em português do Brasil, separadas por "---" (três hífens), na ordem:
1) Para feed/catálogo (2 a 3 frases, tom vendedor)
2) Para WhatsApp (1 a 2 frases, direto)
3) Para legenda Instagram (1 frase + emoji no fim, engajamento)

Cada bloco deve ser só o texto, sem rótulo. Use exatamente "---" entre os blocos.`;
  const text = await generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
  const parts = text.split(/\s*---\s*/).map((s) => s.trim()).filter(Boolean);
  return {
    paraFeed: parts[0] || text,
    paraWhatsApp: parts[1] || parts[0] || text,
    paraInstagram: parts[2] || parts[0] || text,
  };
}

/** Legenda para Instagram/Reels a partir do produto. */
export async function sugerirLegendaInstagram(openaiKey, geminiKey, params) {
  const produtoNome = (params.produtoNome || params.nome || "").trim();
  const descricao = (params.descricao || "").trim();
  if (!produtoNome) throw new Error("Nome do produto é obrigatório");
  const prompt = `Crie uma legenda para post no Instagram/Reels para este produto.
Produto: ${produtoNome}
${descricao ? `Descrição: ${descricao}\n` : ""}

Requisitos: 1 a 2 frases, tom que engaja, pode terminar com 1 ou 2 emojis. Sem hashtags. Responda só a legenda.`;
  return generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
}

/** Mensagem pronta para WhatsApp (pós-venda, recuperação, promoção, novidade). */
export async function sugerirMensagemWhatsApp(openaiKey, geminiKey, params) {
  const tipo = (params.tipo || "promocao").trim();
  const contexto = (params.contexto || "").trim();
  const tipos = {
    posVenda: "mensagem de pós-venda agradecendo a compra e pedindo avaliação",
    recuperacaoCarrinho: "mensagem para recuperar cliente que abandonou carrinho",
    promocao: "mensagem de promoção ou oferta para enviar para clientes",
    novidade: "mensagem anunciando novidade ou novo produto",
  };
  const descricaoTipo = tipos[tipo] || tipos.promocao;
  const prompt = `Gere uma ${descricaoTipo} para WhatsApp.
${contexto ? `Contexto: ${contexto}\n` : ""}

Requisitos: tom amigável, curta (2 a 4 linhas), em português do Brasil. Pode usar 1 ou 2 emojis. Responda só o texto da mensagem.`;
  return generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
}

/** Sugere categoria, subcategoria e tags a partir do nome/descrição. */
export async function sugerirCategoriaSubcategoria(openaiKey, geminiKey, params) {
  const nome = (params.nome || "").trim();
  const descricao = (params.descricao || "").trim();
  if (!nome) throw new Error("Nome do produto é obrigatório");
  const prompt = `Com base no produto abaixo, sugira em uma linha cada, separadas por "---":
1) Categoria (ex: Moda, Eletrônicos, Acessórios)
2) Subcategoria (ex: Anéis, Camisetas)
3) Tags (até 5 palavras-chave separadas por vírgula, para busca)

Produto: ${nome}
${descricao ? `Descrição: ${descricao}\n` : ""}

Responda só as 3 linhas, na ordem, separadas por "---". Sem numeração nem rótulos.`;
  const text = await generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
  const parts = text.split(/\s*---\s*/).map((s) => s.trim()).filter(Boolean);
  const tagsStr = parts[2] || "";
  const tags = tagsStr ? tagsStr.split(/[,;]/).map((t) => t.trim()).filter(Boolean).slice(0, 5) : [];
  return {
    categoria: parts[0] || "Geral",
    subcategoria: parts[1] || "",
    tags,
  };
}

/** Sugestão de promoção para produtos com estoque parado, sazonal ou com pouca saída. */
export async function sugerirPromocaoEstoqueParado(openaiKey, geminiKey, params) {
  const produtos = Array.isArray(params.produtos) ? params.produtos : [];
  const linhas = produtos.length
    ? produtos.map((p) => {
        let linha = `- ${p.nome || "?"} (${p.quantidade ?? 0} un.)`;
        if (p.categoria && String(p.categoria).trim()) linha += ` | categoria: ${p.categoria}`;
        if (p.diasSemVenda != null) linha += ` | ${p.diasSemVenda} dias sem venda`;
        if (p.sazonal === true) linha += " | produto sazonal";
        if (p.observacao && String(p.observacao).trim()) linha += ` | ${p.observacao}`;
        return linha;
      }).join("\n")
    : "(nenhum)";
  const prompt = `Lista de produtos para considerar em promoção (estoque parado, sazonal ou com pouca saída):
${linhas}

Com base nesses produtos (nome, quantidade, categoria, dias sem venda quando houver, e se é sazonal), sugira ações de promoção ou divulgação para escoar o estoque: 2 a 5 frases práticas (ex.: desconto sugerido por categoria, bundle, mensagem para WhatsApp, destaque para produto sazonal). Em português do Brasil.`;
  return generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
}

/** Análise de vendas em linguagem natural: pergunta + resumo de dados. */
export async function analiseVendasNatural(openaiKey, geminiKey, params) {
  const pergunta = (params.pergunta || "").trim();
  const resumoVendas = (params.resumoVendas || "").trim();
  if (!pergunta) throw new Error("Pergunta é obrigatória");
  const prompt = `O dono da loja fez a seguinte pergunta sobre vendas/estoque:
"${pergunta}"

Dados disponíveis (resumo):
${resumoVendas || "(Nenhum dado informado - responda com base apenas na pergunta e dê orientações gerais.)"}

Responda de forma clara e objetiva em português do Brasil. Se os dados não permitirem responder exatamente, diga o que é possível e sugira onde ver no sistema.`;
  return generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
}

/** Atendimento no catálogo: cliente pergunta (estoque, frete, etc.) e IA responde com base no contexto da loja. */
export async function chatAtendimentoCatalogo(openaiKey, geminiKey, params) {
  const pergunta = (params.pergunta || "").trim();
  const contexto = params.contexto || {};
  if (!pergunta) throw new Error("Pergunta é obrigatória");
  const nomeLoja = contexto.nomeLoja || "Loja";
  const temEstoque = contexto.temEstoque != null ? (contexto.temEstoque ? "Sim, temos estoque." : "Não temos no momento.") : "";
  const politicaFrete = contexto.politicaFrete || "";
  const contato = contexto.contato || "";
  const produtoNome = contexto.produtoNome || "";
  const prompt = `Você é o atendente do catálogo da "${nomeLoja}".
O cliente perguntou: "${pergunta}"
${produtoNome ? `Produto em questão: ${produtoNome}\n` : ""}
Contexto da loja:
- Estoque: ${temEstoque || "Não informado."}
- Frete/entrega: ${politicaFrete || "Não informado."}
- Contato: ${contato || "Não informado."}

Responda em 1 a 3 frases, em português do Brasil, de forma amigável. Se não souber, diga para entrar em contato com a loja.`;
  return generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
}

/** Sugestão de preço para combo com base nos itens. */
export async function sugerirPrecoCombo(openaiKey, geminiKey, params) {
  const itens = Array.isArray(params.itens) ? params.itens : [];
  const somaItens = (params.somaItens || 0);
  const prompt = `Lista de itens do combo (nome e preço unitário):
${itens.length ? itens.map((i) => `- ${i.nome || "?"}: R$ ${Number(i.preco ?? 0).toFixed(2)}`).join("\n") : "(vazio)"}
Soma dos itens: R$ ${Number(somaItens).toFixed(2)}

Sugira um preço final de venda para o combo (com desconto atrativo mas que mantenha margem). Responda em uma linha, só o valor sugerido em reais (ex.: "R$ 89,90") e em seguida uma frase curta explicando o desconto.`;
  return generate(openaiKey, geminiKey, prompt, SYS_IA_LOJA, params.preferirModelo);
}
