# Módulo Catálogo – Abordagem Intermediária

Objetivo: manter **um único APK** hoje, com o catálogo **isolado por interfaces**. Assim você pode evoluir o catálogo sem quebrar o resto do app e, no futuro, extrair para um APK separado trocando só as implementações.

---

## 1. Ideia em uma frase

O catálogo **não chama Firestore (ou qualquer backend) direto**. Ele depende de **contratos** (interfaces). Quem abre o catálogo (MasterPalm hoje, ou um app separado amanhã) **injeta** a implementação (Firestore hoje, API amanhã).

---

## 2. Estrutura de pastas proposta

```
lib/
  catalog/                          # Módulo catálogo (fronteira clara)
    README_MODULO_CATALOGO.md       # Este arquivo
    catalog_module.dart              # Barrel: exporta tela + interfaces

    # Contratos (o catálogo só enxerga isso)
    data/
      catalog_product_source.dart   # abstract: obter produtos
      catalog_config_source.dart    # abstract: obter config (tema, fretes, cupons)
      catalog_order_sink.dart       # abstract: enviar pedido / registrar venda

    # Implementação atual (Firestore / MasterPalm)
    data/
      firestore_catalog_impl.dart    # Implementa os 3 contratos com Firestore

    # UI (pode mover os arquivos de public_catalog para cá aos poucos)
    screens/
      public_catalog_screen.dart     # Recebe as fontes por parâmetro ou Provider
    widgets/
      ...                           # catalog_product_card, carrinho_sheet, etc.
```

O que hoje está em `lib/screens/public_catalog/` pode **ficar onde está** e o módulo catálogo **apenas importar** de lá, ou você pode **mover** aos poucos para `lib/catalog/`. O importante é: a **tela do catálogo** e os widgets **só usam** as interfaces, não `FirebaseFirestore.instance` nem serviços concretos do MasterPalm.

---

## 3. Contratos (interfaces)

### 3.1 CatalogProductSource – “de onde vêm os produtos?”

```dart
abstract class CatalogProductSource {
  Stream<List<ProdutoCatalogo>> watchProducts(String lojaId, {bool onlyLive = true});
  Future<List<ProdutoCatalogo>> getProducts(String lojaId, {bool onlyLive = true});
}
```

- **Hoje:** `FirestoreCatalogProductSource` lê a coleção de produtos no Firestore (live/draft).
- **Amanhã (APK separado):** `ApiCatalogProductSource` chama `GET /api/catalog/products`.

### 3.2 CatalogConfigSource – “de onde vêm tema, fretes, cupons, banners?”

```dart
abstract class CatalogConfigSource {
  Stream<Map<String, dynamic>> watchConfig(String lojaId);
  Future<Map<String, dynamic>> getConfig(String lojaId);
}
```

- **Hoje:** lê o documento de config da loja no Firestore.
- **Amanhã:** `GET /api/catalog/config`.

### 3.3 CatalogOrderSink – “para onde vai o pedido?”

```dart
abstract class CatalogOrderSink {
  Future<void> submitOrder(String lojaId, Map<String, dynamic> orderPayload);
}
```

- **Hoje:** grava pedido no Firestore e dispara lógica de notificação/comissão do MasterPalm.
- **Amanhã:** `POST /api/orders` no backend MasterPalm.

---

## 4. Como o restante do app usa o catálogo

- **MasterPalm (app único hoje):** ao navegar para o catálogo (rota `/loja/:id` ou botão “Ver catálogo”), o app cria as implementações Firestore e **injeta** na tela (ou num `Provider`/`InheritedWidget` só do catálogo).

Exemplo conceitual:

```dart
// No app principal (main / app_routes)
final productSource = FirestoreCatalogProductSource();
final configSource = FirestoreCatalogConfigSource();
final orderSink = FirestoreCatalogOrderSink();

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => PublicCatalogScreen(
      lojaId: lojaId,
      productSource: productSource,
      configSource: configSource,
      orderSink: orderSink,
    ),
  ),
);
```

- **Futuro APK só catálogo:** o `main` desse APK usa `ApiCatalogProductSource`, `ApiCatalogConfigSource`, `ApiCatalogOrderSink` (chamando a API do MasterPalm) e abre a **mesma** `PublicCatalogScreen` com essas implementações.

---

## 5. Benefícios

| Hoje (1 APK) | Amanhã (se quiser 2 APKs) |
|--------------|---------------------------|
| Código do catálogo organizado e com fronteira clara | Mesmo código de UI; só troca as implementações |
| Fácil testar o catálogo com dados mock (implementações fake) | App catálogo leve: só UI + chamadas HTTP |
| Menos acoplamento: gestão/estoque não dependem de detalhes do catálogo | Um APK “só catálogo” e um “MasterPalm gestão” compartilhando a mesma API |

---

## 6. Passos práticos (sem quebrar nada)

1. ~~**Criar as 3 interfaces** em `lib/catalog/data/`.~~ ✅ Feito.
2. ~~**Implementar** Firestore em `lib/catalog/data/firestore_catalog_impl.dart`.~~ ✅ Feito (versão básica; o mapeamento completo de produtos pode ser copiado de `_processDocsToProducts` do `PublicCatalogScreen` se quiser).
3. **Alterar** `PublicCatalogScreen` para aceitar opcionalmente `CatalogProductSource`, `CatalogConfigSource`, `CatalogOrderSink`. Se forem fornecidos, usar esses; senão, manter o comportamento atual (Firestore/cache direto). Assim você não quebra nada e pode migrar aos poucos.
4. **Na abertura do catálogo** (ex.: `app_routes.dart`), passar as implementações:  
   `PublicCatalogScreen(lojaId: id, productSource: FirestoreCatalogProductSource(), ...)`.
5. Opcional: mover telas/widgets de `lib/screens/public_catalog/` para `lib/catalog/` e exportar via `catalog_module.dart`.

Assim você tem o **intermediário**: um módulo de catálogo bem definido, ainda dentro do mesmo APK, preparado para um dia virar app separado se fizer sentido.

---

## 7. Como usar hoje (import)

```dart
import 'package:master_palm/catalog/catalog_module.dart';

// Quando for abrir o catálogo com fontes injetadas (após passo 3 e 4):
final productSource = FirestoreCatalogProductSource();
final configSource = FirestoreCatalogConfigSource();
final orderSink = FirestoreCatalogOrderSink();
// PublicCatalogScreen(lojaId: id, productSource: productSource, ...);
```
