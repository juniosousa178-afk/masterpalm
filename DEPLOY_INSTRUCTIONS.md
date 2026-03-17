# 📦 Instruções de Deploy - Catálogo Online LIVE

## ✅ O que foi implementado:

Todas as modificações para suportar **variações de estoque (tamanho + cor)** foram implementadas e estão prontas para deploy:

### 1. **Modelo de Produto** (`produto.dart`)
- ✅ Método `recalcularQuantidadeTotal()` para sincronizar estoque total com variações
- ✅ Recálculo automático ao debitar/devolver estoque

### 2. **Sincronização Firestore** (`produtos_firestore_service.dart`)
- ✅ Sincronização de `variacoes` e `cores` (Hive ↔ Firestore)
- ✅ Atualização completa ao salvar produtos

### 3. **Catálogo Sync** (`catalogo_sync_service.dart`)
- ✅ Deploy de `variacoes` e `cores` para catálogo LIVE (linha 200)
- ✅ Método `pushAllToLive()` atualizado

### 4. **Vendas** (`catalogo_venda_service.dart` e `vendas_service.dart`)
- ✅ Baixa de estoque por variação específica
- ✅ Recálculo automático do total
- ✅ Tamanho e cor na mensagem WhatsApp
- ✅ Tamanho e cor no histórico de clientes

---

## 🚀 Como fazer o Deploy para o Catálogo LIVE:

### Opção 1: Pela Interface do App (RECOMENDADO)

1. **Abra o aplicativo**
   ```bash
   flutter run -d windows
   ```

2. **Navegue até:**
   - Menu lateral → **Configurações da Loja** (ou **Loja Config**)

3. **Clique em:**
   - Botão **"Publicar Catálogo"** ou **"Deploy para LIVE"**

4. **Aguarde:**
   - O processo sincronizará todos os produtos com suas variações
   - Aparecerá mensagem de sucesso quando concluir

---

### Opção 2: Via Código (Para Desenvolvedores)

Execute este código em qualquer tela administrativa:

```dart
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/store_resolver_service.dart';

Future<void> deployToLive() async {
  try {
    // Obter loja ativa
    final lojaId = await StoreResolverService.resolve();

    print('🚀 Iniciando deploy para LIVE...');

    // Fazer deploy
    await CatalogoSyncService.pushAllToLive(
      lojaIdOverride: lojaId,
    );

    print('✅ Deploy concluído!');
  } catch (e) {
    print('❌ Erro: $e');
  }
}
```

---

### Opção 3: Forçar Deploy de um Produto Específico

Se quiser fazer deploy de apenas um produto:

```dart
import 'package:master_palm/services/catalogo_sync_service.dart';

Future<void> deployProduto(Produto produto) async {
  await CatalogoSyncService.upsertFromProduto(
    produto,
    target: SyncTarget.live,
  );
}
```

---

## 📋 Verificação Pós-Deploy:

Após o deploy, verifique:

1. **No Firebase Console:**
   - `lojas/{lojaId}/produtos` → Cada produto deve ter:
     - `variacoes`: `{tamanho: {cor: quantidade}}`
     - `cores`: `['vermelho', 'azul', ...]`
     - `quantidade`: Total calculado automaticamente

2. **No Catálogo Web:**
   - Acesse o site do catálogo
   - Produtos devem exibir opções de tamanho e cor
   - Estoque deve refletir as variações

3. **Teste uma Venda:**
   - Faça uma venda pelo catálogo
   - Verifique se o estoque baixou da variação correta
   - Verifique se a mensagem WhatsApp inclui tamanho e cor

---

## 🔧 Produtos Existentes com Variações:

Se você já tem produtos com variações mas o estoque total está desatualizado:

1. Entre na edição de cada produto
2. Salve novamente (mesmo sem alterar nada)
3. O sistema recalculará o total automaticamente
4. Faça deploy para LIVE

**OU** execute este script para recalcular todos:

```dart
final box = Hive.box<Produto>('produtos_$lojaId');

for (final produto in box.values) {
  if (produto.usaVariacoes) {
    produto.recalcularQuantidadeTotal();
    await produto.save();

    // Deploy individual para LIVE
    await CatalogoSyncService.upsertFromProduto(
      produto,
      target: SyncTarget.live,
    );
  }
}
```

---

## ⚙️ Estrutura de Variações:

### Firestore:
```json
{
  "nome": "Camiseta Básica",
  "quantidade": 15,  // Total calculado automaticamente
  "tamanhos": ["P", "M", "G"],
  "cores": ["Vermelho", "Azul", "Verde"],
  "variacoes": {
    "P": {
      "Vermelho": 3,
      "Azul": 2
    },
    "M": {
      "Vermelho": 4,
      "Verde": 3
    },
    "G": {
      "Azul": 3
    }
  }
}
```

### Como funciona:
- **Adicionar variação**: Sistema soma ao total (3+2+4+3+3 = 15)
- **Vender produto**: Baixa da variação específica E recalcula total
- **Sincronização**: Automática Hive ↔ Firestore ↔ Catálogo LIVE

---

## 🎯 Próximos Passos:

1. ✅ Fazer deploy para LIVE usando uma das opções acima
2. ✅ Testar vendas no catálogo web
3. ✅ Verificar se mensagens WhatsApp incluem tamanho/cor
4. ✅ Validar histórico de clientes

---

**Desenvolvido por:** Claude Sonnet 4.5
**Data:** 2026-01-17
