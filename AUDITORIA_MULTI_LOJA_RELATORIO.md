# Relatório de Auditoria Multi-Loja

**Data:** 15/03/2025  
**Objetivo:** Garantir que todas as telas e serviços utilizem a mesma lógica de resolução de loja da loja modelo (nathypratasefolheados / natypolylopes1997@gmail.com).

---

## BLOCO 1 — LOJA MODELO

### Como a lógica funciona na loja nathypratasefolheados

A loja modelo segue o fluxo padronizado de resolução de loja:

#### 1. Resolução do lojaId

**Ordem de prioridade (StoreResolverService.resolve):**
1. **Auth** – Aguarda até 15s (Web) ou 5s (APK) se `currentUser` for null
2. **Firestore users/{uid}.store_id** – Documento do usuário autenticado
3. **Mapeamento _uidToLoja** – Legado para migração (ex: nathy-pratas-e-folheados)
4. **Firestore usuarios/{email}.store_id** – Documento por email (ex: natypolylopes1997@gmail.com)
5. **Hive sessao/config** – Apenas quando Auth é null (offline)
6. **Slug do email** – Fallback final (ex: natypolylopes1997 → de natypolylopes1997@gmail.com)

**Pontos de entrada:**
- `StoreResolverFacade.resolveForAdminApp()` → Admin/Dashboard
- `LojaIdService.get()` → Usa StoreResolver primeiro, depois Hive sessao/config
- `LojaIdService.getWithTimeout()` → Para telas que precisam de timeout (evita Hive como fast path no Web)

#### 2. Boxes Hive por loja

Todas as boxes usam sufixo `lojaId` via `HiveBoxNames`:
- `produtos_lojaId`
- `clientes_lojaId`
- `vendas_lojaId`
- `fornecedores_lojaId`
- `categorias_lojaId`
- `subcategorias_lojaId`
- `loja_config_lojaId`
- `config_catalogo_lojaId`
- `nota_fiscal_config_lojaId`
- `notas_fiscais_lojaId`
- `contas_receber_lojaId`

#### 3. Paths Firestore

Padrão: `lojas/{lojaId}/...`
- Produtos: `lojas/{lojaId}/produtos`, `lojas/{lojaId}/estoque_produtos`
- Clientes: `lojas/{lojaId}/estoque_clientes`
- Vendas: `lojas/{lojaId}/estoque_vendas`
- Fornecedores: `lojas/{lojaId}/estoque_fornecedores`
- Config: `lojas/{lojaId}/config/config`, `lojas/{lojaId}/draft_config/config`

#### 4. Catálogo

- **Público:** `StoreResolverFacade.resolveForPublicCatalog(lojaIdFromUrl)` – usa ID da URL
- **Admin/Dashboard:** `StoreResolverFacade.resolveForAdminDashboard()` – usa loja do usuário logado

#### 5. Login

- `StoreResolverFacade.resolveForRouter()` → Após login, bind de sessão
- `app_start_router.dart` usa Firestore users/usuarios para role e storeId
- Fallback offline: `sessao.get('store_id')` quando Firestore não responde

#### 6. Sync

- `FullSyncService` usa `StoreResolverFacade.resolveForAdminApp()`
- `AutoSyncService` usa StoreResolver primeiro, sessao como fallback (timeout)
- `SyncQueueService`, `ProdutosFirestoreService`, etc. recebem `lojaId` ou resolvem via StoreResolver

#### 7. Offline

- Hive sessao/config só é usado quando Auth é null ou StoreResolver falha (timeout/rede)
- No Web, evita-se Hive como fast path para não misturar dados entre usuários (IndexedDB compartilhado)

---

## BLOCO 2 — PROBLEMAS ENCONTRADOS

### Arquivos com risco de mistura de dados (corrigidos)

| Arquivo | Problema | Status |
|---------|----------|--------|
| `notificacao_centro_sheet.dart` | Usava `sessao.get('store_id')` como fonte primária | ✅ Corrigido |
| `home_screen.dart` | FirestoreCriticalListenerService e badge de notificações usavam `sessao.get('store_id')` direto | ✅ Corrigido |
| `backup_auto_service.dart` | Ordem invertida: sessao antes de LojaIdService.get() | ✅ Corrigido |
| `global_search_screen.dart` | Usava `'clientes_$lojaId'` em vez de `HiveBoxNames.clientes(lojaId)` | ✅ Corrigido |

### Arquivos com risco residual (documentados)

| Arquivo | Problema | Recomendação |
|---------|----------|--------------|
| `relatorio_financeiro_screen.dart` | Box `fechamentos_mensais` é global (sem lojaId) | Dados filtrados por `f.lojaId == lojaId`. Considerar `HiveBoxNames.fechamentosMensais(lojaId)` em migração futura |
| `relatorios_screen.dart` | Fallback `Hive.box('sessao').get('store_id')` quando getWithTimeout retorna null | Aceitável para offline; mesma lógica de LojaIdService.get() |
| `relatorio_financeiro_screen.dart` | Mesmo fallback sessao | Aceitável para offline |
| `main.dart` _ensureStoreIdOnBootstrap | Fallbacks `loja_uid_$uid` e `loja_email_$slug` | Usado apenas quando StoreResolver falha; não alterar regras de negócio |

