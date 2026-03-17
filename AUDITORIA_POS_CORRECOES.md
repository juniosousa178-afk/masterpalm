# AUDITORIA PÓS-CORREÇÕES — MasterPalm

**Data:** 06/03/2025  
**Versão:** 1.0.28+38  
**Contexto:** Auditoria após correções de Storage, OrderReviewScreen, FirestoreCatalogProductSource e demais endurecimentos.

---

## 1. RESUMO EXECUTIVO PÓS-CORREÇÕES

O MasterPalm está em estado sólido após as correções. A maior parte dos riscos críticos e altos foi mitigada. O que restou são riscos médios/baixos e alguns pontos de atenção para produção e escalabilidade.

**Estado geral:** ✅ Pronto para produção com monitoramento dos riscos residuais.

**O que foi corrigido recentemente:**
- Storage Rules: escrita restrita por `belongsToStore(lojaId)` (Firestore cross-service)
- OrderReviewScreen: boxes Hive por loja com HiveBoxNames + fallback legado controlado
- FirestoreCatalogProductSource: coleções `produtos` / `draft_produtos` alinhadas ao padrão
- Leitura pública de pre_pedidos removida; uso de pedido_status_publico
- clientes_portal para "Meus Pedidos"; getClienteCatalog via CF
- syncPedidoStatusPublico e syncClientePortalProfile em produção
- Tratamento de falhas de getClienteCatalog (perfil, carrinho, favoritos)
- clientes.get público removido via CF + rules; list com limit 10 para login

**O que ainda merece atenção:**
- gerarCupomNumeroSorte usa coleção errada (`campanhas` vs `campanhas_sorteio`)
- Fallback `defaultValue: 'default'` em várias telas → risco de loja errada
- clientes.update rule ainda permissiva (qualquer auth pode atualizar se preservar email)
- clientes.list com limit <= 10 permite listagem sem auth (login/cadastro; vazamento de até 10 PII)
- redirectCatalogo e findLojaIdByOrderId iteram todas as lojas (custo/escalabilidade)
- Sync offline não roda no Web (comportamento esperado, mas divergente)

---

## 2. TOP 10 RISCOS REMANESCENTES

| # | Risco | Severidade | Onde | Quando | Plataformas |
|---|-------|------------|------|--------|-------------|
| 1 | **gerarCupomNumeroSorte** usa coleção `campanhas` em vez de `campanhas_sorteio` | **ALTO** | `functions/index.js` ~2777, `gerarCupomNumeroSorte.js` ~113 | Pós-pagamento catálogo | Backend |
| 2 | **Fallback `'default'`** em lojaId/store_id em relatórios, backup, vendas, etc. | **MÉDIO** | relatorios_screen, relatorio_financeiro, backup_auto, vendas_service, cadastro_catalogo, catalago_screen | store_id ausente | APK, Web |
| 3 | **clientes.update** permite qualquer autenticado se `email == resource.data.email` | **MÉDIO** | `firestore.rules` linha ~357 | Update em lojas de outro dono | Web, APK |
| 4 | **clientes.list** com `limit <= 10` sem auth permite listar até 10 PII | **MÉDIO** | `firestore.rules` linha ~355 | Query sem where; fluxo login | Web |
| 5 | **redirectCatalogo** itera todas as lojas para resolver slug | **MÉDIO** | `functions/index.js` | Cada /c/{short} | Backend |
| 6 | **findLojaIdByOrderId** itera todas as lojas | **MÉDIO** | mpWebhookHandler.js, index.js | Webhook MP sem metadata.lojaId | Backend |
| 7 | **catalog_helpers** fallback Hive `config` no APK para checkout (checkoutCfg) | **BAIXO** | `catalog_helpers.dart` ~104 | Config não vinda do Firestore | APK |
| 8 | **campanhas_sorteio_screen** usa `defaultValue: 'mastepalm'` (inconsistente) | **BAIXO** | `campanhas_sorteio_screen.dart` | store_id ausente | APK |
| 9 | **Sync offline** não roda no Web; fila e cloud_sync desabilitados | **BAIXO** | sync_queue_service, cloud_sync_service | Modo offline Web | Web |
| 10 | **Storage Rules** com `firestore.get()` podem falhar se Firestore/Storage mal configurados | **BAIXO** | `storage.rules` | Deploy/primeiro upload | Todas |

---

## 3. O QUE FOI REALMENTE RESOLVIDO

