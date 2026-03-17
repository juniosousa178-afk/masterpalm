# 🔒 Solução: Isolamento Total por Loja

## ✅ Correções Implementadas

### 1. **Logs de Debug Adicionados**

Adicionei logs em 3 locais chave:

#### `lib/screens/public_catalog_screen.dart:599`
```dart
debugPrint('📱 [CATALOG] Renderizando catálogo para loja: $_resolvedLojaId (preview: ${widget.preview})');
```

#### `lib/widgets/campanha_banner_widget.dart:46`
```dart
debugPrint('🎯 [CAMPANHAS] Carregando campanhas para loja: ${widget.lojaId}');
debugPrint('🎯 [CAMPANHAS] Encontradas ${snapshot.docs.length} campanhas ativas');
```

#### `lib/widgets/roleta_web_widget.dart:62`
```dart
debugPrint('🎰 [ROLETA] Carregando config para loja: ${widget.lojaId}');
debugPrint('✅ [ROLETA] Config carregada: valorMinimo=..., premios=...');
```

---

## 🔍 Como Diagnosticar o Problema

### Passo 1: Rebuild e Executar com Logs

```bash
cd "C:\Users\Pichau\apk_nathy\temp_naty"

# Limpar tudo
flutter clean
flutter pub get

# Executar com verbose para ver os logs
flutter run --verbose

# OU para web com logs visíveis no console:
flutter run -d chrome
```

### Passo 2: Verificar os Logs no Console

Quando você acessar o catálogo web, deve ver logs assim:

```
📱 [CATALOG] Renderizando catálogo para loja: LOJA_ABC (preview: false)
🎯 [CAMPANHAS] Carregando campanhas para loja: LOJA_ABC
🎯 [CAMPANHAS] Encontradas 2 campanhas ativas
🎰 [ROLETA] Carregando config para loja: LOJA_ABC
✅ [ROLETA] Config carregada: valorMinimo=150.0, premios=6
```

**Se NÃO aparecer esses logs:**
- O widget não está sendo renderizado
- Há algum erro antes

**Se aparecer com lojaId errado ou vazio:**
- O problema está na resolução do lojaId
- Verifique o `StoreResolverService`

**Se aparecer "0 campanhas ativas":**
- Não há campanhas no Firestore
- Ou as campanhas não atendem os critérios (ativa=true, dataFim>=hoje)

---

## 🔥 Verificação do Firestore

### Campanhas

Abra o Firebase Console e verifique:

**Caminho:** `lojas/{SEU_LOJA_ID}/campanhas_sorteio`

**Exemplo de documento correto:**
```javascript
{
  nome: "Promoção de Natal",
  descricao: "Concorra a prêmios incríveis!",
  ativa: true,  // ✅ OBRIGATÓRIO
  dataInicio: Timestamp(2025-12-01),
  dataFim: Timestamp(2025-12-31),  // ✅ Precisa ser FUTURO
  dataSorteio: Timestamp(2026-01-05),
  premioDescricao: "Vale-compras de R$ 500",
  valorMinimo: 100.0,
  valorX: 50.0,
  status: "aberta"
}
```

### Config da Roleta

**Caminho:** `lojas/{SEU_LOJA_ID}/campanhas_sorteio_config/roleta`

**Exemplo:**
```javascript
{
  ativo: true,
  valorMinimo: 150.0,
  premios: [
    {
      label: "10% OFF",
      tipo: "percentual",
      valor: 10.0,
      ativo: true
    },
    {
      label: "Frete Grátis",
      tipo: "frete_gratis",
      valor: 0.0,
      ativo: true
    }
    // ... mais prêmios
  ]
}
```

---

## 🎯 Garantindo Isolamento por Loja

### Todos os Widgets/Serviços Agora Usam lojaId:

#### ✅ CampanhaBannerWidget
```dart
_db.collection('lojas')
   .doc(widget.lojaId)  // ← Isolado por loja
   .collection('campanhas_sorteio')
   .where('ativa', isEqualTo: true)
```

#### ✅ RoletaWebWidget
```dart
CampanhasSorteioService.carregarConfigRoleta(
  lojaId: widget.lojaId,  // ← Isolado por loja
)
```

