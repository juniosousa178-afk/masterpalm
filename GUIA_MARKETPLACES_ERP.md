# 🛍️ GUIA COMPLETO: INTEGRAÇÃO COM MARKETPLACES / ERP

## 🎯 O QUE É ESTA FUNCIONALIDADE?

A integração com Marketplaces permite que você **sincronize automaticamente** seus produtos com grandes plataformas de venda online como TikTok Shop, Mercado Livre, Shopee e outras.

### **O que você pode fazer:**
- ✅ **Sincronizar produtos** automaticamente
- ✅ **Atualizar estoque** em todos os marketplaces
- ✅ **Atualizar preços** em tempo real
- ✅ **Receber pedidos** diretamente no app
- ✅ **Gerenciar tudo** em um único lugar

---

## 📋 MARKETPLACES DISPONÍVEIS

### 🟢 **INTEGRADOS E FUNCIONANDO**

#### 1. **🎵 TikTok Shop**
- ✅ Sincronização automática de produtos
- ✅ Atualização de estoque
- ✅ Atualização de preços
- ✅ Importação de pedidos
- 🔥 **Melhor para**: Produtos virais, público jovem

#### 2. **🟡 Mercado Livre**
- ✅ Sincronização automática de produtos
- ✅ Atualização de estoque
- ✅ Atualização de preços
- ✅ Importação de pedidos
- 🔥 **Melhor para**: Alcance nacional, varejo em geral

#### 3. **🛍️ Shopee**
- ✅ Sincronização automática de produtos
- ✅ Atualização de estoque
- ✅ Atualização de preços
- ⚠️ **Em desenvolvimento**: Importação de pedidos
- 🔥 **Melhor para**: Produtos populares, frete grátis

### 🟠 **EM BREVE**

- 📦 **Amazon** - Maior marketplace do mundo
- 🔵 **Magazine Luiza** - Varejo brasileiro
- 🔴 **Americanas** - Grande alcance nacional
- 🟠 **Casas Bahia** - Eletrônicos e eletrodomésticos

---

## 🚀 COMO USAR

### **PASSO 1: Acessar a Tela de Marketplaces**

1. Abra o app Master Palm
2. Vá em **Menu (☰)**
3. Clique em **"Marketplaces / ERP"**

### **PASSO 2: Configurar Cada Marketplace**

Escolha o marketplace que deseja integrar e siga os passos abaixo:

---

## 🎵 TIKTOK SHOP - CONFIGURAÇÃO COMPLETA

### **O que você precisa:**
1. Conta de vendedor no TikTok Shop
2. App criado no TikTok Developer
3. Credenciais de API

### **Como obter as credenciais:**

#### **1. Criar conta no TikTok Shop Seller**
```
1. Acesse: https://seller.tiktokglobalshop.com
2. Clique em "Sign Up" (Cadastrar)
3. Escolha "Individual" ou "Business"
4. Preencha seus dados
5. Verifique seu email
6. Configure sua loja
```

#### **2. Acessar TikTok Developer**
```
1. Acesse: https://partner.tiktokshop.com
2. Faça login com sua conta de vendedor
3. Vá em "My Apps" → "Create App"
4. Preencha:
   - App Name: "Master Palm Integration"
   - Description: "Integração com sistema de vendas"
   - Permissions: Marque todas relacionadas a produtos e pedidos
5. Clique em "Submit"
```

#### **3. Obter Credenciais**
```
Após criar o app, você verá:

📝 App Key: abc123def456...
🔒 App Secret: xyz789uvw012...
🔑 Access Token: (clicar em "Generate Token")
🏪 Shop ID: (copiar da sua loja)
```

### **4. Configurar no App Master Palm**

```
No App:
1. Menu → Marketplaces / ERP
2. Expandir "TikTok Shop"
3. Colar as credenciais:

   App Key: _______________
   App Secret: _____________
   Access Token: ___________
   Shop ID: ________________

4. Clicar em "SALVAR CONFIGURAÇÕES"
```

### **5. Sincronizar Produtos**

