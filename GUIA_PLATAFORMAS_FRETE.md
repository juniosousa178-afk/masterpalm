# 📦 GUIA COMPLETO DE PLATAFORMAS DE FRETE

## 🎯 COMO FUNCIONA NO SEU APP

Quando um cliente compra no seu catálogo online, ele precisa escolher como receber o produto. O app oferece opções de frete automaticamente e, dependendo da plataforma que você configurou, funciona de maneiras diferentes.

---

## 📋 PLATAFORMAS DISPONÍVEIS

⚡ **NOVIDADE**: Você pode cadastrar **TODAS as plataformas** ao mesmo tempo! O app vai mostrar TODAS as opções de frete para o cliente escolher a melhor.

**Exemplo**: Se você cadastrar Melhor Envio + Frenet + Correios, o cliente verá:
```
[ ] Melhor Envio - PAC: R$ 20,00
[ ] Melhor Envio - SEDEX: R$ 30,00
[ ] Frenet - Jadlog: R$ 28,00
[ ] Frenet - Total Express: R$ 32,00
[ ] Correios - PAC: R$ 25,00
[ ] Correios - SEDEX: R$ 35,00
```

Quanto mais plataformas cadastradas, mais opções o cliente tem!

---

### 🟢 1. MELHOR ENVIO (Recomendado - Automático)

#### **O que é?**
Melhor Envio é uma plataforma que conecta você com várias transportadoras (Correios, Jadlog, etc.) em um único lugar. É como um shopping de fretes.

#### **Como funciona no app?**

**PASSO 1**: Cliente escolhe frete
```
Cliente vê opções:
[ ] PAC - R$ 25,00 em 8 dias
[x] SEDEX - R$ 35,00 em 3 dias  ← Cliente escolhe
[ ] Jadlog - R$ 28,00 em 5 dias
```

**PASSO 2**: Cliente finaliza pedido
```
O app AUTOMATICAMENTE:
✅ Envia todos os dados do cliente para o Melhor Envio
✅ Adiciona o pedido no seu carrinho do Melhor Envio
✅ Preenche endereço, CEP, nome, tudo!
```

**PASSO 3**: Você finaliza (manual)
```
1. Entre no site do Melhor Envio
2. Vá em "Carrinho" (o pedido JÁ ESTÁ LÁ!)
3. Clique em "Finalizar Compra"
4. Pague o frete
5. Imprima a etiqueta
6. Cole na embalagem e despache
```

#### **Vantagens**
- ✅ **AUTOMÁTICO**: Cliente compra, pedido vai direto pro carrinho
- ✅ **RÁPIDO**: Você só entra e finaliza (não digita nada!)
- ✅ **SEM ERROS**: Dados vêm do pedido, não tem como errar
- ✅ **VÁRIAS TRANSPORTADORAS**: Correios, Jadlog, Azul Cargo, etc.
- ✅ **ECONOMIA**: Até 80% de desconto nos fretes

#### **Como conectar ao app?**

**1. Criar conta no Melhor Envio**
- Acesse: https://melhorenvio.com.br
- Clique em "Criar Conta"
- Preencha seus dados
- Confirme seu email

**2. Pegar o Token da API**
- Faça login no Melhor Envio
- Vá em: **Perfil** (foto no canto superior direito)
- Clique em **Configurações**
- Procure por **"Tokens de Acesso"** ou **"API"**
- Clique em **"Gerar Novo Token"**
- **COPIE** o token que aparece (é uma sequência longa de letras/números)
- ⚠️ **IMPORTANTE**: Guarde bem esse token, ele só aparece uma vez!

**3. Configurar no App**
```
No App Master Palm:
1. Abra o app
2. Menu (☰) → Fretes & Cupons
3. Provider: Selecione "Melhor Envio"
4. CEP Origem: Digite seu CEP (ex: 01310-100)
5. Token Melhor Envio: COLE o token que você copiou
6. Clique em SALVAR
```

**4. Pronto!**
Agora todos os pedidos irão automaticamente para o carrinho do Melhor Envio!

