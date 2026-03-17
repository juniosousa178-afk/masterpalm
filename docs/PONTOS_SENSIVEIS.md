# Pontos sensíveis – onde ter cuidado ao alterar

Ao mexer nestes arquivos ou fluxos, testar bem e verificar o que mais depende deles. **Não remover nada;** só evite mudanças sem testar.

---

## Resolução de loja (store_id / lojaId)

| Onde | O que faz | Cuidado |
|------|------------|---------|
| `StoreResolverService` | Resolve loja do usuário (Firestore users, cache) | Principal fonte da verdade; mudar aqui afeta login e home |
| `LojaIdService` | Lê/grava loja da sessão (Hive) | Usado em muitas telas; não remover fallbacks |
| `StoreResolverUnified` | Resolve por contexto (URL, app, catálogo) | Usado no catálogo público; testar deep links |
| `sessao` / `config` (Hive) | store_id, store_slug | Vários serviços leem direto; ao mudar, buscar referências com "store_id" ou "sessao.get" |

**Regra:** Preferir usar sempre um único serviço (ex.: `StoreResolverService.resolve()`) em código novo em vez de ler Hive direto.

---

## Sync e boxes Hive por loja

| Onde | O que faz | Cuidado |
|------|------------|---------|
| `SyncQueueService` | Fila Hive → Firestore (retry, conectividade) | Ao alterar tipos (SyncOperationType) ou boxes, rodar testes e testar uma venda offline |
| `FullSyncService` | Firestore → Hive no login | Limpa cache de outra loja; não remover verificação de last_synced_loja_id |
| `CatalogoVendaService` | Abre várias boxes (produtos_, clientes_, vendas_) | Muitos openBox; ao mudar, garantir que lojaId está validado (StoreAccessGuard) |
| Boxes `produtos_$lojaId`, `clientes_$lojaId`, `vendas_$lojaId` | Dados locais por loja | Nunca misturar lojaId entre boxes; usar StoreAccessGuard.requireLojaId antes de abrir |

**Regra:** Ao abrir box com nome que contém lojaId, usar `StoreAccessGuard.requireLojaId` e, em debug, `auditBoxAccess` se quiser rastrear.

---

## Licença e plano

| Onde | O que faz | Cuidado |
|------|------------|---------|
| `LicenseManager.hasValidAccessFallbackLegacy` | Decide se usuário tem acesso (root, Firestore, Hive, legado) | Root emails no início; não remover sem adicionar em outro lugar |
| `PlanosService.fetchCurrentPlan` | Retorna plano atual (lifetime para root, Firestore, Hive plano_ativo) | Mesma lista de root que LicenseManager; manter alinhado |
| Box `licenca` (Hive) | currentPlanId, expiresAt, ativado, codigo (legado) | Legado ainda usado; não apagar campos sem migração |

---

## Firestore – paths críticos

| Path | Uso | Cuidado |
|------|-----|---------|
| `users/{uid}` | Plano, store_id espelho | Escrito por StoreResolver e PlanosService; regras exigem auth |
| `lojas/{lojaId}/config/payments` | Config pagamentos (catálogo) | Regra: read se resource != null; App Check pode bloquear se token inválido |
| `lojas/{lojaId}/estoque_produtos`, `estoque_clientes` | Sync e app | Muitas leituras; ao adicionar campo, verificar índices |
| `lojas/{lojaId}/estoque_vendas` | Vendas no Firestore | Sync e relatórios; não mudar estrutura sem atualizar SyncQueue e serviços |

---

## Ao alterar uma tela específica

- **Login / splash:** Verificar StoreResolver, sessão, redirect após login.
- **Home / dashboard:** LojaId, boxes vendas_/produtos_/metas_; DashboardHomeCards usa StoreAccessGuard.
- **Catálogo público:** StoreResolverUnified, config, payments; lista de produtos.
- **Vendas / PDV:** CatalogoVendaService, SyncQueueService.enqueue após gravar venda.
- **Diagnóstico:** LicenseManager, PlanosService, Hive.box<Produto>/<Cliente>/<Venda> (tipado).

---

*Atualize este doc quando descobrir “mexi aqui e quebrou ali” para ajudar nas próximas vezes.*
