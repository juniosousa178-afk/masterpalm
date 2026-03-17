# Onde o app usa Firestore e Storage (custo e otimização)

Documento para acompanhar uso e decidir onde otimizar. **Atualize** quando adicionar novas queries ou descobrir gargalos.

---

## Tela que mais pode causar custo: Catálogo público

A tela que **mais pode elevar o custo** é o **Catálogo público** (`lib/screens/public_catalog_screen.dart`), usada por **clientes** (link compartilhado da loja). Motivos:

| O que ela faz | Por que o custo sobe |
|---------------|----------------------|
| **Listener em `config`** (`configRef.snapshots().listen`) | Cada alteração no documento `config` da loja gera **1 leitura** para **cada** cliente com o catálogo aberto. Vários visitantes = várias leituras por mudança. |
| **`paymentsRef.get()` dentro do listener de config** | Toda vez que o config muda, o código faz **mais 1 leitura** (doc `payments`) para cada listener ativo. Ou seja: 10 usuários com catálogo aberto = 10 leituras de config + 10 de payments a cada mudança. |
| **Listener em produtos com `.limit(1000)`** | Stream em `produtos` (ou `produtos_rascunho`) com **até 1.000 documentos**. O Firestore cobra leituras quando envia o snapshot e quando há atualizações. Qualquer mudança em um produto pode gerar **novas leituras** para todos os clientes com a tela aberta. Quanto mais tempo a tela fica aberta e mais pessoas acessam, maior o custo. |
| **Fallback de cupons** | Era `.get()` sem limit; **corrigido:** `public_catalog_screen.dart` e `catalog_cache_service.dart` usam `.limit(50)` e `.limit(30)` respectivamente. |
| **Uso prolongado e muitas abas/usuários** | Como é a vitrine da loja, a tela costuma ficar aberta por mais tempo e ser acessada por muitos usuários ao mesmo tempo. Listeners ativos = leituras contínuas e em múltipliplas cópias (uma por cliente). |

**Resumo:** O custo sobe por (1) **listeners em tempo real** (config + até 1.000 produtos), (2) **leitura extra de `payments`** a cada mudança de config, (3) **query de cupons sem limit** no fallback e (4) **muitos acessos simultâneos** ao catálogo.

---

## Outras telas/serviços que impactam custo

| Tela / serviço | O que eleva o custo |
|----------------|----------------------|
| **FirestoreCriticalListenerService** (ativo ao abrir vendas/estoque) | Listener em **toda** a coleção `estoque_produtos` **sem limit**. Qualquer mudança em qualquer produto dispara o listener; em seguida é feita sincronização Firestore → Hive (mais leituras). Quanto mais produtos na loja, maior o custo. |
| **Campanha Participantes** (`campanha_participantes_screen`) | Stream em `participantes` com **`.snapshots()` sem `.limit()`**. Lista todos os participantes em tempo real; campanhas grandes = muitas leituras e atualizações. |
| **Tela Plano** (admin, `plano_screen`) | `collection('usuarios').get()` **sem limit**. Carrega **todos** os usuários do app (ex.: 1.000 usuários = 1.000 leituras) cada vez que o admin abre a tela. |
| **Pedido público** (`pedido_publico_screen`) | Fallback: quando o produto não está no Hive, faz `collection('produtos').get()` **sem limit**, carregando todos os produtos da loja (centenas de leituras por vez). |

---

## Firestore – principais pontos de leitura

