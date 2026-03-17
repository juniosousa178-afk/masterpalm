# Análise e Atualização das Regras Firestore — MasterPalm

## Objetivo
Atualizar `firestore.rules` para cobrir todos os caminhos usados pelo app, sem quebrar o que já funciona.

---

## Mapa de Coleções e Permissões

### Coleções raiz

| Coleção | Quem lê | Quem escreve |
|---------|---------|--------------|
| `app_config` | site_config: público; master_config: admin/programador | root admin |
| `usuarios` | autenticado | próprio doc ou admin |
| `users` | próprio uid ou admin | próprio uid ou admin |
| `checkout_planos` | próprio userId ou admin | autenticado (create); admin (update/delete) |
| `lojas` | público (se published) ou autenticado | admin |
| `pedidos` (root) | admin | admin |
| `pedidos_temp` (root) | se doc existe | create/update (validação); delete se doc existe |
| `vendas` (root) | admin | autenticado (create); admin (update/delete) |
| `stores` | se doc existe | admin |
| `_healthcheck` | autenticado | autenticado |
| `debug_check` | admin | admin |
| `_rate_limits`, `_idempotency`, `_mp_webhook_processed` | negado | negado |
| `order_loja_index`, `catalog_redirect_index` | negado | negado (uso CF Admin) |

### Subcoleções de lojas/{lojaId}

| Subcoleção | Quem lê | Quem escreve |
|------------|---------|--------------|
| `config` (config, payments, roleta_sorte, fretes) | público (resource != null) | admin |
| `draft_config` | admin | admin |
| `produtos` | público | admin |
| `draft_produtos`, `produtos_rascunho` | admin | admin |
| `clientes` | belongsToStore ou limit 1 | create: validação; update: belongsToStore; delete: admin |
| `clientes_catalogo/{email}/cupons` | público | create: validação; update/delete: admin |
| `clientes_portal` | público | belongsToStore |
| `estoque_produtos`, `estoque_clientes`, `estoque_vendas` | admin ou vendedor | admin ou vendedor |
| `pedidos`, `pre_pedidos`, `pedidos_pendentes` | conforme doc | conforme doc |
| `pedidos_temp`, `pedido_temp`, `temp_orders` | se doc existe | validação + belongsToStore |
| `campanhas_sorteio`, `participantes`, `historico_sorteios` | público (read) ou belongsToStore | belongsToStore |
| `ia_uso` | belongsToStore | belongsToStore |
| `canais`, `canais_publicos` | conforme doc | admin |
| `configuracoes`, `metas`, `vendedores`, `members` | conforme doc | admin/belongsToStore |
| `roleta_vendas` | admin | autenticado (create) |
| `motor_campanhas` | belongsToStore | belongsToStore |

---

## Alterações Aplicadas

### 1. app_config/master_config
**Problema:** PERMISSION_DENIED ao ler `app_config/master_config` para admin/programador (não root).

**Solução:** Incluir leitura para `master_config` quando `isAdminOrSystem()`.

```
allow read: if doc == 'site_config'
  || isRootAdmin()
  || (doc == 'master_config' && isAdminOrSystem());
```

### 2. motor_campanhas
**Problema:** Coleção `lojas/{lojaId}/motor_campanhas` usada pelo Motor de Crescimento IA não tinha regra explícita (caía no deny-all final).

**Solução:** Adicionar regra explícita.

```
match /motor_campanhas/{campanhaId} {
  allow read, write: if belongsToStore(lojaId);
}
```

---

## O Que Já Estava Correto

- **Catálogo:** config, produtos, cupons — leitura pública
- **Checkout:** pre_pedidos, pedidos_pendentes — create público com validação
- **Vendas:** estoque_vendas — admin e vendedor
- **Clientes:** create público com validação; get/list restritos
- **Campanhas sorteio:** read público; write belongsToStore
- **config/roleta_sorte:** coberto por `config/{configId}` (read público, write admin)
- **config/fretes:** idem

---

## Validação

| Critério | Status |
|----------|--------|
| app_config/master_config | Admin/programador pode ler |
| motor_campanhas | Admin/vendedor pode ler/escrever |
| Regras existentes | Mantidas |
| Catálogo público | Mantido (config, produtos, cupons) |
| Checkout/Pedidos | Mantido |
| Vendas/Estoque | Mantido |

---

## Deploy

```bash
firebase deploy --only firestore:rules
```

Antes de fazer deploy em produção, testar em projeto de desenvolvimento e validar:

1. Login como admin/programador → MasterConfigScreen carrega
2. Catálogo público → config, produtos
3. Motor de Crescimento → motor_campanhas
4. Checkout → pre_pedidos, pedidos_pendentes
5. Nova venda → estoque_vendas