#### **Quanto custa?**
- ❌ **Não tem mensalidade**
- ✅ Você só paga quando usa (quando envia um produto)
- 💰 Preços variam por transportadora (geralmente R$ 15-50)

---

### 🟡 2. FRENET (Apenas Cotação de Preços)

#### **O que é?**
Frenet é um **cotador de preços** de frete. Ele NÃO envia produtos, NÃO tem carrinho, e NÃO gera etiquetas. **Ele APENAS consulta os preços** de várias transportadoras e mostra para o cliente escolher.

⚠️ **IMPORTANTE**: Frenet só serve para **mostrar preços**! Depois que o cliente escolhe, você precisa fazer tudo manualmente na transportadora.

#### **Como funciona no app?**

**PASSO 1**: Cliente escolhe frete
```
Cliente vê opções:
[ ] Correios - R$ 25,00
[x] Jadlog - R$ 28,00  ← Cliente escolhe
[ ] Total Express - R$ 30,00
```

**PASSO 2**: Cliente finaliza pedido
```
O app salva que o cliente escolheu "Jadlog R$ 28,00"
⚠️ MAS NÃO ENVIA AUTOMATICAMENTE PARA NENHUM LUGAR
```

**PASSO 3**: Você precisa fazer TUDO manualmente
```
1. Ver no app qual transportadora o cliente escolheu
2. Entrar no site DA TRANSPORTADORA (ex: jadlog.com.br)
3. CRIAR CONTA na transportadora (se não tiver)
4. DIGITAR MANUALMENTE todos os dados:
   - Nome do cliente
   - CPF
   - Endereço completo
   - CEP
   - Telefone
   - Peso do produto
   - Dimensões
5. Pagar o frete
6. Gerar etiqueta
7. Imprimir e despachar
```

#### **Por que não é automático?**
Frenet é **APENAS um cotador de preços**.

**Analogia**: É como pesquisar passagens de avião no Google Flights:
- ✅ Google mostra: "GOL R$ 350 | LATAM R$ 380 | Azul R$ 400"
- ❌ Mas você precisa ir no site da companhia para COMPRAR

**Frenet faz o mesmo**:
- ✅ Mostra: "Correios R$ 25 | Jadlog R$ 28 | Total Express R$ 30"
- ❌ Você precisa ir no site da transportadora para DESPACHAR

#### **Vantagens**
- ✅ Mostra preços de várias transportadoras
- ✅ Ajuda o cliente a escolher o mais barato

#### **Desvantagens**
- ❌ **NÃO É AUTOMÁTICO**: Você digita tudo manualmente
- ❌ Precisa criar conta em cada transportadora
- ❌ Mais demorado (pode levar 10-15 minutos por pedido)
- ❌ Mais chance de erro (digitação errada)

#### **Como conectar ao app?**

**1. Criar conta no Frenet**
- Acesse: https://painel.frenet.com.br
- Clique em "Cadastre-se"
- Preencha seus dados
- Confirme seu email

**2. Pegar Token da API**
- Faça login no Frenet
- Vá em: **Configurações** → **API**
- Copie o **Token de Acesso**

**3. Configurar no App**
```
No App Master Palm:
1. Menu (☰) → Fretes & Cupons
2. Provider: Selecione "Frenet"
3. CEP Origem: Digite seu CEP
4. Token Frenet: COLE o token
5. SALVAR
```

**4. Depois de cada venda**
Você vai precisar:
- Ver qual transportadora o cliente escolheu
- Ir no site da transportadora
- Criar o envio manualmente

#### **Quanto custa?**
- ✅ Frenet é GRÁTIS
- 💰 Você paga direto para cada transportadora quando usar

---

### 🔴 3. CORREIOS (Manual)

#### **O que é?**
Os Correios tradicionais, empresa de envio postal do governo.

#### **Como funciona no app?**

**PASSO 1**: Cliente escolhe frete
```
Cliente vê opções:
[ ] PAC - R$ 20,00 em 10 dias
[x] SEDEX - R$ 32,00 em 3 dias  ← Cliente escolhe
```

