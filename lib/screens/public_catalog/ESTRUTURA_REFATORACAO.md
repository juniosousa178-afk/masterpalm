# Estrutura de Refatoração – Public Catalog

## Objetivo

- **Manutenção**: Widgets menores e services dedicados
- **Performance**: Menos rebuilds, lógica fora do `build()`
- **Compatibilidade**: 100% – layout e comportamento idênticos

---

## Nova Estrutura de Pastas

```
lib/
  screens/
    public_catalog_screen.dart          # Barrel: exporta o catálogo (compatibilidade)
    public_catalog/
      public_catalog_screen.dart        # Orquestrador principal (simplificado)
      catalog_helpers.dart               # Endpoints, cores, checkout config, mapas
      catalog_theme.dart                 # CatalogThemeData – parsing de tema
      catalog_config_service.dart        # Parse fretes, cupons, mídia
      ESTRUTURA_REFATORACAO.md          # Este arquivo
      widgets/
        catalog_banner_carousel.dart     # Carrossel de banners
        catalog_image_placeholder.dart   # Imagem com fallback
        catalog_footer.dart              # Rodapé
        catalog_section_title.dart       # Título de seção
        catalog_gallery_view.dart        # Galeria fullscreen
        catalog_product_details_sheet.dart
        catalog_product_selection_sheet.dart
        catalog_product_card.dart        # Card de produto
        carrinho_sheet_web.dart          # Carrinho/checkout em bottom sheet
      services/
        catalog_config_service.dart     # (futuro) Fretes, cupons, checkout
```

---

## O Que Foi Extraído (Fase 1)

### 1. `catalog_helpers.dart`
- Endpoints HTTP (Mercado Pago, fretes)
- Constantes Firestore (produtos live/draft)
- `readColor`, `readColorFromCfg`
- `deepFindString`, `resolveCheckoutCfgFromData`
- `mpMapDyn`, `mpMapString`
- `isValidHttpUrl`

### 2. `catalog_theme.dart`
- Classe `CatalogThemeData` com todas as cores parseadas
- Método estático `fromConfig(Map)` – evita recalcular em todo rebuild

### 3. `widgets/catalog_banner_carousel.dart`
- `CatalogBannerCarousel` – carrossel com autoplay
- State isolado – mudanças em banners não afetam o restante do catálogo

### 4. `widgets/catalog_image_placeholder.dart`
- `CatalogImagePlaceholder` – imagem com fallback para erro/URL inválida

---

## O Que Foi Extraído (Fase 2)

### 5. `widgets/catalog_section_title.dart`
- `CatalogSectionTitle` – título de seção reutilizável

### 6. `widgets/catalog_gallery_view.dart`
- `CatalogGalleryView` – galeria fullscreen de imagens

### 7. `widgets/catalog_footer.dart`
- `CatalogFooter` – rodapé com redes sociais, links, pagamentos, badges

### 8. `widgets/catalog_product_details_sheet.dart`
- `CatalogProductDetailsSheet` – modal de detalhes do produto

### 9. `widgets/catalog_product_selection_sheet.dart`
- `CatalogProductSelectionSheet` – modal de seleção tamanho/cor

---

## O Que Foi Extraído (Fase 3)

### 10. `widgets/catalog_product_card.dart`
- `CatalogProductCard` – card de produto com galeria, detalhes e seleção

### 11. `widgets/carrinho_sheet_web.dart`
- `CarrinhoSheetWeb` – carrinho/checkout em bottom sheet (~2500 linhas extraídas)
- Cadastro, cupons, roleta, fretes dinâmicos, WhatsApp e Mercado Pago

---

### 12. `catalog_config_service.dart`
- `parseFretes(cfg)` – lista de fretes a partir do config
- `parseCupons(cfg)` – lista de cupons (filtra expirados)
- `parseMedia(cfg, isWide)` – `CatalogMediaConfig` com logoUrl, banners, bannerH

---

## Próximos Passos

1. **Limpeza** – remover imports não usados do arquivo principal

---

## Como Usar a Nova Estrutura

### Imports no arquivo principal

```dart
import 'public_catalog/catalog_helpers.dart';
import 'public_catalog/catalog_theme.dart';
import 'public_catalog/widgets/catalog_banner_carousel.dart';
import 'public_catalog/widgets/catalog_image_placeholder.dart';
```

### Exemplo de uso do tema

```dart
// Dentro do StreamBuilder, após ter cfg:
final themeData = CatalogThemeData.fromConfig(cfg);
// Usar themeData.primaryColor, themeData.bgColor, etc.
```

### Exemplo de uso do banner

```dart
CatalogBannerCarousel(
  banners: banners,
  height: bannerH,
)
```

---

## Redução de Rebuilds

1. **Tema**: `CatalogThemeData.fromConfig()` é chamado uma vez por dados de config; o objeto é imutável.
2. **BannerCarousel**: É um `StatefulWidget` independente – seu `setState` não propaga para o pai.
3. **ProductCard**: Ao ser extraído, cada card terá seu próprio estado (hover, galeria).
4. **CarrinhoSheetWeb**: Ao ser extraído, alterações no carrinho não forçam rebuild do catálogo principal.

---

## Compatibilidade

- **Imports externos**: `import 'screens/public_catalog_screen.dart'` continua funcionando via barrel.
- **Layout**: Nenhuma alteração visual.
- **Comportamento**: Fluxos de checkout, WhatsApp, Mercado Pago, roleta, etc. inalterados.
