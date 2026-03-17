# Entrega: Correção de Fallback 'padrao' como Loja

**Data:** 06/03/2025

---

## 1. Classificação dos usos de 'padrao'

Ver `docs/CLASSIFICACAO_PADRAO.md` para a tabela completa.

**Resumo:**
- **A) Fallback perigoso:** Corrigido em todos os arquivos listados.
- **B) Uso legítimo:** Mantido (tipoEmbalagem, frete tipo padrão, etc.).
- **C) Legado:** Revisado; `_lojaMatch` passa a tratar cLoja vazio como `true`; `cliente.vazioAsync` usa `normalizeFromBox` e lança `StateError` quando não resolve loja.

---

## 2. Arquivos alterados

| Arquivo | Alteração |
|---------|-----------|
| `lib/screens/loja_config_screen.dart` | `_slug ?? _lojaId ?? 'padrao'` → `_lojaId!` |
| `lib/screens/historico_movimentacao_estoque_screen.dart` | `LojaIdService.getWithTimeout` + tela de erro com retry |
| `lib/screens/carrinhos_abandonados_screen.dart` | `LojaIdService.getWithTimeout` + tela de erro com retry |
| `lib/screens/estoque_screen.dart` | Não navega quando lojaId null; SnackBar de erro |
| `lib/services/vendas_service.dart` | `ArgumentError` quando lojaId null/vazio |
| `lib/services/hive_multi_store.dart` | `_lojaId` nullable; lança em getters se não inicializado |
| `lib/screens/produto_form_screen.dart` | `LojaIdService.getWithTimeout`; SnackBar + pop quando null |
| `lib/screens/order_review_screen.dart` | Resolve lojaId antes de registrar venda; passa lojaId |
| `lib/models/cliente.dart` | `vazioAsync` usa `normalizeFromBox`; lança `StateError` se não resolver |
| `lib/services/repair_historico_clientes_service.dart` | `_lojaMatch`: cLoja vazio → `true` |
| `lib/services/reconciliacao_vendas_clientes_service.dart` | `_lojaMatch`: cLoja vazio → `true` |

---

## 3. Compatibilidade preservada

- **Cliente/Fornecedor legados:** O default `lojaId = 'padrao'` no construtor Hive foi mantido (desserialização legada).
- **Cliente.vazioAsync:** Continua aceitando `lojaId` e `vendasBoxName`; passa a usar `normalizeFromBox(sessao)` em vez de fallback 'padrao'. Lança apenas quando não consegue resolver loja (sessão sem store_id e sem lojaId informado).
- **_lojaMatch:** Documentos legados sem `lojaId` passam a ser considerados pertencentes ao contexto atual (box já é por loja). Garante que clientes antigos continuem sendo processados.
- **VendasService:** Chamares que passam `lojaId` continuam funcionando; os que não passavam (ex.: order_review_screen) passam a resolver antes de chamar.

---

## 4. Checklist de testes manuais

- [ ] **Loja Config:** Abrir tela após login; deve carregar normalmente.
- [ ] **Histórico Movimentação:** Abrir pelo menu do estoque; se loja não resolver, exibir tela de erro com "Tentar novamente".
- [ ] **Carrinhos Abandonados:** Mesmo fluxo do histórico.
- [ ] **Estoque > Histórico:** Se loja não resolver, SnackBar de erro e não navegar.
- [ ] **Produto Form:** Abrir novo produto; se loja não resolver, SnackBar e voltar.
- [ ] **Nova Venda:** Registrar venda no app (nova_venda_modal) com loja ativa; deve registrar normalmente.
- [ ] **Order Review (Link do Pedido):** Finalizar pedido com loja válida; deve registrar venda e pedido.
- [ ] **Pedido Público:** Finalizar pedido; deve registrar venda com lojaId da tela.
- [ ] **HiveMultiStore:** Login deve inicializar; getters usados após login devem funcionar.
- [ ] **Repair Histórico / Reconciliação:** Rodar com loja válida; clientes legados sem lojaId devem ser incluídos.

---

## 5. Pronto para ETAPAS 4–6

Sim. Os usos perigosos de `'padrao'` como fallback de loja foram removidos sem alterar usos legítimos nem quebrar legado. O sistema não assume mais loja fictícia quando a resolução falha.