**PASSO 2**: Cliente finaliza pedido
```
O app salva a opção escolhida
⚠️ NÃO ENVIA AUTOMATICAMENTE
```

**PASSO 3**: Você faz TUDO manualmente
```
1. Ver no app os dados do pedido
2. Ir no site dos Correios ou agência física
3. Criar envio manualmente
4. Pagar o frete
5. Gerar etiqueta
```

#### **Por que não é automático?**
Os Correios não oferecem integração automática para pessoas físicas ou pequenos lojistas. Só empresas grandes com contrato especial conseguem.

#### **Vantagens**
- ✅ Conhecido e confiável
- ✅ Entrega em todo Brasil

#### **Desvantagens**
- ❌ **TOTALMENTE MANUAL**: Você faz tudo sozinho
- ❌ Pode ser mais caro que outras opções
- ❌ Precisa ir até agência ou usar site (ambos manuais)

#### **Como conectar ao app?**

**1. Criar conta (opcional)**
- Acesse: https://www.correios.com.br
- Para ter desconto, precisa fazer contrato empresarial

**2. Configurar no App**
```
No App Master Palm:
1. Menu (☰) → Fretes & Cupons
2. Provider: Selecione "Correios"
3. CEP Origem: Digite seu CEP
4. SALVAR
```

**3. Depois de cada venda**
- Entre no site dos Correios
- Crie o envio manualmente com os dados do pedido
- Ou vá até uma agência

#### **Quanto custa?**
- 💰 Varia por peso/distância
- 📦 PAC: ~R$ 15-30 (10-20 dias)
- 🚀 SEDEX: ~R$ 25-50 (2-5 dias)

---

### ⚙️ 4. FRETE MANUAL (Mais Simples)

#### **O que é?**
Você define valores fixos de frete (não depende de CEP nem de plataforma externa).

#### **Como funciona no app?**

**PASSO 1**: Você configura opções fixas
```
Exemplo:
- Frete Grátis: R$ 0,00
- Frete Normal: R$ 15,00
- Frete Expresso: R$ 25,00
```

**PASSO 2**: Cliente escolhe
```
[ ] Grátis - R$ 0,00
[x] Normal - R$ 15,00  ← Cliente paga R$ 15
[ ] Expresso - R$ 25,00
```

**PASSO 3**: Você envia como quiser
```
1. Pode usar Correios
2. Pode usar transportadora própria
3. Pode entregar pessoalmente
4. TOTAL LIBERDADE
```

#### **Vantagens**
- ✅ **SUPER SIMPLES**: Sem APIs, tokens, integrações
- ✅ Você controla totalmente os valores
- ✅ Bom para vendas locais
- ✅ Bom se você tem acordo próprio com transportadora

#### **Desvantagens**
- ❌ Cliente não sabe prazo real
- ❌ Preço fixo (não muda por distância)
- ❌ Pode cobrar muito caro ou barato demais

#### **Como configurar?**

```
No App Master Palm:
1. Menu (☰) → Fretes & Cupons
2. Provider: Selecione "Manual"
3. Adicione opções:
   Nome: "Frete Grátis"
   Valor: 0

   Nome: "Frete Normal"
   Valor: 15.00

   Nome: "Frete Expresso"
   Valor: 25.00
4. SALVAR
```

#### **Quando usar?**
- ✅ Vendas em sua cidade
- ✅ Entregas pessoais
- ✅ Produtos leves (frete baixo)
- ✅ Você já tem parceria com transportadora

---

## 🏆 QUAL ESCOLHER?

### **Para Lojas Profissionais e Vendas Nacionais**
👉 **MELHOR ENVIO** (automático, rápido, econômico)

### **Para Comparar Preços Apenas**
👉 **FRENET** (mas prepare-se para trabalho manual)

### **Para Vendas Locais/Simples**
👉 **FRETE MANUAL** (fácil de configurar)

### **Para Quem Já Usa Correios**
👉 **CORREIOS** (mas é tudo manual)

---

## 📊 COMPARAÇÃO RÁPIDA

