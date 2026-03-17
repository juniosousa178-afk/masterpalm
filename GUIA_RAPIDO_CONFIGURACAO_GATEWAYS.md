# 🚀 Guia Rápido: Configuração de Gateways (1-2 minutos cada)

## 📱 Mercado Pago

### Passo 1: Obter Credenciais
1. Tocar em 🌐 ou "Obter Credenciais" na tela
2. Fazer login no Mercado Pago
3. Ir em "Suas integrações" → "Aplicações"
4. Copiar **Access Token** (produção)

### Passo 2: Configurar
1. Tocar em "Conectar Mercado Pago" (OAuth recomendado)
   - OU colar token em "Public Key"
2. Tocar em "Salvar"

### Passo 3: Validar
1. Tocar em "Testar Conexão"
2. Aguardar confirmação ✅

**Tempo total: ~1 minuto**

---

## 💳 PagSeguro

### Passo 1: Obter Token
1. Tocar em "Gerar Token" na tela
2. Fazer login no PagSeguro
3. Ir em "Integrações" → "Token de Segurança"
4. Gerar novo token
5. Copiar token

### Passo 2: Configurar
1. Colar **Token** no campo
2. Digitar **Seller ID** (email da conta)
3. Tocar em "Salvar"

### Passo 3: Validar
1. Tocar em "Testar"
2. Confirmar ✅ sucesso

**Tempo total: ~1 minuto**

---

## 🏪 Ton

### Passo 1: Obter Credenciais
1. Tocar em "Portal Desenvolvedor" na tela
2. Fazer login na Ton
3. Ir em "Aplicações" → "Nova Aplicação"
4. Copiar **Client ID** e **Client Secret**

### Passo 2: Configurar
1. Colar **Client ID**
2. Colar **Client Secret**
3. Tocar em "Salvar"

### Passo 3: Validar
1. Tocar em "Testar"
2. Aguardar validação OAuth2 ✅

**Tempo total: ~2 minutos**

---

## 💰 InfinitePay

### Passo 1: Obter API Key
1. Tocar em "Gerar API Key" na tela
2. Fazer login no InfinitePay
3. Ir em "Configurações" → "API"
4. Gerar nova chave
5. Copiar **API Key** e **Merchant ID**

### Passo 2: Configurar
1. Colar **API Key**
2. Colar **Merchant ID**
3. Tocar em "Salvar"

### Passo 3: Validar
1. Tocar em "Testar"
2. Confirmar ✅ funcionando

**Tempo total: ~1 minuto**

---

## ⚡ Atalhos Úteis

### Links Diretos das Plataformas

