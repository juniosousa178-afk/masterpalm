// Script de teste para validar classificação de intents
// Execute: node test-webhooks.js

function normalizeText(text) {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
}

function classifyIntent(messageText) {
  const text = normalizeText(messageText);

  if (/^(oi|ola|olá|bom dia|boa tarde|boa noite|hey|opa)/i.test(text)) {
    return { intent: "GREETING", confidence: 0.9 };
  }

  if (/(atendente|humano|pessoa|funcionario|funcionário|alguem|alguém)/i.test(text)) {
    return { intent: "HANDOVER", confidence: 0.95 };
  }

  if (/(quanto custa|preço|valor|preco|quanto fica|quanto é|quanto e)/i.test(text)) {
    return { intent: "PRODUCT_PRICE", confidence: 0.8, query: text };
  }

  if (/(tem em estoque|disponivel|disponível|tem esse|tem esta|tem este)/i.test(text)) {
    return { intent: "PRODUCT_STOCK", confidence: 0.8, query: text };
  }

  if (/(tamanho|tam|medida|p m g|gg|pp|numero|número)/i.test(text)) {
    return { intent: "PRODUCT_SIZE", confidence: 0.7, query: text };
  }

  if (/(cor|cores|colorido|preto|branco|azul|vermelho|verde|amarelo|rosa)/i.test(text)) {
    return { intent: "PRODUCT_COLOR", confidence: 0.7, query: text };
  }

  if (/(foto|imagem|picture|pic|manda foto|quero ver|mostra)/i.test(text)) {
    return { intent: "PRODUCT_PHOTO", confidence: 0.8, query: text };
  }

  if (/(detalhe|descri[cç]|como é|caracteristica|especifica[cç])/i.test(text)) {
    return { intent: "PRODUCT_DESCRIPTION", confidence: 0.7, query: text };
  }

  if (/(frete|entreg|envio|enviar|quanto fica o frete|cep)/i.test(text)) {
    return { intent: "SHIPPING", confidence: 0.8 };
  }

  if (/(pagamento|pagar|cart[aã]o|pix|boleto|dinheiro|aceita)/i.test(text)) {
    return { intent: "PAYMENT", confidence: 0.8 };
  }

  if (/(horario|horário|funciona|abre|fecha|aberto|fechado)/i.test(text)) {
    return { intent: "BUSINESS_HOURS", confidence: 0.8 };
  }

  return { intent: "UNKNOWN", confidence: 0.3 };
}

// ========== TESTES ==========

console.log("\n🧪 TESTE DE CLASSIFICAÇÃO DE INTENTS\n");

const testMessages = [
  "Olá!",
  "Bom dia, tudo bem?",
  "Quanto custa a camisa polo?",
  "Tem em estoque?",
  "Quais tamanhos disponíveis?",
  "Quais cores tem?",
  "Manda foto do produto",
  "Como é esse produto?",
  "Quanto fica o frete?",
  "Aceita cartão?",
  "Qual o horário de funcionamento?",
  "Quero falar com um atendente",
  "Isso é um teste aleatório",
];

testMessages.forEach((msg, idx) => {
  const result = classifyIntent(msg);
  const emoji = result.intent === "UNKNOWN" ? "❓" : "✅";
  console.log(`${emoji} ${idx + 1}. "${msg}"`);
  console.log(`   → Intent: ${result.intent} (confidence: ${result.confidence})`);
  if (result.query) {
    console.log(`   → Query: ${result.query}`);
  }
  console.log("");
});

console.log("\n✅ Testes concluídos!\n");
console.log("📝 Para testar em produção:");
console.log("   1. Deploy: firebase deploy --only functions");
console.log("   2. Configure webhook na Meta Developers");
console.log("   3. Envie mensagem pelo WhatsApp/Instagram/Messenger");
console.log("   4. Veja logs: firebase functions:log\n");
