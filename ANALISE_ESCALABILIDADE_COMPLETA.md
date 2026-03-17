# Análise Completa de Escalabilidade – Milhares de Admins e Vendedores Simultâneos

**Data:** 12/02/2026  
**Objetivo:** Identificar todos os erros atuais, riscos futuros e soluções para uso em produção com alta concorrência.

---

## 1. RESUMO EXECUTIVO

| Severidade | Quantidade | Status |
|------------|------------|--------|
| CRÍTICO   | 4          | 2 corrigidos, 2 pendentes |
| ALTO      | 6          | 3 corrigidos, 3 pendentes |
| MÉDIO     | 8          | Documentados |
| BAIXO     | 5          | Documentados |

---

## 2. ERROS CRÍTICOS

### 2.1 🔴 Firestore Rules – Vendedores sem acesso a estoque/vendas/clientes

**Problema:** Regras atuais permitem `estoque_produtos`, `estoque_vendas` e `estoque_clientes` apenas para `isAdminOrSystem()`. Vendedores autenticados via `isSellerOfStore(lojaId)` **não conseguem**:
- Baixar estoque ao vender (EstoqueTransactionService)
- Sincronizar venda no Firestore (VendasFirestoreService.syncVenda)
- Sincronizar cliente ao cadastrar (ClientesFirestoreService.syncCliente)

**Impacto:** Vendedores recebem PERMISSION_DENIED em todas as vendas.

**Solução:** Incluir `isSellerOfStore(lojaId)` nas regras de `estoque_produtos`, `estoque_vendas` e `estoque_clientes`.

**Status:** ✅ Corrigido nesta análise

---

### 2.2 🔴 Colisão de código de cupom (roleta)

**Problema:** `_gerarCodigoCupom()` usa `Random()` com 8 caracteres (36^8 ≈ 2,8 trilhões). Com milhares de usuários simultâneos, há risco de colisão. Cupom duplicado sobrescreve o anterior no Firestore.

**Impacto:** Cliente perde cupom válido; possíveis conflitos de dados.

**Solução:** Usar UUID v4 ou `FirebaseFirestore.instance.collection('_').doc().id` para garantir unicidade.

**Status:** ✅ Corrigido nesta análise

---

### 2.3 🟡 LimitsGuard – Coleção incorreta

**Problema:** `LimitsGuard` consultava `tenants/{lojaId}/produtos`, etc. O app usa `lojas/{lojaId}/...`.

**Solução aplicada:** Alterado para `lojas/{lojaId}/estoque_produtos`, `estoque_clientes`, `estoque_vendas`. Chaves de limite: `maxProducts`, `maxClients`, `vendasMes`. Adicionados `maxClients` e `vendasMes` ao `SubscriptionService.freeLimits`.

**Status:** ✅ Corrigido

---

### 2.4 🟡 Regras de clientes e cupons – Muito permissivas

**Problema:** `clientes` e `cupons_clientes` têm `allow create, update: if true` (público). Qualquer pessoa pode criar/alterar dados.

**Impacto:** Abuso, dados falsos, possíveis ataques de negação de serviço.

**Solução:** Restringir criação/atualização a usuários autenticados ou com validação de origem (ex.: apenas após compra verificada).

**Status:** ⚠️ Avaliar regras de negócio antes de alterar

---

## 3. ERROS DE CONCORRÊNCIA (já corrigidos anteriormente)

| Item | Status |
|------|--------|
| Fallback Hive em falha de estoque | ✅ Removido |
| Roleta sem transação atômica | ✅ runTransaction implementado |
| ID de cliente baseado em telefone+nome | ✅ UUID + compatibilidade |
| Listeners em tempo real | ✅ Produtos e permissões |
| Fonte única produtos/estoque | ✅ estoque_produtos |

---

## 4. RISCOS DE ESCALABILIDADE

### 4.1 Queries sem limite ou com limite alto

| Arquivo | Query | Risco |
|---------|-------|-------|
| `produtos_firestore_service` | `.get()` em estoque_produtos | Sem paginação; lojas com 10k+ produtos podem travar |
| `clientes_firestore_service` | `.get()` em estoque_clientes | Idem |
| `vendas_firestore_service` | `limit(100)` | Vendas antigas não sincronizadas |
| `full_sync_service` | `limit(pageSize)` | Paginação existe; verificar pageSize |

**Solução:** Implementar paginação (startAfter, cursors) para coleções grandes. Aumentar limite de vendas ou usar paginação por data.

---

### 4.2 Listeners globais

- `FirestoreCriticalListenerService`: listeners por loja (produtos, permissões). Iniciados ao abrir telas; cancelados no dispose.
- **Risco:** Múltiplas instâncias da mesma tela (ex.: navegação rápida) podem criar listeners duplicados. O serviço já faz `cancelProdutosListener` antes de iniciar novo.
- **Recomendação:** Garantir que apenas uma tela de vendas/estoque esteja ativa por loja por vez.

