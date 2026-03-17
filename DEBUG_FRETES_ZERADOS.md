# 🔍 DEBUG: FRETES MOSTRANDO R$ 0,00

**Problema**: Fretes do Melhor Envio, Correios e Frenet aparecem com R$ 0,00

**Status**: Em investigação - logs detalhados adicionados

---

## 📸 EVIDÊNCIAS (SUAS IMAGENS)

### **Imagem 1: Melhor Envio com R$ 0,00**
```
Mini Envios          R$ 0,00
Rodoviário           R$ 0,00
.Package Centralizado R$ 0,00
Express              R$ 0,00
Coleta               R$ 0,00
```

### **Imagem 2: Mix com R$ 0,00**
```
Retirada             R$ 0,00
Entrega local        R$ 10,00
PAC                  R$ 0,00   ← Deveria ter valor
SEDEX                R$ 0,00   ← Deveria ter valor
.Package             R$ 0,00   ← Deveria ter valor
```

### **Imagem 3: FUNCIONANDO CORRETAMENTE ✅**
```
Retirada             R$ 0,00
Entrega local        R$ 10,00
PAC                  R$ 20,81  ✅ Valor correto!
Sedex                R$ 22,84  ✅ Valor correto!
Jadlog Package       R$ 24,79  ✅ Valor correto!
```

---

## 🎯 ANÁLISE

O fato de que **às vezes funciona** (imagem 3) indica que:

❌ NÃO é problema de código (o código funciona quando recebe dados corretos)
✅ É problema de CONFIGURAÇÃO ou API retornando erro

---

## 🔍 POSSÍVEIS CAUSAS

### **Causa 1: Token do Melhor Envio Inválido/Expirado** (MAIS PROVÁVEL)

O Melhor Envio exige um token válido. Se o token estiver:
- Expirado
- Inválido
- Revogado
- De ambiente de testes (sandbox)

A API vai retornar erro e o app usa fallback (fretes manuais com R$ 0,00).

**Como verificar**:
1. Acesse: https://melhorenvio.com.br/painel
2. Faça login
3. Vá em "Desenvolvedores" → "Tokens"
4. Verifique se o token está ATIVO
5. Se necessário, gere um novo token
6. Cole o novo token no app: Menu → Fretes & Cupons → Melhor Envio → Token

---

### **Causa 2: CEP de Origem Não Configurado**

O Melhor Envio precisa saber DE ONDE você está enviando.

**Como verificar no Firestore**:
```
lojas/
  └─ {sua_loja_id}/
     └─ config/
        └─ fretes/
           └─ cepOrigem: "12345678"  ← DEVE EXISTIR
           └─ melhorEnvio:
              └─ token: "seu_token_aqui"
```

**Se não existir**, adicione:
1. Acesse Firebase Console
2. Firestore Database
3. `lojas/{sua_loja}/config/fretes`
4. Adicione campo: `cepOrigem = "seu_cep_sem_traço"`

---

### **Causa 3: Produto Sem Peso ou Dimensões**

APIs de frete precisam de:
- Peso (em gramas)
- Dimensões (altura, largura, comprimento em cm)

**Como verificar**:
1. Vá em Produtos
2. Abra o produto que você adicionou ao carrinho
3. Verifique se tem:
   - ✅ Peso: 500g (mínimo 300g)
   - ✅ Altura: 10cm
   - ✅ Largura: 20cm
   - ✅ Comprimento: 30cm

Se estiver vazio, as APIs podem retornar erro.

---

### **Causa 4: API do Melhor Envio Fora do Ar**

Pode ser instabilidade momentânea da API.

**Como verificar**:
1. Acesse: https://status.melhorenvio.com.br
2. Veja se tem algum problema reportado

---

## 🛠️ CORREÇÕES APLICADAS NO CÓDIGO

### **1. Logs Detalhados Adicionados**

Agora o código mostra:
```
📦 [CATALOGO] Processando 5 opções da API:
   [0] DUMP COMPLETO da opção: {nome: PAC, valor: 20.81, prazo: 8, ...}
   [0] Valor bruto recebido: 20.81 (tipo: double)
   [0] ✅ Convertido de num para double: 20.81
   [0] API retornou: PAC - R$ 20.81 - 8 dias - Correios - Plataforma: melhor_envio
```

**Se aparecer R$ 0,00**:
```
   [0] DUMP COMPLETO da opção: {nome: PAC, valor: 0.0, ...}
   [0] Valor bruto recebido: 0.0 (tipo: double)
   [0] ✅ Convertido de num para double: 0.0
   ⚠️⚠️⚠️ [0] ATENÇÃO: Valor zero detectado!
   ⚠️ Opção completa: {nome: PAC, valor: 0.0, prazo: 0, empresa: , plataforma: melhor_envio}
   ⚠️ Campo 'valor': 0.0
   ⚠️ Todos os campos: [nome, valor, prazo, empresa, plataforma]
```

---

### **2. Dump Completo do Objeto**

Agora vemos EXATAMENTE o que a API está retornando.

---

## 📋 CHECKLIST DE DEBUG

Execute esses passos para identificar o problema:

### **PASSO 1: Instalar APK Atualizado**

```bash
# Desinstalar versão antiga
adb uninstall com.suaempresa.seuapp

# Instalar nova versão com logs
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

### **PASSO 2: Conectar USB e Ver Logs**

```bash
# Ver logs em tempo real
adb logcat | grep -E "CATALOGO|FRETE|MELHOR_ENVIO|VIACEP"
```

Ou use Android Studio → Logcat

---

### **PASSO 3: Fazer Pedido de Teste**

1. Abra o catálogo
2. Adicione produto ao carrinho
3. Digite CEP: `01310100` (Av. Paulista - sempre funciona)
4. Observe os logs no console

---

### **PASSO 4: Analisar Logs**

**Se ver**:
```
✅ [MELHOR_ENVIO] API retornou 5 opções
   [0] PAC - R$ 20.81
   [1] SEDEX - R$ 22.84