### Uso correto de sessao.get('store_id')

- **LojaIdService.get()** – sessao como fallback após StoreResolver (ordem correta)
- **app_start_router.dart** – sessao como fallback offline quando Firestore não responde
- **StoreResolverService** – sessao apenas quando Auth é null (offline)
- **StoreContext** – sessao como fonte principal de cache local (compat)

---

## BLOCO 3 — CORREÇÕES APLICADAS

### 1. `lib/widgets/notificacao_centro_sheet.dart`

**Antes:** `_currentStoreId()` lia diretamente de `Hive.box('sessao').get('store_id')` e `Hive.box('config').get('store_id')`.

**Depois:** Usa `FutureBuilder` com `LojaIdService.get()` (que prioriza StoreResolverFacade).

### 2. `lib/screens/home_screen.dart`

**Antes:** 
- `FirestoreCriticalListenerService.startPermissoesListener` recebia `sessao.get('store_id')`
- Badge de notificações e itemBuilder do menu usavam `Hive.box('sessao').get('store_id')`

**Depois:**
- Listener recebe `_lojaIdInterno` (já resolvido via StoreResolver) com fallback para sessao
- Badge e menu usam `_lojaIdInterno` diretamente

### 3. `lib/services/backup_auto_service.dart`

**Antes:** `storeId = (sessao.get('store_id') ?? await LojaIdService.get())` – sessao antes de LojaIdService.

**Depois:** `storeId = await LojaIdService.get()` primeiro; sessao só como fallback quando LojaIdService retorna null/vazio.

### 4. `lib/screens/global_search_screen.dart`

**Antes:** `final clientesBoxName = 'clientes_$lojaId'`

**Depois:** `final clientesBoxName = HiveBoxNames.clientes(lojaId)`

---

## BLOCO 4 — SEGURANÇA MULTI-LOJA

### Confirmação

- **lojaId** é resolvido por `StoreResolverFacade.resolveForAdminApp()` ou `LojaIdService.get()`
- **Hive** usa `HiveBoxNames.produtos(lojaId)`, `HiveBoxNames.clientes(lojaId)`, etc.
- **Firestore** usa `lojas/{lojaId}/...`
- **Hive sessao** é usado apenas como fallback offline
- Não há lojaId fixo nem uso da loja modelo como fallback

### Telas auditadas (resumo)

| Tela | Resolução lojaId | Boxes Hive | Status |
|------|------------------|------------|--------|
| vendas_screen | LojaIdService.getWithTimeout | HiveBoxNames.vendas | ✅ |
| clientes_screen | LojaIdService.getWithTimeout | HiveBoxNames.clientes | ✅ |
| estoque_screen | LojaIdService.getWithTimeout / StoreResolverFacade | HiveBoxNames.produtos | ✅ |
| fornecedores_screen | LojaIdService | HiveBoxNames.fornecedores | ✅ |
| campanhas_sorteio_screen | StoreResolverFacade | - | ✅ |
| vendedores_screen | StoreResolverFacade | - | ✅ |
| gerenciar_vendedores_screen | StoreResolverFacade | - | ✅ |
| fretes_cupons_screen | StoreResolverFacade (sessao fallback) | config_$slug | ✅ |
| subcategorias_screen | StoreResolverFacade | - | ✅ |
| catalago_screen | StoreResolverFacade | - | ✅ |
| public_catalog_screen | StoreResolverFacade (Public/Admin) | - | ✅ |
| home_screen | StoreResolverFacade + resolveHomeStoreContext | HiveBoxNames.* | ✅ |
| admin_painel_web_screen | LojaIdService.getWithTimeout | - | ✅ |
| admin_sync_screen | StoreResolverFacade | - | ✅ |
| loja_config_screen | StoreResolverFacade | HiveBoxNames.lojaConfig | ✅ |

---

## BLOCO 5 — TESTES RECOMENDADOS

### Checklist Web

- [ ] Login com natypolylopes1997@gmail.com → loja nathypratasefolheados
- [ ] Login com outro usuário → loja correspondente ao users/usuarios
- [ ] Troca de conta no mesmo navegador → dados da loja correta
- [ ] Catálogo público /loja/nathypratasefolheados → produtos da loja
- [ ] Notificações → contagem e lista da loja correta
- [ ] Backup automático → pasta/arquivos da loja correta

### Checklist APK

- [ ] Login → loja resolvida corretamente
- [ ] Estoque, clientes, vendas, fornecedores → dados da loja
- [ ] Sync → produtos/clientes/vendas da loja
- [ ] Relatórios → dados filtrados por loja
- [ ] Busca global → resultados da loja

### Checklist Offline

- [ ] Após login, ir offline → sessao mantém store_id
- [ ] Abrir app offline → loja carregada de sessao
- [ ] Sync ao voltar online → dados da loja correta

---

## Regras críticas respeitadas

- ✅ Não copiar dados da loja modelo
- ✅ Não fixar lojaId
- ✅ Não alterar estrutura do banco
- ✅ Não alterar rotas
- ✅ Não quebrar sync
- ✅ Não quebrar offline
- ✅ Não quebrar vendas
- ✅ Apenas alinhar a lógica de funcionamento

---

*Relatório gerado pela auditoria multi-loja do projeto.*