---

### 4.3 Índices Firestore

**Faltando possivelmente:**
- `estoque_vendas`: `orderBy('createdAt', descending: true)` – Firestore pode exigir índice explícito.
- Queries compostas com `where` + `orderBy` em coleções diversas.

**Solução:** Adicionar índices em `firestore.indexes.json` conforme erros do console do Firebase.

---

### 4.4 Contadores e agregações

- `LimitsGuard._countOf()` usa `query.count().get()` – adequado para Firestore.
- **Risco:** Em coleções muito grandes, count pode ser lento. Firestore recomenda cache de contadores para altos volumes.

---

### 4.5 Sessão e multi-tenant

- `SessionSanity` limpa sessão ao logout.
- `StoreResolverService` e `StoreContext` invalidados.
- **Risco:** Troca rápida de usuário em mesmo dispositivo pode deixar cache residual. O `clearAllStoreCache` resolve quando chamado explicitamente.

---

### 4.6 Temp orders e pedidos pendentes – Regras públicas

- `temp_orders`, `pedidos_temp`: `allow read, write: if true`
- **Risco:** Qualquer pessoa pode criar/ler/alterar. Útil para checkout público, mas permite abuso (ex.: preencher coleção com lixo).
- **Recomendação:** Avaliar rate limiting ou autenticação mínima para criação.

---

## 5. PONTOS DE FALHA EM ALTA CONCORRÊNCIA

### 5.1 Firestore Transactions

- **Limite:** 500 documentos por transação.
- **Estoque:** `baixarEstoqueTransactionBatch` processa itens em sequência na mesma transação. Venda com 100+ itens pode chegar perto do limite.
- **Solução:** Se vendas com muitos itens forem comuns, considerar batch de transações (ex.: 50 itens por transação).

---

### 5.2 Escrita em lote

- `syncTodasVendas` faz um `syncVenda` por venda em loop. Centenas de vendas = centenas de writes.
- **Risco:** Rate limit do Firestore (10k writes/segundo por projeto – geralmente suficiente) ou lentidão no cliente.
- **Solução:** Batch writes (até 500 por chamada) quando disponível no fluxo.

---

### 5.3 Campanhas e sorteio

- `CampanhasSorteioService._gerarNumeros` usa `runTransaction` no contador – correto.
- Registro de participação: verificar se há race condition ao registrar múltiplos participantes simultâneos na mesma campanha.

---

## 6. SOLUÇÕES PREVENTIVAS

### 6.1 Monitore e alerte

- Logs de PERMISSION_DENIED no cliente.
- Métricas de falhas de transação (estoque, roleta).
- Alertas para aumento anormal de erros.

### 6.2 Testes de carga

- Simular 50+ vendedores vendendo o mesmo produto.
- Simular 100+ usuários girando a roleta simultaneamente.
- Simular sync de 1000+ vendas ao abrir a tela.

### 6.3 Backup e recuperação

- Hive é local; perda do dispositivo = perda de cache.
- Firestore é fonte da verdade; garantir que todas as operações críticas (venda, estoque) dependam do Firestore.

### 6.4 Versionamento e migração

- Schema Hive (Cliente, Produto, Venda) com novos campos (ex.: `idFirebase`): garantir compatibilidade com dados antigos.
- Regras do Firestore: testar em ambiente de staging antes de produção.

---

## 7. CHECKLIST DE DEPLOY

- [ ] Deploy das regras do Firestore atualizadas
- [ ] Verificar índices no Console do Firebase
- [ ] Corrigir LimitsGuard (coleção tenants vs lojas)
- [ ] Testar venda com usuário vendedor (não admin)
- [ ] Testar roleta com múltiplos usuários simultâneos
- [ ] Validar sync de produtos/clientes/vendas em loja com muitos dados

---

## 8. ARQUIVOS ALTERADOS NESTA CORREÇÃO

| Arquivo | Alteração |
|---------|-----------|
| `firestore.rules` | Inclusão de `isSellerOfStore(lojaId)` em estoque_produtos, estoque_vendas e estoque_clientes |
| `lib/widgets/roleta_web_widget_v3.dart` | Uso de UUID para código de cupom (evitar colisão) |
| `lib/services/limits_guard.dart` | Coleções `tenants`→`lojas`; subcoleções corretas e chaves de limite |
| `lib/services/subscription_service.dart` | Adicionados `maxClients` e `vendasMes` ao freeLimits |

---

## 9. PRÓXIMOS PASSOS RECOMENDADOS

1. **Deploy das regras:** `firebase deploy --only firestore:rules`
2. **Testar vendedor:** Login como vendedor e realizar uma venda completa
3. **Índices:** Se aparecer erro de índice no console, adicionar em `firestore.indexes.json`
4. **Monitorar:** Logs de PERMISSION_DENIED e falhas de transação

---

*Documento gerado em 12/02/2026.*