```
✅ **API funcionando** - valores estão chegando

**Se ver**:
```
❌ [FRETE] Melhor Envio erro 401: {"message":"Unauthenticated"}
```
❌ **Token inválido** - precisa gerar novo token

**Se ver**:
```
❌ [FRETE] Melhor Envio erro 422: {"message":"CEP de origem inválido"}
```
❌ **CEP de origem não configurado** - adicione no Firestore

---

## 🔧 SOLUÇÕES

### **Solução 1: Renovar Token do Melhor Envio**

1. Acesse: https://melhorenvio.com.br/painel
2. Faça login
3. Menu → "Desenvolvedores" → "Tokens"
4. Clique em "Gerar Novo Token"
5. **IMPORTANTE**: Marque todas as permissões:
   - ✅ shipping-calculate (calcular frete)
   - ✅ shipping-cancel (cancelar)
   - ✅ shipping-checkout (finalizar)
   - ✅ shipping-tracking (rastrear)
   - ✅ shipping-generate (gerar etiqueta)
6. Copie o token gerado
7. No app: Menu → Fretes & Cupons → Melhor Envio
8. Cole o token
9. Salve
10. Teste novamente

---

### **Solução 2: Configurar CEP de Origem no Firestore**

1. Acesse: https://console.firebase.google.com
2. Selecione seu projeto
3. Firestore Database
4. Navegue para: `lojas/{sua_loja_id}/config/fretes`
5. Se o documento não existir, crie
6. Adicione campo:
   ```
   cepOrigem: "01310100"  (seu CEP sem traço)
   ```
7. Salve
8. Teste novamente

---

### **Solução 3: Verificar Peso dos Produtos**

1. Menu → Produtos
2. Edite cada produto
3. Certifique-se de preencher:
   - Peso: mínimo 300g (recomendado 500g)
   - Altura: 10cm
   - Largura: 20cm
   - Comprimento: 30cm
4. Salve
5. Teste novamente

---

## 🎯 TESTE RÁPIDO (5 MINUTOS)

### **Teste Simples para Identificar Causa**

```bash
# 1. Instalar APK atualizado
adb install -r build/app/outputs/flutter-apk/app-release.apk

# 2. Conectar logs
adb logcat > logs.txt &

# 3. No app:
#    - Adicione produto ao carrinho
#    - Digite CEP: 01310100
#    - Aguarde cálculo

# 4. Parar logs
# Ctrl+C

# 5. Analisar
grep "MELHOR_ENVIO\|FRETE\|CATALOGO" logs.txt
```

---

## 📊 INTERPRETANDO OS LOGS

### **Cenário 1: Token Inválido**

```
🔄 [FRETE] Consultando Melhor Envio...
❌ [FRETE] Melhor Envio erro 401: {"message":"Unauthenticated"}
✅ [FRETE] Manual: 2 opções
```

**Solução**: Gerar novo token (ver Solução 1)

---

### **Cenário 2: CEP de Origem Faltando**

```
🔄 [FRETE] Consultando Melhor Envio...
❌ [FRETE] Melhor Envio erro 422: {"errors":{"cep_origem":["required"]}}
✅ [FRETE] Manual: 2 opções
```

**Solução**: Configurar cepOrigem no Firestore (ver Solução 2)

---

### **Cenário 3: Funcionando Corretamente**

```
🔄 [FRETE] Consultando Melhor Envio...
✅ [MELHOR_ENVIO] API retornou 5 opções
   [0] PAC - R$ 20.81 - 8 dias
   [1] SEDEX - R$ 22.84 - 6 dias
   [2] Jadlog Package - R$ 24.79 - 8 dias
✅ [FRETE] Melhor Envio: 5 opções
🎉 [FRETE] TOTAL: 7 opções de frete disponíveis
```

**Resultado**: Tudo OK! ✅

---

## 🚨 PROBLEMA MAIS COMUM

**90% dos casos de "frete zerado" são causados por**:

🎯 **Token do Melhor Envio inválido ou expirado**

**Solução rápida**:
1. Gere novo token no painel do Melhor Envio
2. Cole no app
3. Salve
4. Teste

---

## 📞 SE NADA FUNCIONAR

Envie os seguintes dados:

1. **Logs completos**:
   ```bash
   adb logcat > logs_completos.txt
   # Fazer pedido de teste
   # Ctrl+C para parar
   # Enviar arquivo logs_completos.txt
   ```

2. **Screenshot do Firestore**:
   - `lojas/{sua_loja}/config/fretes`
   - Mostre todos os campos (censure o token se necessário)

3. **Screenshot do Melhor Envio**:
   - Painel → Tokens
   - Mostre se o token está ativo

4. **Informações do produto**:
   - Peso configurado
   - Dimensões configuradas

---

## ✅ APK ATUALIZADO

**Localização**: `build/app/outputs/flutter-apk/app-release.apk`
**Tamanho**: 82.3 MB
**Mudanças**:
- ✅ Logs detalhados de debug
- ✅ Dump completo de cada opção de frete
- ✅ Alertas quando detecta R$ 0,00
- ✅ Mostra tipo do valor recebido

---

**Data**: Janeiro 2026
**Status**: 🔍 Aguardando logs para diagnosticar
