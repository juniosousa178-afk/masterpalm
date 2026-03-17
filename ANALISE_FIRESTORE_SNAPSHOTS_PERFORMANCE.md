# Análise: Uso de snapshots() Firestore — Performance para 1000+ usuários

**Data:** 12/02/2026  
**Projeto:** MasterPalm

---

## 1. MAPEAMENTO ATUAL DE STREAMS

| Contexto | Coleção/Path | Arquivo | Limit? | Uso |
|----------|--------------|---------|--------|-----|
| Catálogo público | config/config | public_catalog_screen | ❌ | Config + tema da loja |
| Catálogo público | produtos (ou draft_produtos) | public_catalog_screen | ❌ | Lista de produtos |
| Pré-pedidos | pre_pedidos | pre_pedido_service | ✅ 50 | Lista pendentes/confirmados |
| Clientes | clientes | clientes_firestore_service | ❌ | streamClientes (não usado) |
| Vendas | estoque_vendas | vendas_firestore_service | ❌ | streamVendas (não usado) |
| Cupons disponíveis | cupons | cupom_desconto_service | ❌ | Checkout (modal cupom) |
| Cupons admin | cupons | cupom_desconto_service | ❌ | Tela fretes/cupons |
| Notificações | notificacoes | notificacao_vendas_service | ✅ 50 | Badge + lista |
| Config pagamentos | config/payments | pagamentos_service | - | 1 doc |
| Permissões admin | usuarios/{email} | firestore_critical_listener_service | - | 1 doc |
| Permissões vendedor | vendedores/{uid} | firestore_critical_listener_service | - | 1 doc |
| Estoque produtos | estoque_produtos | firestore_critical_listener_service | ❌ | Sync Hive multiusuário |
| Admin usuários | usuarios | admin_usuarios_screen | ❌ | Lista completa |
| Campanhas participantes | participantes | campaign_engine_service | ❌ | Histórico campanha |
| Fechamentos | fechamentos_mensais | fechamento_firestore_service | ❌ | Lista mensal |
| Canais públicos | canais_publicos | canais_service | ❌ | Catálogo |
| Canais privados | canais | canais_service | ❌ | Admin |
| Perfil cliente | clientes/{id} | perfil_cliente_screen_novo | - | 1 doc |
| Subscription | users/{uid} | subscription_service | - | 1 doc |
| Master config | app_config/master | master_config_service | - | 1 doc |
| Notas fiscais | notas_fiscais | nota_fiscal_firestore_service | ❌ | Lista |
| Fornecedores | estoque_fornecedores | fornecedores_firestore_service | ❌ | Lista |
| Produtos draft/live | draft_produtos, produtos | produtos_service | ❌ | Admin catálogo |

---

## 2. RECOMENDAÇÕES: REALTIME vs get()/PAGINADO

### 2.1 MANTER EM TEMPO REAL (crítico)

| Stream | Motivo |
|--------|--------|
| **Permissões** (admin/vendedor) | Segurança: revogação deve refletir imediatamente |
| **Estoque produtos** (FirestoreCriticalListener) | Multiusuário: sync Hive quando outro vendedor altera |
| **Pré-pedidos** | Vendedor precisa ver novos pedidos do catálogo em tempo real |
| **Notificações** | Novas notificações devem aparecer sem refresh |
| **Config pagamentos** | Admin pode estar editando em outra aba |
| **Subscription status** | Plano do usuário pode mudar (upgrade/downgrade) |

### 2.2 PODE VIRAR get() ou CONSULTA PAGINADA