```
1. Após salvar, clique em "Sincronizar Produtos"
2. Aguarde o processo (pode levar alguns minutos)
3. Você verá um resumo:
   - Total: 50 produtos
   - Sincronizados: 48
   - Erros: 2
```

### **⚠️ IMPORTANTE - TikTok Shop**:
- Produtos precisam ter **imagem principal**
- Produtos precisam ter **descrição**
- Estoque mínimo: **1 unidade**
- Preço mínimo: **R$ 1,00**

---

## 🟡 MERCADO LIVRE - CONFIGURAÇÃO COMPLETA

### **O que você precisa:**
1. Conta de vendedor no Mercado Livre
2. App criado no Mercado Livre Developers
3. Access Token e Refresh Token

### **Como obter as credenciais:**

#### **1. Criar conta de vendedor**
```
1. Acesse: https://www.mercadolivre.com.br
2. Clique em "Vender" (canto superior)
3. Siga o cadastro de vendedor
4. Verifique sua identidade
```

#### **2. Acessar Mercado Livre Developers**
```
1. Acesse: https://developers.mercadolivre.com.br
2. Faça login
3. Vá em "Meus Aplicativos" → "Criar Aplicativo"
4. Preencha:
   - Nome: "Master Palm"
   - Descrição: "Integração com sistema de vendas"
   - Redirect URI: https://mastepalm.com.br/callback
   - Permissions: Selecione:
     ✅ read (ler dados)
     ✅ write (criar/editar produtos)
     ✅ offline_access (manter conexão)
5. Clique em "Criar"
```

#### **3. Obter Access Token**
```
1. No seu app criado, copie o "Client ID" e "Client Secret"
2. Acesse (substitua CLIENT_ID):

   https://auth.mercadolivre.com.br/authorization?
   response_type=code&
   client_id=SEU_CLIENT_ID&
   redirect_uri=https://mastepalm.com.br/callback

3. Autorize o acesso
4. Você será redirecionado para uma URL com um "code"
5. Use esse code para obter o token (via API ou ferramenta)
```

**OU use a ferramenta simplificada**:
```
1. Acesse: https://api.mercadolibre.com/oauth/authorize
2. Autorize
3. Copie o Access Token gerado
```

#### **4. Configurar no App**

```
No App Master Palm:
1. Menu → Marketplaces / ERP
2. Expandir "Mercado Livre"
3. Colar:

   Access Token: ___________________
   Refresh Token: __________________

4. Salvar
```

#### **5. Sincronizar Produtos**

```
1. Clique em "Sincronizar Produtos"
2. Aguarde conclusão
3. Produtos aparecerão no Mercado Livre em até 5 minutos
```

### **⚠️ IMPORTANTE - Mercado Livre**:
- Você precisa escolher a **categoria correta** para cada produto
- Produtos podem ser **rejeitados** se não seguirem as políticas do ML
- Access Token **expira** a cada 6 horas (use Refresh Token)
- Comissão do ML: **11-16%** do valor de venda

---

## 🛍️ SHOPEE - CONFIGURAÇÃO COMPLETA

### **O que você precisa:**
1. Conta de vendedor na Shopee
2. Partner ID e Partner Key
3. Access Token

### **Como obter as credenciais:**

#### **1. Criar conta de vendedor**
```
1. Baixe o app Shopee
2. Vá em "Eu" → "Vender na Shopee"
3. Complete o cadastro
4. Verifique documentos
```

#### **2. Acessar Shopee Open Platform**
```
1. Acesse: https://open.shopee.com
2. Faça login com sua conta de vendedor
3. Vá em "Console" → "Criar Aplicativo"
4. Preencha:
   - Nome: "Master Palm"
   - Tipo: "Integração"
   - Permissions: Marque:
     ✅ Product
     ✅ Orders
     ✅ Logistics
5. Aguarde aprovação (1-2 dias)
```

#### **3. Obter Credenciais**
```
Após aprovação:

📝 Partner ID: 123456
🔒 Partner Key: abcdef123456...
🏪 Shop ID: (ID da sua loja)
```

#### **4. Gerar Access Token**
```
1. No console, vá em "Authorization"
2. Clique em "Generate Token"
3. Copie o Access Token gerado
```