| Área | Arquivo / fluxo | O que lê | Limite atual | Observação |
|------|------------------|----------|--------------|------------|
| **Sync inicial (login)** | `FullSyncService` | estoque_produtos, estoque_clientes | Paginado 500 | Já otimizado |
| **Catálogo público** | Vários | lojas/{id}/config, produtos, campanhas | config 1 doc; produtos 500 em alguns | Revisar listeners sem limit |
| **Resolução de loja** | StoreResolverService, main, app_start_router | users/{uid}, usuarios/{email}, lojas | 1 doc por vez | OK |
| **Banner campanhas** | campanha_banner_widget | campanhas_sorteio | limit(30) | ✅ |
| **Lista campanhas** | campanhas_sorteio_list_screen, CampaignEngine | campanhas_sorteio, participantes, historico | 50/100 em listagem; exclusão busca todos | listar: limit(100); excluir: sem limit (precisa apagar todos) |
| **Produtos (admin)** | produtos_service, catalogo_sync_service | draft_produtos, produtos | 500 / limit(500) | OK |
| **Pedidos / catálogo** | catalogo_venda_service, pedido_publico_screen | pedidos, pedidos_pendentes, pre_pedidos, produtos | Alguns sem limit | Candidato a limit |
| **Config loja** | loja_config_screen | config, draft_config, campanhas_sorteio | Alguns .get() sem limit | config costuma ser poucos docs |
| **Comissões** | comissao_service | comissoes | limit(limite) usado | OK |
| **Canais** | canais_service | canais_publicos, canais | limit(20) / limit(1) | OK |
| **License/Plano** | LicenseManager, PlanosService | users/{uid}, subscriptions | 1 doc ou limit(5) | OK |

---

## Firestore – escritas

- Sync: SyncQueueService envia Hive → Firestore (produto, cliente, venda, fornecedor).
- Cadastros/edição: produtos, clientes, vendas, config, campanhas, etc.
- Espelho de plano: users/{uid}, subscriptions.
- **Custo:** Escritas custam mais que leituras; evitar writes em loop (ex.: um write por item em lote pode usar batch ou transaction onde fizer sentido).

---

## Storage

- Fotos de produtos (upload ao cadastrar/editar).
- Possivelmente avatares ou anexos (conferir no app).
- **Otimização:** Validar tamanho máximo antes de subir (ex.: 2–5 MB por imagem); comprimir no cliente se a lib permitir.

---

## Como monitorar

1. **Firebase Console** → Uso e faturamento: Firestore (leituras/escritas), Storage, Auth.
2. **Google Cloud Console** → Billing → Relatórios: filtrar por produto (Firestore, Storage).
3. **Alertas:** Billing → Budgets & alerts → definir orçamento mensal e alerta (ex.: 50%, 90%, 100%).

### Configurar alerta de orçamento (Google Cloud)

