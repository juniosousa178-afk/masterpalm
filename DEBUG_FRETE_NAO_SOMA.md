# 🔍 DEBUG: FRETE NÃO ESTÁ SOMANDO NO TOTAL

**Problema**: Mesmo selecionando um frete com valor (ex: PAC R$ 20,81), o total continua sem somar o frete

**Status**: Logs detalhados adicionados para identificar o problema

---

## 📋 SINTOMAS

1. ✅ Fretes aparecem na lista (PAC R$ 20,81, SEDEX R$ 22,84, etc)
2. ✅ Usuário seleciona um frete
3. ❌ Total da venda NÃO soma o valor do frete
4. ❌ Total continua sendo apenas o valor dos produtos

**Exemplo**:
```
Produtos: R$ 100,00
Frete selecionado: PAC R$ 20,81
Total esperado: R$ 120,81
Total mostrado: R$ 100,00 ❌
```

---

## 🔍 LOGS ADICIONADOS

### **1. Log ao Selecionar Frete** (linhas 4033-4042)

Quando o usuário clica em um frete, agora mostra:

```
🖱️ [SELEÇÃO] Usuário clicou no frete: PAC (índice 2)
🖱️ [SELEÇÃO] Valor do frete: R$ 20.81
🖱️ [SELEÇÃO] Frete completo: {nome: PAC, valor: 20.81, prazo: 8 dias úteis, ...}
✅ [SELEÇÃO] _freteIndex atualizado para: 2
```

**O que verificar**:
- ✅ Valor está correto na seleção? (R$ 20.81)
- ✅ `_freteIndex` está sendo atualizado?

---

### **2. Log ao Calcular Total** (linhas 3793-3809)

Toda vez que o total é calculado, agora mostra:

```
💰 [TOTAL] Frete selecionado (índice 2): PAC
💰 [TOTAL] Frete completo: {nome: PAC, valor: 20.81, prazo: 8 dias úteis, ...}
💰 [TOTAL] Campo valor bruto: 20.81 (tipo: double)
💰 [TOTAL] Valor frete original: R$ 20.81
💰 [TOTAL] Valor frete final: R$ 20.81 (frete grátis: false)
💰 [TOTAL] Subtotal: R$ 100.00
💰 [TOTAL] Total calculado: R$ 100.00 + R$ 20.81 - R$ 0.00 = R$ 120.81
```

**O que verificar**:
- ✅ Frete selecionado é o correto?
- ✅ Valor bruto está correto?
- ✅ Valor frete final é R$ 0.00 ou tem valor?
- ✅ Total calculado está correto?

---

## 🎯 POSSÍVEIS CAUSAS

### **Causa 1: Frete Grátis Ativo**

Se o cupom aplicado tem "frete grátis", o valor será zerado:

```
💰 [TOTAL] Valor frete final: R$ 0.00 (frete grátis: true)
```

**Solução**: Remover cupom ou usar cupom sem frete grátis

---

### **Causa 2: _freteIndex Incorreto**

Se o índice estiver errado, pode estar pegando o frete errado:

```
💰 [TOTAL] Frete selecionado (índice 0): Retirada  ← Errado!
💰 [TOTAL] Valor frete original: R$ 0.00
```

**Solução**: Verificar se a seleção está atualizando `_freteIndex`

---

### **Causa 3: setState Não Sendo Chamado**

Se `setState` não for chamado após selecionar, a UI não atualiza:

```
🖱️ [SELEÇÃO] Usuário clicou no frete: PAC (índice 2)
✅ [SELEÇÃO] _freteIndex atualizado para: 2
[Sem logs de TOTAL depois] ← setState não chamado!
```

**Solução**: Verificar se `setState(() {})` está sendo executado

---

### **Causa 4: Valor Sendo Zerado no Build**

Se o valor está correto no momento da seleção, mas zerado no build:

```
🖱️ [SELEÇÃO] Valor do frete: R$ 20.81  ✅
...
💰 [TOTAL] Campo valor bruto: 0.0 (tipo: double)  ❌
```

**Problema**: O objeto `frete` está sendo modificado em algum lugar

---