| Gateway | Dashboard | Credenciais | Docs |
|---------|-----------|-------------|------|
| **Mercado Pago** | [Dashboard](https://www.mercadopago.com.br/developers/panel) | [Credenciais](https://www.mercadopago.com.br/developers/panel/app) | [Docs](https://www.mercadopago.com.br/developers/pt/docs) |
| **PagSeguro** | [Integrações](https://pagseguro.uol.com.br/preferencias/integracoes.jhtml) | [Tokens](https://pagseguro.uol.com.br/preferencias/integracoes.jhtml) | [API Ref](https://dev.pagseguro.uol.com.br/reference) |
| **Ton** | [Portal](https://www.ton.com.br) | [Developers](https://www.ton.com.br/desenvolvedores) | [Docs](https://dev.stone.com.br/docs) |
| **InfinitePay** | [Dashboard](https://minhaconta.infinitepay.io) | [API Settings](https://minhaconta.infinitepay.io/configuracoes/integracao) | [Developers](https://dev.infinitepay.io) |

### Na tela do app, todos esses links estão a 1 toque de distância! 🚀

---

## ✅ Checklist de Configuração Completa

### Mercado Pago
- [ ] Obter Access Token
- [ ] Conectar via OAuth OU salvar Public Key
- [ ] Testar conexão ✅
- [ ] Ver confirmação verde

### PagSeguro
- [ ] Gerar token
- [ ] Salvar Token + Seller ID
- [ ] Testar ✅
- [ ] Ver confirmação verde

### Ton
- [ ] Criar aplicação
- [ ] Salvar Client ID + Secret
- [ ] Testar ✅
- [ ] Ver confirmação verde

### InfinitePay
- [ ] Gerar API Key
- [ ] Salvar API Key + Merchant ID
- [ ] Testar ✅
- [ ] Ver confirmação verde

### Checkout Padrão
- [ ] Escolher gateway padrão
- [ ] Configurar chave PIX
- [ ] Salvar configurações

---

## 🎯 Dicas de Ouro

### 1. Use navegação em abas
- Mantenha o app e o painel do gateway abertos simultaneamente
- Troque entre eles rapidamente (Alt+Tab no PC, App Switcher no mobile)

### 2. Sempre teste antes de usar
- Não pule o botão "Testar"
- 10 segundos de validação economizam horas de debug

### 3. Configure um de cada vez
- Complete 100% um gateway antes de passar para outro
- Evita confusão entre credenciais

### 4. Guarde as credenciais
- Use um gerenciador de senhas
- Salve screenshots (em local seguro)
- Facilita reconfigurações futuras

### 5. Ambiente correto
- **Produção**: Use tokens de produção (pagamentos reais)
- **Teste**: Use tokens sandbox quando disponível (desenvolvimento)

---

## 🚨 Troubleshooting Rápido

### "Teste falhou" ❌

**Causa comum:** Token de sandbox em ambiente de produção
- **Solução:** Use token de PRODUÇÃO

**Causa comum:** Token expirado
- **Solução:** Gere novo token na plataforma

**Causa comum:** Conta não ativa
- **Solução:** Verifique status da conta no painel do gateway

### "Link não abre" 🔗

**Solução 1:** Copie URL manualmente da documentação
**Solução 2:** Verifique permissões do app para abrir URLs
**Solução 3:** Atualize o app

### "Não encontro as credenciais" 🔍

**Solução:** Use os botões de link direto na tela do app
- Eles te levam EXATAMENTE onde você precisa estar

---

## ⏱️ Tempo Total de Configuração

| Cenário | Tempo |
|---------|-------|
| 1 gateway | ~1-2 min |
| 2 gateways | ~2-4 min |
| 3 gateways | ~3-6 min |
| 4 gateways (todos) | ~5-8 min |

**Antes das melhorias:** 1-2 HORAS para 4 gateways
**Depois das melhorias:** 5-8 MINUTOS para 4 gateways

**Economia: ~95%** ⚡

---

## 🎓 Sequência Recomendada

Para vendedores iniciantes:

1. **Comece com PIX Manual** (mais simples)
   - Configure apenas chave PIX
   - Teste com primeiros pedidos

2. **Adicione Mercado Pago** (mais popular)
   - OAuth é mais fácil
   - Grande cobertura no Brasil

3. **Expanda com PagSeguro** (segunda opção)
   - Boa alternativa ao MP
   - Aceito em todo Brasil

4. **Considere Ton** (maquininhas)
   - Se já usa maquininha Ton
   - Integração unificada

5. **Opte por InfinitePay** (moderno)
   - Taxas competitivas
   - API moderna e rápida

---

## 📊 Qual Gateway Escolher?

| Critério | Mercado Pago | PagSeguro | Ton | InfinitePay |
|----------|--------------|-----------|-----|-------------|
| **Popularidade** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Facilidade** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Taxas** | Média | Média | Baixa | Baixa |
| **PIX** | ✅ | ✅ | ✅ | ✅ |
| **Boleto** | ✅ | ✅ | ❌ | ❌ |
| **Cartão** | ✅ | ✅ | ✅ | ✅ |
| **OAuth** | ✅ | ❌ | ✅ | ❌ |

**Recomendação:** Configure pelo menos 2 gateways para ter backup!

---

## 🎉 Conclusão

Com esta nova interface:
- ⚡ Configuração em **minutos** (não horas)
- ✅ Validação **instantânea** (não tentativa e erro)
- 🔗 Links **diretos** (não buscar no Google)
- 📖 Docs **integradas** (não procurar ajuda)

**Resultado:** Experiência profissional e sem frustrações! 🚀

---

*Imprima este guia ou salve como favorito para consulta rápida!*

**Última atualização: 29/12/2025**