1. Acesse [Google Cloud Console](https://console.cloud.google.com) → selecione o projeto do Firebase (ex.: masterpalm-58c46).
2. Menu **Faturamento** (Billing) → **Orçamentos e alertas** (Budgets & alerts).
3. **Criar orçamento** → nome (ex.: "MasterPalm mensal") → valor (ex.: R$ 200/mês).
4. Em **Alertas**, defina percentuais (ex.: 50%, 90%, 100%) para receber e-mail quando o uso atingir cada nível.
5. Salvar. Assim você evita surpresas na fatura.

---

## Próximas otimizações (sem quebrar)

- [x] Banner campanhas: limit(30). Loja config e CampaignEngine: limit(50) em listas de campanhas.
- [x] CampaignEngine.listarParticipacoes(): adicionado limit(100) (alinhado ao stream de participações).
- [ ] Adicionar `.limit(N)` em outras listas que ainda não tenham (ver greps no código).
- [ ] Onde a tela exibe “lista infinita”, garantir paginação ou “carregar mais” com limit fixo.
- [ ] Revisar listeners (snapshots) que ficam 24/7: trocar por get() + cache (Hive) quando os dados forem quase estáticos.

---

## Queries que não devem ter limit (intencional)

| Onde | Motivo |
|------|--------|
| FullSyncService (estoque_clientes, estoque_produtos) | Sync completo no login; precisa de todos (já paginado 500 em produtos). |
| campanhas_sorteio_list_screen: participantes/historico ao **excluir** campanha | Precisa buscar todos para apagar um a um. |
| campanhas_sorteio_service.sortearNumero: participantes.get() | Precisa de todos para achar o número sorteado. |
| Documento único (.doc(id).get()) | Não é lista; limit não se aplica. |

---

## Estimativa de custo: 1.000 usuários (APK)

Valores em **USD** (Firebase/Google Cloud fatura em dólar). Região de referência: americas (preços podem variar por região).

### Premissas de uso (MasterPalm)

- **1.000 usuários** = lojas ou usuários ativos cadastrados.
- **~30% ativos por dia** = 300 acessos/dia (abertura do app, sync ou uso).
- **Sync no login:** ~500 leituras (produtos paginados) + ~100 clientes por loja que sincroniza.
- **Uso diário por usuário ativo:** listagens (produtos, vendas, config), algumas escritas (vendas, atualizações). Estimativa: **~400 leituras** e **~30 escritas** por usuário ativo por dia.

### Firestore (referência: firebase.google.com/docs/firestore/pricing)

| Item | Free tier (diário) | Uso estimado 1k usuários | Excedente | Custo mensal (USD) |
|------|---------------------|---------------------------|-----------|---------------------|
| Leituras | 50.000/dia | ~120.000/dia (300 ativos × 400) | ~70.000/dia × 30 ≈ 2,1M/mês | 2,1M × US$ 0,03/100k ≈ **US$ 0,65** |
| Escritas | 20.000/dia | ~9.000/dia (300 × 30) | 0 (dentro do free) | **US$ 0** |
| Armazenamento | 1 GiB | Depende de docs (produtos, vendas, etc.) | Acima de 1 GiB ~ US$ 0,18/GiB/mês | **~US$ 2–5** se 10–20 GiB |

### Storage (fotos de produtos)

- **Free:** 5 GB.
- **Uso típico:** 1.000 lojas × ~50 produtos × 0,1 MB ≈ 5 GB (no limite) a 15 GB (mais fotos).
- **Excedente:** ~US$ 0,026/GB/mês (GCS Standard) ou plano Firebase Storage.
- **Estimativa:** **US$ 0** (até 5 GB) a **~US$ 1–3/mês** (5–15 GB).

### Auth, FCM, App Check, Remote Config

- **Auth:** uso normal fica dentro do free (até 50k MAU).
- **FCM, App Check, Remote Config:** sem custo adicional relevante para 1k usuários.

---

### Cenários mensais (1.000 usuários, USD)

| Cenário | Uso | Firestore | Storage | **Total/mês (USD)** | **Total/mês (BRL, ~5,50)** |
|---------|-----|-----------|---------|----------------------|-----------------------------|
| **Leve** | Poucos ativos/dia, sync raro, poucas fotos | ~US$ 1–3 | US$ 0 | **US$ 1–3** | **R$ 6–17** |
| **Médio** | ~30% ativos, uso como acima | ~US$ 5–15 | US$ 0–2 | **US$ 5–17** | **R$ 28–94** |
| **Alto** | Muitos ativos, sync frequente, muitas fotos | ~US$ 15–30 | US$ 2–5 | **US$ 17–35** | **R$ 94–193** |

*Conversão BRL ilustrativa (câmbio variável).*

---

### Como reduzir custo com 1.000 usuários

1. **Limites e paginação:** manter `.limit()` em listas e “carregar mais” (já em parte feito).
2. **Cache/sync:** reduzir sync completo por dia (ex.: sync full 1x/dia; atualizações incrementais).
3. **Storage:** limitar tamanho de upload (ex.: 2 MB por imagem) e comprimir no app.
4. **Monitorar:** Firebase Console → Uso; alerta de orçamento no Google Cloud (ver acima).
5. **Região:** deixar dados na região mais barata que atenda à LGPD (ex.: southamerica-east1).

**Resposta direta:** para **1.000 usuários**, em uso **médio**, espere algo em torno de **US$ 5–15/mês** (**R$ 28–83** em câmbio ~5,50). Em uso leve, pode ficar perto do free tier (**US$ 0–3**). Em uso intenso, **US$ 20–35/mês** é possível.