| Stream | Motivo | Ação sugerida |
|--------|--------|---------------|
| **Catálogo - produtos** | Público, 1000+ leitores = 1000+ listeners; produtos mudam pouco | limit(100) + cache; ou get() com refresh manual |
| **Catálogo - config** | 1 doc; muda raramente | Manter stream (1 doc barato) ou get() |
| **Cupons disponíveis** | Checkout; cupons mudam pouco | get() com cache 60s ou limit(30) |
| **Cupons admin** | Lista admin; não precisa realtime | get() + limit(100) |
| **Clientes** (streamClientes) | Não usado atualmente | get() quando implementado |
| **Vendas** (streamVendas) | Não usado atualmente | get() quando implementado |
| **Admin usuários** | Lista admin; não precisa realtime | get() + limit(100) |
| **Campanhas participantes** | Histórico; não precisa realtime | get() + limit(100) |
| **Fechamentos** | ~12–24 registros/ano | get() + limit(24) |
| **Canais** | Poucos por loja | get() + limit(20) |
| **Perfil cliente** | Dados mudam pouco | get() (1 doc) |
| **Master config** | Config global; muda raramente | get() com cache |
| **Notas fiscais** | Lista; não precisa realtime | get() + limit(50) |
| **Fornecedores** | Lista; não precisa realtime | get() + limit(100) |
| **Produtos draft/live** | Admin; pode ser get() | get() + limit(500) |

---

## 3. OTIMIZAÇÕES APLICADAS

### 3.1 Adição de limit() em streams que permanecem

- **Catálogo produtos:** limit(100) — evita trazer 1000+ docs em lojas grandes
- **Pré-pedidos:** já tem limit(50) ✓
- **Notificações:** já tem limit(50) ✓
- **Cupons:** limit(50) em listarDisponiveis e listarTodos
- **Campanhas participantes:** limit(100)
- **Fechamentos:** limit(24)
- **Canais:** limit(20)
- **Notas fiscais:** limit(50)
- **Fornecedores:** limit(100)
- **Admin usuários:** limit(100)
- **Estoque produtos (listener):** mantém sem limit (sync completo necessário)

### 3.2 Firestore persistence (web)

- Avaliar `enablePersistence` no web para cache local e menos leituras de rede.

---

## 4. ARQUITETURA FINAL DE LEITURA (RESUMO)

| Categoria | Estratégia | Coleções/Contextos |
|-----------|------------|---------------------|
| **Realtime obrigatório** | snapshots() com limit() | Permissões, estoque_produtos, pré-pedidos, notificações, config/payments, subscription |
| **Paginado** | get() + limit + startAfter | Catálogo produtos, cupons admin, clientes, vendas, usuários admin, notas, fornecedores |
| **Cache + get()** | get() com TTL 60–300s | Config catálogo, cupons checkout, master config |
| **Documento único** | get() ou snapshots (1 doc) | config, payments, perfil cliente, subscription |

---

## 5. CONSTANTES DE LIMITE APLICADAS

| Contexto | Limit | Motivo |
|----------|-------|--------|
| Catálogo produtos | 100 | Lojas típicas < 100 itens; evita sobrecarga |
| Cupons disponíveis | 50 | Checkout; cupons por loja geralmente poucos |
| Cupons admin | 100 | Lista admin |
| Campanhas participantes | 100 | Histórico por campanha |
| Campanhas lista | 50 | Campanhas por loja |
| Histórico sorteios | 50 | Sorteios por campanha |
| Fechamentos | 24 | ~2 anos de fechamentos |
| Canais públicos/privados | 20 | Poucos canais por loja |
| Notas fiscais | 50 | Lista recente |
| Fornecedores | 100 | Lista admin |
| Clientes | 100 | Lista (não usado ainda) |
| Vendas | 100 | Lista (não usado ainda) |
| Admin usuários | 100 | Lista usuarios |
| Pré-pedidos | 50 | Já existia |
| Notificações | 50 | Já existia |
| Produtos draft/live (admin) | 500 | Catálogo admin |

---

## 6. CUSTO ESTIMADO (leituras/dia)

**Antes (exemplo: 500 usuários, 200 lojas):**
- 500 usuários × catálogo produtos (sem limit) ≈ 500 × N docs por mudança
- Múltiplos listeners sem limit em listas grandes

**Depois (com limit + get onde possível):**
- Catálogo: 500 × 100 docs = 50k docs/dia (inicial) vs sem limit
- Listas admin: get() uma vez por tela = ~10–50 leituras por abertura
- Listeners críticos: ~6 por sessão ativa (permissoes, estoque, pré-pedidos, notif, config, subscription)

---

*Documento gerado em 12/02/2026.*
