# ADR-038 — Offline Cloud Bridge Operational Integration

## Status
Accepted

## Contexto
A Parte 1 entregou contratos cloud vendor-neutral e governança de staging, mas
sem integração operacional no provider principal.

## Decisão
Introduzir uma camada operacional cloud estritamente offline-simulation:

- `PersistentArtifactCloudOperationsService` para operações de objeto e multipart
- `PersistentArtifactCloudOperationStatus` com granularidade operacional completa
- `PersistentArtifactCloudStatusMapper` para preservar semântica do bridge
- `PersistentArtifactCloudEnvironmentGate` bloqueando staging/produção
- expansão retrocompatível do `PersistentArtifactBackendRegistry`
- API `PersistentArtifactCloudOperationsProvider` no provider principal

## Restrições
- Sem SDK cloud
- Sem HTTP/rede
- Sem `dart:io` em `lib/persistent_artifacts/cloud`
- Sem bootstrap/registro automático de bridge cloud

## Consequências
- Runtime padrão continua seguro (`unavailable` quando sem bridge)
- Fluxo operacional auditável por correlation ID
- Testabilidade elevada com fake bridge em memória

## Validação
- `dart analyze lib`
- `dart test test/persistent_artifacts/cloud`
- `dart test test/persistent_artifacts`
- `dart test`