| Problema | Mitigação | Status |
|----------|-----------|--------|
| Leitura pública de pre_pedidos | Uso de pedido_status_publico + clientes_portal | ✅ Resolvido |
| Dados de cliente no catálogo | getClienteCatalog (CF) + rules sem get público em clientes | ✅ Resolvido |
| "Meus Pedidos" | clientes_portal/{portalToken}/pedidos | ✅ Resolvido |
| syncPedidoStatusPublico / syncClientePortalProfile | Triggers em produção | ✅ Resolvido |
| Falhas de getClienteCatalog | UX tratada (perfil, carrinho, favoritos, SnackBar) | ✅ Resolvido |
| Storage write em loja de outro | belongsToStore(lojaId) com Firestore | ✅ Resolvido |
| OrderReviewScreen Hive boxes | HiveBoxNames + lojaId + fallback legado | ✅ Resolvido |
| FirestoreCatalogProductSource coleções | produtos / draft_produtos | ✅ Resolvido |
| Catch silenciosos principais | Tratamento em fluxos críticos (cliente, carrinho) | ✅ Parcialmente mitigado |
| Temp collections lojaId | Validação resourceLojaIdMatchesPathIfPresent | ✅ Já estava ok |

---

## 4. O QUE AINDA ESTÁ FRÁGIL

| Área | Fragilidade | Impacto |
|------|-------------|---------|
| **gerarCupomNumeroSorte** | Coleção `campanhas` inexistente; padrão é `campanhas_sorteio` | Cupom/número da sorte nunca registrados em campanha |
| **Fallback 'default'** | Loja `default` pode não existir ou ser de outro contexto | Relatórios, backup, vendas em loja errada |
| **clientes update** | Qualquer auth pode atualizar cliente de qualquer loja | Risco de alteração indevida de PII |
| **clientes list** | limit 10 sem auth permite enumerar clientes | Vazamento de até 10 emails/nomes por loja |
| **redirectCatalogo** | Itera todas as lojas | Latência e custo com muitas lojas |
| **Sync Web** | Sem fila offline, sem cloud_sync | Web com comportamento diferente do APK |
| **Hive config global** | `config`, `sessao` usados em vários fluxos; store_id pode ser legado | Loja incorreta em edge cases |

---

## 5. PONTOS ONDE SINCRONIZAÇÃO ENTRE PLATAFORMAS AINDA PODE FALHAR

| Origem | Destino | Risco | Condição |
|--------|---------|-------|----------|
| Venda catálogo (pre_pedido → estoque_vendas) | Hive APK | Hive desatualizado | APK sem sync após venda catálogo |
| Web admin | Hive | Não usa Hive da mesma forma | Web usa Firestore direto; APK usa Hive |
| Fallback loja 'default' | Firestore/Hive | Dados da loja errada | store_id ausente em sessão |
| gerarCupomNumeroSorte | campanhas_sorteio/participantes | Nunca grava | Coleção `campanhas` não existe |
| redirectCatalogo | /loja/{slug} | Falha ou demora | Muitas lojas; busca sequencial |
| Fila offline (Web) | Firestore | Sem fila | Web não processa fila pendente |

---

## 6. ARQUIVOS MAIS SENSÍVEIS RESTANTES

| Arquivo | Motivo |
|---------|--------|
| `firestore.rules` | Regras de clientes (update, list); validações restantes |
| `functions/index.js` | gerarCupomNumeroSorte, redirectCatalogo |
| `functions/gerarCupomNumeroSorte.js` | Coleção `campanhas` |
| `functions/src/mpWebhookHandler.js` | findLojaIdByOrderId |
| `lib/screens/relatorios_screen.dart` | defaultValue 'default' |
| `lib/screens/relatorio_financeiro_screen.dart` | defaultValue 'default' |
| `lib/screens/relatorio_vendedor_screen.dart` | defaultValue 'default' |
| `lib/services/backup_auto_service_io.dart` | Fallback 'default' |
| `lib/services/vendas_service.dart` | venda.lojaId ?? 'default' |
| `lib/screens/backup_screen_web.dart` | Fallback 'default' |
| `lib/screens/cadastro_catalogo_screen.dart` | Fallback 'default' |
| `lib/screens/catalago_screen.dart` | _lojaId ?? 'default' |
| `lib/screens/campanhas_sorteio_screen.dart` | defaultValue 'mastepalm' |

---

## 7. RISCOS DE PRODUÇÃO