#### **5. Configurar no App**

```
No App Master Palm:
1. Menu → Marketplaces / ERP
2. Expandir "Shopee"
3. Colar:

   Partner ID: ______________
   Partner Key: _____________
   Shop ID: _________________
   Access Token: ____________

4. Salvar
```

### **⚠️ IMPORTANTE - Shopee**:
- Produtos precisam estar em **categorias pré-aprovadas**
- Fotos devem ter **fundo branco**
- Frete é **calculado pela Shopee**
- Comissão: **5-15%** dependendo da categoria

---

## 🔄 SINCRONIZAÇÃO AUTOMÁTICA

### **Como Funciona:**

```
Quando você atualiza um produto no app:
    ↓
App detecta mudança
    ↓
Sincroniza AUTOMATICAMENTE com todos os marketplaces
    ↓
Produto atualizado em:
  - TikTok Shop
  - Mercado Livre
  - Shopee
```

### **O que é sincronizado:**

- ✅ **Nome** do produto
- ✅ **Preço**
- ✅ **Estoque**
- ✅ **Descrição**
- ✅ **Fotos**
- ✅ **Peso/Dimensões**

### **Quando é sincronizado:**

- 🔄 Quando você **salva** um produto editado
- 🔄 Quando você **cria** um novo produto
- 🔄 Quando você **clica em "Sincronizar"**
- 🔄 **Opcionalmente**: A cada 1 hora (automático)

---

## 📦 GERENCIAMENTO DE PEDIDOS

### **Pedidos chegam automaticamente:**

```
Cliente compra no TikTok Shop
    ↓
Pedido aparece no App Master Palm
    ↓
Você processa e envia
    ↓
App atualiza status no TikTok Shop
    ↓
Cliente recebe notificação
```

### **Status de Pedidos:**

| App Master Palm | TikTok Shop | Mercado Livre | Shopee |
|---|---|---|---|
| Pendente | TO_CONFIRM | pending | UNPAID |
| Pago | AWAITING_SHIPMENT | paid | TO_SHIP |
| Enviado | IN_TRANSIT | shipped | SHIPPING |
| Entregue | DELIVERED | delivered | COMPLETED |
| Cancelado | CANCELLED | cancelled | CANCELLED |

---

## 💰 CUSTOS E COMISSÕES

### **Comissões por Marketplace:**

| Marketplace | Comissão | Taxa Fixa | Frete |
|---|---|---|---|
| **TikTok Shop** | 2-8% | R$ 0,00 | Por conta do vendedor |
| **Mercado Livre** | 11-16% | Varia | Mercado Envios (opcional) |
| **Shopee** | 5-15% | R$ 0,00 | Shopee Garantia (incluído) |
| **Amazon** | 8-15% | R$ 0,00 | Amazon Logistics (opcional) |

### **Exemplo Real:**

```
Produto: Colar de prata
Preço: R$ 100,00

TikTok Shop:
- Comissão: R$ 5,00 (5%)
- Você recebe: R$ 95,00

Mercado Livre:
- Comissão: R$ 13,00 (13%)
- Você recebe: R$ 87,00

Shopee:
- Comissão: R$ 10,00 (10%)
- Você recebe: R$ 90,00
```

---

## ❓ PERGUNTAS FREQUENTES

### **1. Preciso criar conta em cada marketplace?**
✅ Sim, você precisa ter uma conta ativa de vendedor em cada plataforma que deseja usar.

### **2. Posso vender em todos ao mesmo tempo?**
✅ SIM! Você configura todos e seus produtos aparecem em todas as plataformas simultaneamente.

### **3. O estoque é controlado automaticamente?**
✅ Sim! Quando vende em um marketplace, o estoque diminui em todos automaticamente.

**Exemplo**:
```
Estoque inicial: 10 unidades
↓
Venda no TikTok: 3 unidades
↓
Novo estoque em TODOS:
- App: 7 unidades
- TikTok: 7 unidades
- Mercado Livre: 7 unidades
- Shopee: 7 unidades
```