## 🛠️ COMO DEBUGAR

### **PASSO 1: Instalar APK Atualizado**

```bash
# Desinstalar versão antiga
adb uninstall com.suaempresa.seuapp

# Instalar com logs
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

### **PASSO 2: Conectar Logs**

```bash
# Ver logs em tempo real
adb logcat | grep -E "SELEÇÃO|TOTAL|FRETE|CATALOGO"
```

Ou use Android Studio → Logcat

---

### **PASSO 3: Fazer Pedido de Teste**

1. Adicione produto ao carrinho
2. Digite CEP válido (ex: 01310100)
3. **AGUARDE** os fretes calcularem
4. Observe os logs de cálculo de frete
5. **SELECIONE** um frete (ex: PAC R$ 20,81)
6. Observe os logs de seleção
7. Observe os logs de cálculo de total

---

### **PASSO 4: Analisar Sequência de Logs**

**Sequência esperada (funcionando)**:

```
📦 [CATALOGO] Processando 5 opções da API
   [0] DUMP COMPLETO: {nome: Retirada, valor: 0.0, ...}
   [1] DUMP COMPLETO: {nome: Entrega local, valor: 10.0, ...}
   [2] DUMP COMPLETO: {nome: PAC, valor: 20.81, ...}  ✅
   [3] DUMP COMPLETO: {nome: SEDEX, valor: 22.84, ...}

📍 [CATALOGO] Selecionando primeira opção de API: PAC (índice 2)
📍 [CATALOGO] _freteIndex: 2

💰 [TOTAL] Frete selecionado (índice 2): PAC
💰 [TOTAL] Valor frete original: R$ 20.81
💰 [TOTAL] Valor frete final: R$ 20.81
💰 [TOTAL] Subtotal: R$ 100.00
💰 [TOTAL] Total calculado: R$ 120.81  ✅
```

**Sequência com problema (frete zerado)**:

```
📦 [CATALOGO] Processando 5 opções da API
   [2] DUMP COMPLETO: {nome: PAC, valor: 0.0, ...}  ❌ Já vem zero!

💰 [TOTAL] Valor frete original: R$ 0.00  ❌
💰 [TOTAL] Total calculado: R$ 100.00  ❌
```

---

## ✅ CÓDIGO CORRIGIDO

O código que calcula o total está correto:

```dart
// Linha 3791-3809
final frete = _fretesLocal[_freteIndex];

final double valorFreteOriginal =
    (frete['valor'] as num?)?.toDouble() ?? 0.0;
final double valorFreteFinal = _freteGratis ? 0.0 : valorFreteOriginal;

final double descontoProdutos = _descontoCupomProdutos;
final double total = (_subtotal + valorFreteFinal) - descontoProdutos;
```

A lógica está correta:
1. ✅ Pega o frete pelo índice: `_fretesLocal[_freteIndex]`
2. ✅ Extrai o valor: `frete['valor']`
3. ✅ Converte para double: `?.toDouble() ?? 0.0`
4. ✅ Soma ao subtotal: `_subtotal + valorFreteFinal`

---

## 🎯 DIAGNÓSTICO BASEADO NOS LOGS

### **Cenário 1: Fretes vêm zerados da API**

```
📦 [CATALOGO] Processando 5 opções da API:
   [0] DUMP COMPLETO da opção: {nome: PAC, valor: 0.0, ...}
   [0] Valor bruto recebido: 0.0 (tipo: double)
   ⚠️⚠️⚠️ [0] ATENÇÃO: Valor zero detectado!
```

**Problema**: API retornou zero (token inválido, CEP origem faltando, etc)

**Solução**: Ver `DEBUG_FRETES_ZERADOS.md` → Verificar token do Melhor Envio

---

### **Cenário 2: Frete correto, mas não soma**

```
📦 [CATALOGO] Processando 5 opções da API:
   [2] Valor bruto recebido: 20.81 (tipo: double)  ✅

🖱️ [SELEÇÃO] Usuário clicou no frete: PAC (índice 2)
🖱️ [SELEÇÃO] Valor do frete: R$ 20.81  ✅
✅ [SELEÇÃO] _freteIndex atualizado para: 2

