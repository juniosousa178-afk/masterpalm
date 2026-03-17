# Classificação dos usos de 'padrao'
**Data:** 06/03/2025
**Status:** Corrigido

---

## A) Fallback perigoso de loja (corrigido)

| Arquivo | Linha | Uso | Ação |
|---------|-------|-----|------|
| loja_config_screen.dart | 397 | `_slug ?? _lojaId ?? 'padrao'` | Redundante: id já validado antes; usar `_lojaId!` |
| historico_movimentacao_estoque_screen.dart | 42 | `_lojaId = id ?? 'padrao'` | LojaIdService.getWithTimeout + erro |
| carrinhos_abandonados_screen.dart | 42 | `_lojaId = id ?? 'padrao'` | LojaIdService.getWithTimeout + erro |
| estoque_screen.dart | 3096 | `lojaId: lojaId ?? 'padrao'` | Não navegar quando null |
| vendas_service.dart | 258 | `lojaEfetiva = lojaId ?? 'padrao'` | Exigir lojaId; lançar se null |
| hive_multi_store.dart | 9 | `_lojaId = 'padrao'` | Usar nullable; lançar se não inicializado |
| produto_form_screen.dart | 249 | `id ?? 'padrao'` | Tratar null; não abrir box |

---

## B) Uso legítimo de negócio (não alterar)

| Arquivo | Linha | Uso | Observação |
|---------|-------|-----|------------|
| fretes_cupons_screen.dart | 78 | `{'id': 'padrao', 'nome': 'Padrão', ...}` | Embalagem padrão |
| carrinho_sheet_web.dart | 1061, 1102, 1122, 3062, 3072, 3221, 3230, 3373, 3383 | tipoEmbalagem, tipo frete 'padrao' | Legítimo |
| produto_form_screen.dart | 65, 295, 301 | tipoEmbalagem, embalagens | Legítimo |
| produto.dart | 98, 178 | tipoEmbalagem = 'padrao' | Legítimo |
| product_card.dart, catalog_product_card.dart, catalog_combo_variation_sheet | vários | tipoEmbalagem | Legítimo |
| public_catalog_screen.dart, firestore_catalog_impl.dart | 339, 207 | tipoEmbalagem ?? 'padrao' | Legítimo |
| estoque_screen.dart | 2130 | tipoEmbalagem | Legítimo |
| ean13_generator.dart | 23, 24 | prefixo '789' padrão | Legítimo |
| permissao_service.dart | 256-260 | variável local padrao | Legítimo |

---

## C) Legado/model compatível (revisado)

| Arquivo | Linha | Uso | Ação |
|---------|-------|-----|------|
| cliente.dart | 58 | `lojaId = 'padrao'` default | Manter para Hive legado; vazioAsync usar normalizeFromBox |
| cliente.dart | 89 | `sessao.get(...) ?? 'padrao'` | Usar normalizeFromBox; lançar se null |
| fornecedor.dart | 44 | `lojaId = 'padrao'` default | Manter para Hive legado |
| repair_historico_clientes_service.dart | 128 | `lojaId == 'padrao'` em _lojaMatch | Alterar: cLoja vazio → true (legado) |
| reconciliacao_vendas_clientes_service.dart | 105 | idem | idem |

---

## Scripts manuais (menor prioridade)

| Arquivo | Uso | Observação |
|---------|-----|------------|
| importar_vendas_firestore.dart | `lojaId = args[0] ?? 'padrao'` | Script CLI; exigir arg ou documentar |
| repair_historico_clientes.dart | idem | idem |
