# 🐛 DEBUG - Cor Não Vai para o Pedido

## 🔍 INVESTIGAÇÃO REALIZADA

Após analisar os logs e código, identifiquei o problema:

### Evidências dos Logs

```
🔍 [DEBUG] Produto: anel amarelo
   - usaVariacoes: true
   - variacoes: {11: {azul: 3}, 12: {marrom: 5, rosa: 2}, 13: {rosa: 1}, 14: {amarelo: 10}}
   - tamanho recebido: "12"
   - cor recebida: ""  ← ❌ COR VAZIA!
   ➜ Usando ESTOQUE POR TAMANHO: disponível = 6
✅ Estoque baixado (tamanho): anel amarelo [12] - quantidade restante no tamanho: 5
```

**Conclusão:** A cor está chegando VAZIA no serviço de vendas, apesar do produto TER variações!

---

## 🎯 CAUSA RAIZ

O produto tem variações corretamente:
```json
{
  "11": {"azul": 3},
  "12": {"marrom": 5, "rosa": 2},  ← Tamanho 12 tem 2 cores!
  "13": {"rosa": 1},
  "14": {"amarelo": 10}
}
```

Mas quando o usuário adiciona ao carrinho, a cor está indo vazia.

**Possíveis causas:**

1. **O modal de seleção NÃO está abrindo**
   - O campo `variacoes` pode estar null no widget do card
   - A lógica de detecção está falhando

2. **O usuário consegue adicionar SEM selecionar cor**
   - O modal está bloqueando incorretamente
   - O usuário está fechando o modal antes de selecionar

3. **A cor está sendo perdida no caminho**
   - Entre o modal e o carrinho
   - Entre o carrinho e o pré-pedido

---

## ✅ CORREÇÃO APLICADA

Adicionei logs de debug extensivos no botão "Adicionar ao Carrinho":

**Arquivo:** `lib/screens/public_catalog_screen.dart` (linhas 3062-3088)

```dart
onPressed: () {
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('🛒 [ADD BUTTON] Product: ${widget.name}');
  debugPrint('   estoquePorTamanho: ${widget.estoquePorTamanho}');
  debugPrint('   estoquePorCor: ${widget.estoquePorCor}');
  debugPrint('   variacoes: ${widget.variacoes}');
  debugPrint('   hasTamanhos: $hasTamanhos');
  debugPrint('   hasCores: $hasCores');
  debugPrint('   hasVariacoes: $hasVariacoes');

  if (hasTamanhos || hasCores || hasVariacoes) {
    debugPrint('✅ Opening selection modal');
    _openSelectionModal();
  } else {
    debugPrint('❌ Adding to cart directly (NO VARIATIONS)');
    widget.onAdd({ 'tamanho': '', 'cor': '' });
  }
}
```

---

## 🧪 COMO TESTAR

### Passo 1: Instalar Nova Versão

No computador, execute:
```bash
cd "C:\Users\Pichau\apk_nathy\temp_naty"
flutter run -d <seu-dispositivo>
```

OU compile o APK:
```bash
flutter build apk --debug
```

### Passo 2: Reproduzir o Problema

1. **Abra o catálogo** no app
2. **Selecione "Anel Amarelo"**
3. **Clique em "Adicionar"**
4. **OBSERVE o console**:
   - Deve mostrar os logs: `🛒 [ADD BUTTON] Product: anel amarelo`
   - Deve mostrar: `variacoes: {11: {azul: 3}, 12: {marrom: 5, rosa: 2}, ...}`
   - Deve mostrar: `hasVariacoes: true` ou `false`
   - Deve mostrar: `✅ Opening selection modal` OU `❌ Adding to cart directly`

### Passo 3: Cenários

#### ✅ Cenário Esperado (CORRETO):
```
🛒 [ADD BUTTON] Product: anel amarelo
   variacoes: {11: {azul: 3}, 12: {marrom: 5, rosa: 2}, ...}
   hasVariacoes: true
✅ Opening selection modal
```

Então o modal abre com:
- Opções de tamanho: 11, 12, 13, 14
- Após selecionar tamanho 12: opções de cor: marrom, rosa

#### ❌ Cenário Atual (PROBLEMA):
```
🛒 [ADD BUTTON] Product: anel amarelo
   variacoes: null  ← ❌ VARIAÇÕES NULL!
   hasVariacoes: false
❌ Adding to cart directly (NO VARIATIONS)
```

Produto vai para o carrinho SEM modal, com `tamanho: ''` e `cor: ''`.

---

## 📋 INFORMAÇÕES A COLETAR

Por favor, me envie:

1. **Screenshot do console** quando clicar em "Adicionar"
2. **Confirme se o modal abriu** ou se o produto foi direto para o carrinho
3. **Se o modal abriu:**
   - Screenshot do modal
   - Confirme se as cores aparecem APÓS selecionar o tamanho
   - Confirme se o botão "Adicionar ao Carrinho" fica habilitado SOMENTE após selecionar tamanho E cor

---

## 🔧 POSSÍVEIS SOLUÇÕES

### Se `variacoes` for null:

**Problema:** Os dados não estão sendo passados do Firestore para o widget

**Solução:** Verificar se o produto foi publicado corretamente:
1. Vá em "Produtos" → Edite "Anel Amarelo"
2. Verifique se a grade de variações está preenchida
3. **PUBLIQUE o catálogo** (botão "Publicar Catálogo")
4. Teste novamente no app mobile

### Se o modal NÃO abrir (mesmo com hasVariacoes: true):

**Problema:** Erro ao abrir o BottomSheet

**Solução:** Verificar logs de erro no console

### Se o modal abrir MAS não mostrar cores:

**Problema:** Lógica de `_hasCores` ou `_coresDisponiveis` está falhando

**Solução:** Adicionar mais logs no modal

---

## 🎯 PRÓXIMOS PASSOS BASEADOS NO RESULTADO

### Se variacoes é null:
➡️ Problema na publicação do catálogo ou na leitura do Firestore

### Se variacoes existe MAS modal não abre:
➡️ Problema no código de detecção de variações

### Se modal abre MAS não mostra cores:
➡️ Problema na lógica de cores disponíveis

### Se modal mostra cores MAS permite adicionar sem selecionar:
➡️ Problema na validação `_podeAdicionar`

---

## 📱 COMANDO PARA TESTE RÁPIDO

```bash
# No computador
cd "C:\Users\Pichau\apk_nathy\temp_naty"

# Rodar no celular conectado via USB
flutter run

# Ou compilar APK de debug
flutter build apk --debug
# O APK ficará em: build/app/outputs/flutter-apk/app-debug.apk
```

Depois transfira o APK para o celular e instale.

---

## ✅ STATUS

**Data:** 2026-01-17
**Arquivo Modificado:** `lib/screens/public_catalog_screen.dart`
**Logs Adicionados:** ✅
**Deploy:** ⏳ Aguardando rebuild do app

---

**AGUARDANDO:** Logs do console quando você tentar adicionar o produto ao carrinho! 🔍
