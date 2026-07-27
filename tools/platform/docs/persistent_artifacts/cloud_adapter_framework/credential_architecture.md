# Credential Architecture

**Status:** draft — sem segredos reais, sem implementação.

## Princípios

1. **Credenciais de longa duração proibidas** por padrão (access keys estáticas).
2. **Workload identity preferencial** para runtime (VM, CI, futuro staging/prod).
3. **Credenciais temporárias** com TTL curto e rotação automática.
4. **Separação por ambiente** — identidades distintas; staging/production bloqueados até gates futuros.
5. **Referências estruturais apenas** — `PersistentArtifactCloudAuthenticationReference` sem resolução.

## Modelo conceitual

```
PersistentArtifactCloudAuthenticationReference (declarativo)
        ↓
Credential Resolver (futuro, fora do core PA)
        ↓
Short-lived session / federation token (runtime, nunca serializado)
        ↓
Adapter bridge (única camada com I/O)
```

## Cobertura

| Tópico | Decisão draft |
|--------|---------------|
| Identity federation | Preferir OIDC/workload identity do cloud provider |
| Rotação | Automática via provider; sem keys em código |
| Audience / scope | Mínimo por operação (ver least_privilege_policy.md) |
| Secret storage | Vault/KMS provider-side; não em PA snapshots |
| Redaction | Nenhum token em logs/telemetry |
| Revogação | Disable identity + unregister backend |
| Break-glass | Processo manual documentado; não automatizado |
| Desenvolvimento local | Profile isolado ou emulator com credenciais efêmeras |
| CI | OIDC federation para pipeline dedicado |

## Proibido nesta sprint

accessKey, secretKey, sessionToken, JWT, certificados reais, credential loader em `lib/`.