| Característica | Melhor Envio | Frenet | Correios | Manual |
|---|---|---|---|---|
| **Automático?** | ✅ SIM | ❌ Não | ❌ Não | ⚠️ Parcial |
| **Pedido no carrinho?** | ✅ SIM | ❌ Não | ❌ Não | ❌ Não |
| **Precisa digitar dados?** | ❌ Não | ✅ Sim | ✅ Sim | ✅ Sim |
| **Economiza tempo?** | ✅ Muito | ❌ Não | ❌ Não | ⚠️ Médio |
| **Múltiplas transportadoras?** | ✅ Sim | ✅ Sim | ❌ Não | ❌ Não |
| **Complexidade** | Fácil | Média | Média | Muito Fácil |
| **Melhor para** | Loja completa | Comparar preços | Tradição | Vendas locais |

---

## ❓ PERGUNTAS FREQUENTES

### **1. Posso usar mais de uma plataforma ao mesmo tempo?**
✅ **SIM!** Agora você pode cadastrar TODAS as plataformas e o app mostrará TODAS as opções para o cliente!

**Exemplo**: Se você cadastrar:
- Melhor Envio (token configurado)
- Frenet (token configurado)
- Correios (usuário/senha configurado)
- Frete Manual (valores fixos)

O cliente verá:
```
Opções de Frete:
[ ] Melhor Envio - PAC: R$ 20,00 (8 dias)
[ ] Melhor Envio - SEDEX: R$ 30,00 (3 dias)
[ ] Frenet - Jadlog: R$ 28,00 (5 dias)
[ ] Frenet - Total Express: R$ 32,00 (7 dias)
[ ] Correios - PAC: R$ 25,00 (10 dias)
[ ] Correios - SEDEX: R$ 35,00 (3 dias)
[ ] Frete Grátis: R$ 0,00 (manual)
```

✨ **O cliente escolhe o melhor custo-benefício!**

### **2. Qual é a mais barata?**
Depende! Frenet e Melhor Envio mostram preços de várias transportadoras, então você pode comparar. Geralmente Melhor Envio oferece os melhores descontos.

### **3. Preciso pagar para usar as plataformas?**
- **Melhor Envio**: Não tem mensalidade, paga só quando usa
- **Frenet**: Grátis para usar
- **Correios**: Paga por envio
- **Manual**: Grátis total

### **4. O que acontece se eu não configurar nada?**
O app vai usar "Frete Manual" com valor R$ 0,00. Você vai precisar combinar o frete com o cliente depois.

### **5. Como sei se está funcionando?**
Teste fazendo um pedido de teste no catálogo. Se configurou Melhor Envio, entre no site deles e veja se o pedido apareceu no carrinho.

### **6. Posso adicionar/remover plataformas depois?**
✅ Sim! Você pode configurar quantas quiser a qualquer momento em: Menu → Fretes & Cupons

**Como funciona**:
- Cadastre o token de cada plataforma que quiser usar
- Deixe em branco as que não quer usar
- As opções aparecem automaticamente para o cliente

---

## 🎯 RECOMENDAÇÃO FINAL

**Se você quer profissionalizar sua loja e economizar tempo:**
👉 Use **MELHOR ENVIO**

**Benefícios:**
- ⏱️ Economiza ~10 minutos por pedido
- 🎯 Sem erros de digitação
- 💰 Descontos de até 80% nos fretes
- 🚀 Cliente recebe mais rápido (você despacha mais rápido)
- 😊 Experiência profissional

**Setup:**
15 minutos para criar conta e configurar = economia de horas depois!

---

## 📞 PRECISA DE AJUDA?

Se tiver dúvidas:
1. Leia este guia novamente com calma
2. Teste com um pedido pequeno primeiro
3. Entre em contato com o suporte da plataforma escolhida

**Links úteis:**
- Melhor Envio: https://melhorenvio.com.br/suporte
- Frenet: https://frenet.com.br/contato
- Correios: https://www.correios.com.br/falecomoscorreios

---

**Última atualização**: Janeiro 2026