### **4. E se o produto for rejeitado em um marketplace?**
⚠️ Alguns marketplaces têm regras específicas. Se um produto for rejeitado:
- Você recebe notificação
- Produto continua nos outros marketplaces
- Você pode ajustar e reenviar

### **5. Quanto tempo leva para sincronizar?**
- ⚡ **TikTok Shop**: 1-5 minutos
- ⚡ **Mercado Livre**: 2-10 minutos
- ⚡ **Shopee**: 5-15 minutos

### **6. Posso desativar um marketplace depois?**
✅ Sim! Basta **apagar as credenciais** e salvar. Produtos continuarão ativos naquele marketplace, mas não serão mais sincronizados.

### **7. Preciso pagar para usar a integração?**
❌ A integração do app Master Palm é **GRATUITA**! Você só paga as comissões diretamente para cada marketplace quando vender.

### **8. Os pedidos aparecem automaticamente no app?**
✅ Sim! Quando um cliente compra em qualquer marketplace, o pedido aparece automaticamente na aba "Pedidos" do app.

---

## 🎯 MELHORES PRÁTICAS

### **1. Fotos de Qualidade**
- ✅ Use fotos com **fundo branco**
- ✅ Mínimo **3 fotos** por produto
- ✅ Mostre o produto de **vários ângulos**
- ✅ Tamanho mínimo: **800x800px**

### **2. Descrições Completas**
- ✅ Descreva **características** detalhadas
- ✅ Inclua **dimensões** e **peso**
- ✅ Mencione **material** e **cuidados**
- ✅ Use **palavras-chave** relevantes

### **3. Preços Competitivos**
- ✅ Pesquise **concorrentes** em cada marketplace
- ✅ Considere as **comissões** ao definir preço
- ✅ Ofereça **promoções** ocasionais
- ✅ Use **frete grátis** quando possível

### **4. Estoque Sempre Atualizado**
- ✅ Sincronize **diariamente**
- ✅ Evite vender com **estoque zerado**
- ✅ Configure **alertas** de estoque baixo

### **5. Atendimento Rápido**
- ✅ Responda **dúvidas** em até 24h
- ✅ Envie pedidos em até **48h**
- ✅ Atualize **código de rastreamento** sempre

---

## 🔧 SOLUÇÃO DE PROBLEMAS

### **Erro: "Access Token Inválido"**
```
Causa: Token expirou ou está errado

Solução:
1. Volte na plataforma (TikTok/ML/Shopee)
2. Gere um NOVO token
3. Cole no app
4. Salve novamente
```

### **Erro: "Produto Rejeitado"**
```
Causa: Produto não atende regras do marketplace

Solução:
1. Leia a mensagem de erro
2. Ajuste o produto (categoria, descrição, foto)
3. Sincronize novamente
```

### **Erro: "Sincronização Falhou"**
```
Causa: Problema de conexão ou API fora do ar

Solução:
1. Verifique sua internet
2. Tente novamente em 5 minutos
3. Se persistir, contate suporte
```

---

## 📊 RELATÓRIOS E ANÁLISES

### **O que você pode acompanhar:**

- 📈 **Vendas por Marketplace**
- 📉 **Taxa de conversão**
- 💰 **Receita total**
- 📦 **Produtos mais vendidos**
- ⭐ **Avaliações dos clientes**

---

## 🎉 PRONTO PARA COMEÇAR!

### **Checklist Rápido:**

- [ ] Criar conta de vendedor nos marketplaces desejados
- [ ] Obter credenciais de API
- [ ] Configurar no app Master Palm
- [ ] Sincronizar produtos
- [ ] Testar com 1-2 produtos primeiro
- [ ] Expandir para catálogo completo
- [ ] Monitorar vendas e ajustar preços

---

## 📞 PRECISA DE AJUDA?

- 📧 Email: suporte@mastepalm.com.br
- 💬 WhatsApp: (11) 99999-9999
- 📖 Documentação completa: https://docs.mastepalm.com.br

---

**Última atualização**: Janeiro 2026
**Versão**: 1.0 - Integração com TikTok Shop, Mercado Livre e Shopee
