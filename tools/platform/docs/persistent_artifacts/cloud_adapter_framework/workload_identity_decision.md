# Workload Identity Decision

**Status:** reviewRequired

## Avaliação conceitual

| Cenário | Abordagem recomendada | Estado |
|---------|----------------------|--------|
| Runtime VM (futuro) | Instance/workload identity do provider | reviewRequired |
| CI pipeline | OIDC federation → role temporária | reviewRequired |
| Desenvolvimento local | Perfil isolado ou emulator | reviewRequired |
| Staging | **bloqueado** até gates futuros | notApplicable agora |
| Production | **bloqueado** | notApplicable agora |

## Princípios

- Short-lived credentials apenas.
- Audience e subject restritos por ambiente.
- Tenant/account boundaries explícitos no descriptor PA.
- Nenhuma autenticação implementada nesta sprint.

## Gap

Decisão final depende de stack organizacional (AWS IAM Roles, GCP WIF, Azure Managed Identity).
