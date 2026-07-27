# Rollout — stockRevision (R8.4.1)

## Classificação de versão mínima

- **Cliente novo:** `StockRevisionOperationGate` + `kMinStockRevisionClientVersion = 284` (compilado).
- **Cliente antigo real:** não conhece o gate — barreira final = **Firestore Rules**.
- **Remoto:** `AppUpdateService` / `SiteConfigService.apkVersion` é informativo (semver APK), **não** bloqueia operações de estoque.
- **Classificação:** `CLIENT_CONSTANT_ONLY_NOT_ENFORCED` para clientes já instalados; `REMOTE_MINIMUM_VERSION_ENFORCEMENT_VALIDATED` **não** aplicável sem Remote Config dedicado.

## Estratégias avaliadas

| # | Estratégia | Prós | Contras | Escolha |
|---|------------|------|---------|---------|
| 1 | App primeiro | Zero erro em clientes antigos durante janela | Legado continua escrevendo grade sem revision | Rejeitada sem janela curta |
| 2 | Rules primeiro | Bloqueio imediato de overwrite stale | Clientes antigos recebem PERMISSION_DENIED | **Complementar** após app compatível em lojas críticas |
| 3 | Janela manutenção | Controle operacional | Downtime de vendas | Recomendada para lojas com histórico de reversão |
| 4 | Backend compatível | Migração suave | Escopo alto (callable) | Futura se coexistência prolongada |

## Ordem recomendada (não executar sem autorização)

1. Publicar **app** com gate + contrato revision em lojas piloto.
2. Validar LEG-A + E1–E8 em piloto (24–48 h).
3. Publicar **Rules** com enforcement `estoque_produtos`.
4. Ativar comunicação de atualização obrigatória (APK / web cache bust).
5. Monitorar: `permission-denied` em estoque, `stockSyncState=conflict`, vendas sem baixa.

## Plataformas

| Plataforma | Mecanismo | Offline |
|------------|-----------|---------|
| Android APK | SiteConfig + gate local | Gate local; Rules na reconexão |
| Web | Deploy hosting + cache | Mesmo gate; Rules na sync |
| Desktop | Build distribuído manual | Idem Android |

## Rollback

1. Reverter Rules para `allow read, write: if belongsToStore` (somente emergência).
2. Manter app novo (compatível com rules relaxadas).
3. Não reverter dados — usar runbook `stock-conflict-investigation.md`.

## Monitoramento pós-deploy (futuro)

- Taxa de `StockRevisionUpdateRequiredException` / UPDATE_REQUIRED
- Conflitos `stockSyncState=conflict`
- Vendas com estoque não baixado (RCA retorno tardio)