💰 [TOTAL] Frete selecionado (índice 2): PAC
💰 [TOTAL] Campo valor bruto: 0.0 (tipo: double)  ❌ Como ficou zero?
```

**Problema**: Objeto sendo modificado ou sobrescrito depois

**Solução**: Verificar se `_recalcularFreteSelecionado()` está zerando os valores

---

### **Cenário 3: Cupom com frete grátis**

```
💰 [TOTAL] Valor frete original: R$ 20.81  ✅
💰 [TOTAL] Valor frete final: R$ 0.00 (frete grátis: true)  ❌
```

**Problema**: Cupom aplicado tem frete grátis

**Solução**: Remover cupom ou verificar se o cupom deveria ter frete grátis

---

## 📊 TESTE RÁPIDO

```bash
# 1. Instalar APK
adb install -r build/app/outputs/flutter-apk/app-release.apk

# 2. Conectar logs
adb logcat | grep -E "SELEÇÃO|TOTAL" > logs_total.txt &

# 3. No app:
#    - Adicione produto (R$ 100,00)
#    - Digite CEP: 01310100
#    - Aguarde calcular
#    - Selecione PAC
#    - Observe o total

# 4. Parar logs
# Ctrl+C

# 5. Ver logs
cat logs_total.txt
```

---

## 🔧 VERIFICAÇÕES ADICIONAIS

### **1. Verificar Objeto _fretesLocal**

No console, quando calcular frete:

```
📊 [CATALOGO] _fretesLocal após atualização: 5 itens
   [0] Retirada - R$ 0.0 (manual)
   [1] Entrega local - R$ 10.0 (manual)
   [2] PAC - R$ 20.81 (melhor_envio)  ← Tem valor aqui?
   [3] SEDEX - R$ 22.84 (melhor_envio)
```

Se aparecer R$ 0.0 aqui, o problema é no `FreteService`.

---

### **2. Verificar Seleção**

Quando clicar no frete:

```
🖱️ [SELEÇÃO] Usuário clicou no frete: PAC (índice 2)
🖱️ [SELEÇÃO] Valor do frete: R$ 20.81  ← Tem valor aqui?
```

Se aparecer R$ 0.0 aqui, o objeto já está zerado na lista.

---

### **3. Verificar Total**

No momento de calcular:

```
💰 [TOTAL] Frete selecionado (índice 2): PAC
💰 [TOTAL] Campo valor bruto: 20.81 (tipo: double)  ← Tem valor aqui?
💰 [TOTAL] Valor frete final: R$ 20.81
💰 [TOTAL] Total calculado: R$ 100.00 + R$ 20.81 = R$ 120.81
```

Se o total calculado está correto mas a UI mostra errado, o problema é no setState.

---

## 📄 ARQUIVOS RELACIONADOS

- **`DEBUG_FRETES_ZERADOS.md`** - Problema de fretes chegando com R$ 0,00 da API
- **`CORRECAO_FRETES_ZERADOS.md`** - Correção de valores zerados e duplicação

---

## ✅ APK ATUALIZADO

**Localização**: `build/app/outputs/flutter-apk/app-release.apk`
**Tamanho**: 82.3 MB

**Mudanças**:
- ✅ Log quando usuário seleciona frete
- ✅ Log do valor do frete na seleção
- ✅ Log detalhado do cálculo de total
- ✅ Mostra valor bruto, final e total calculado
- ✅ Indica se frete grátis está ativo

---

## 🎯 PRÓXIMOS PASSOS

1. **Instale o APK atualizado**
2. **Conecte os logs** via `adb logcat`
3. **Faça um pedido de teste** e selecione um frete
4. **Envie os logs** da sequência completa:
   - Logs de cálculo (`📦 [CATALOGO]`)
   - Logs de seleção (`🖱️ [SELEÇÃO]`)
   - Logs de total (`💰 [TOTAL]`)

Com esses logs, vou poder identificar EXATAMENTE onde o valor está sendo perdido.

---

**Data**: Janeiro 2026
**Status**: 🔍 Aguardando logs para diagnosticar