#### ✅ Relatório Financeiro
```dart
vendasBox.values.where((v) => v.lojaId == lojaId)  // ← Isolado por loja
```

#### ✅ Catálogo (Produtos)
```dart
FirebaseFirestore.instance
  .collection('lojas')
  .doc(lojaId)  // ← Isolado por loja
  .collection(widget.preview ? 'draft_produtos' : 'produtos')
```

---

## 🚀 Comandos para Executar AGORA

```bash
# 1. Limpar cache
flutter clean

# 2. Atualizar dependências
flutter pub get

# 3. Executar o app
flutter run -d chrome

# 4. Observar os logs no terminal
# Procure por mensagens começando com:
# 📱 [CATALOG]
# 🎯 [CAMPANHAS]
# 🎰 [ROLETA]
```

---

## 🐛 Problemas Comuns

### Problema 1: "0 campanhas ativas" mesmo tendo campanhas

**Causa:** As campanhas não atendem os critérios do filtro.

**Solução:**
1. Abra o Firestore
2. Verifique cada campanha:
   - `ativa` deve ser `true` (boolean, não string)
   - `dataFim` deve ser >= data de hoje
   - O tipo de `dataFim` deve ser `Timestamp`, não `String`

**Correção manual no Firestore:**
```javascript
// Se dataFim estiver como string, corrija para Timestamp:
dataFim: new Date('2025-12-31')  // No console do Firebase
```

---

### Problema 2: Roleta não aparece no checkout

**Causas possíveis:**
1. Valor do carrinho < valorMinimo
2. Dados do cliente não preenchidos
3. Não há campanha ativa
4. Config da roleta não existe

**Verificação:**
1. Veja no log: `🎰 [ROLETA] Config carregada`
2. Confirme o `valorMinimo` e compare com o total do carrinho
3. Preencha TODOS os campos do checkout (nome, email, telefone, endereço completo)

---

### Problema 3: lojaId vazio ou undefined

**Causa:** O `StoreResolverService` não está retornando o lojaId.

**Verificação:**
```dart
// Adicione temporariamente no início do build():
debugPrint('🔍 widget.lojaId = ${widget.lojaId}');
debugPrint('🔍 _resolvedLojaId = $_resolvedLojaId');
```

**Solução:**
1. Certifique-se de estar logado no app
2. Verifique se a loja está selecionada
3. No Hive, confirme que `store_id` está salvo:
   ```dart
   final box = Hive.box('sessao');
   print(box.get('store_id'));
   ```

---

## 📋 Checklist Final

- [ ] Executei `flutter clean`
- [ ] Executei `flutter pub get`
- [ ] Executei `flutter run`
- [ ] Vi os logs no console com `[CATALOG]`, `[CAMPANHAS]`, `[ROLETA]`
- [ ] Verifiquei que o lojaId está correto nos logs
- [ ] Confirmei que existem campanhas ativas no Firestore
- [ ] Confirmei que `ativa=true` e `dataFim` é futuro
- [ ] Publiquei o catálogo via app (Estoque → Publicar TUDO)
- [ ] Testei adicionando produtos ao carrinho (valor >= valorMinimo)
- [ ] Preenchi TODOS os dados do checkout

---

## 📞 Se Ainda Não Funcionar

**Me envie os seguintes dados:**

1. **Logs do console:**
   - Copie todas as mensagens com `[CATALOG]`, `[CAMPANHAS]`, `[ROLETA]`

2. **Screenshot do Firestore:**
   - `lojas/{lojaId}/campanhas_sorteio`
   - Mostre os campos de pelo menos uma campanha

3. **Informações:**
   - Qual é o `lojaId` sendo usado?
   - O valor do carrinho é maior que o `valorMinimo`?
   - Todos os dados do checkout estão preenchidos?

---

## 🎉 Resultado Esperado

Quando tudo estiver funcionando, você verá:

1. **Banner de Campanhas:** Logo após os banners de produtos no topo
2. **Roleta:** No checkout, após preencher todos os dados, se o valor >= valorMinimo
3. **Relatório Financeiro:** Vendas separadas por tipo de pagamento

**Tudo 100% isolado por loja!** Cada loja só vê suas próprias campanhas, roleta, produtos e vendas.

---

**Data:** 2025-12-23
**Status:** ✅ Logs adicionados - Pronto para diagnóstico