| Risco | Probabilidade | Impacto | Mitigação sugerida |
|-------|---------------|---------|--------------------|
| gerarCupomNumeroSorte não registra em campanha | Alta | Médio | Corrigir coleção para `campanhas_sorteio` |
| Usuário vê dados de loja errada (fallback default) | Média | Alto | Trocar fallback por erro ou LojaIdService.ensure |
| Storage rules falham no deploy | Baixa | Alto | Validar em staging antes de produção |
| clientes update indevido | Baixa | Médio | Adicionar belongsToStore no update |
| clientes list vaza PII | Baixa | Médio | Avaliar se limit 10 é necessário; documentar risco |

---

## 8. RISCOS DE ESCALABILIDADE

| Ponto | Problema | Quando piora |
|-------|----------|--------------|
| redirectCatalogo | Itera todas as lojas | > 50 lojas |
| findLojaIdByOrderId | Itera todas as lojas | Webhook MP sem metadata; muitas lojas |
| Queries em produtos/estoque | Possível falta de índices compostos | Queries com where+orderBy |
| Relatórios | Queries amplas sem paginação | Muitas vendas/produtos |
| Sync Firestore→Hive | Full sync sem cursor | Muitos documentos por loja |

---

## 9. CHECKLIST DE PRÓXIMAS CORREÇÕES POR PRIORIDADE

### Prioridade 1 — Alto
- [ ] **gerarCupomNumeroSorte**: trocar `.collection('campanhas')` para `.collection('campanhas_sorteio')` em `functions/index.js` e `gerarCupomNumeroSorte.js`

### Prioridade 2 — Médio
- [ ] **Fallback 'default'**: substituir por `LojaIdService.get()` ou lançar erro; não usar 'default' como lojaId
- [ ] **clientes update rule**: incluir `belongsToStore(lojaId)` ou restringir a self (portalToken) no update
- [ ] **clientes list rule**: avaliar remoção de `request.query.limit <= 10` ou exigir `belongsToStore` sempre; documentar se mantido

### Prioridade 3 — Baixo
- [ ] **redirectCatalogo**: criar índice/coleção mapeando slug→lojaId para evitar iteração
- [ ] **findLojaIdByOrderId**: garantir `metadata.lojaId` em createPreference para evitar fallback
- [ ] **campanhas_sorteio_screen**: alinhar fallback a 'default' ou remover
- [ ] **catalog_helpers**: documentar fallback Hive config como legado APK

---

## 10. O QUE NÃO MEXER AGORA (evitar regressão)

| Área | Motivo |
|------|--------|
| PedidoCollectionResolver e fluxos de pedido | Estáveis; temp com validação lojaId |
| syncPedidoStatusPublico, syncClientePortalProfile | Funcionando em produção |
| mpWebhookHandler (transação atômica, idempotência) | Sólido |
| publishLojaDraft | Fluxo ok |
| getClienteCatalog e UX de falha | Já revisados |
| Storage Rules (belongsToStore) | Corrigido; validar em staging |
| OrderReviewScreen Hive | Corrigido |
| FirestoreCatalogProductSource | Corrigido |
| HiveBoxNames, HiveMultiStore | Estrutura estável |
| StoreResolverService, LojaIdService | Lógica complexa; alterar com cuidado |
| Temp collections (temp_orders, pedidos_temp) | Regras e paths ok |
| Firestore Rules de pedidos, pre_pedidos | Validadas |

---

## 11. SINCRONIZAÇÃO POR BLOCO (RESUMO)

| Bloco | Status | Observação |
|-------|--------|------------|
| **Multi-loja** | ✅ OK | Storage e OrderReviewScreen corrigidos; fallback 'default' ainda em uso |
| **Pedidos e espelhos** | ✅ OK | pre_pedidos → pedido_status_publico → clientes_portal |
| **Clientes e clientes_portal** | ✅ OK | CF getClienteCatalog; rules restritivas; update ainda permissivo |
| **Produtos e catálogo** | ✅ OK | FirestoreCatalogProductSource alinhado |
| **Fotos e Storage** | ✅ OK | Storage Rules com belongsToStore |
| **Vendas e estoque** | ✅ OK | mpWebhook atômico; sync Firestore↔Hive |
| **Hive/cache** | ⚠️ Parcial | OrderReviewScreen ok; fallback 'default' em vários pontos |
| **Firestore Rules** | ⚠️ Parcial | clientes update/list frágeis |
| **Cloud Functions** | ⚠️ Parcial | gerarCupomNumeroSorte com coleção errada |
| **UX e erros** | ✅ OK | Principais fluxos tratados |
| **Sincronização Web/APK** | ⚠️ Parcial | Web sem sync offline (esperado) |
| **Custo/performance** | ⚠️ Atenção | redirectCatalogo e findLojaId iteram lojas |

---

**Fim do relatório.**
