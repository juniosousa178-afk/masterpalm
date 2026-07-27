# ADR-035 — Controlled Filesystem Backend Integration

## Status
Accepted

## Contexto
O adapter de filesystem já existia com stores e factory, mas faltava um contrato público controlado para operações físicas e registro por capacidade.

## Decisão
- Separar entrypoint concreto em `masterpalm_platform_filesystem.dart`.
- Manter `masterpalm_platform.dart` apenas com tipos vendor-neutral de integração backend.
- Introduzir `PersistentArtifactBackendRegistry` com registro idempotente e gate de ambiente.
- Exigir `backendId` explícito em todas as operações físicas.
- Implementar superfície física no `PlatformPersistentArtifactProvider`.

## Consequências
- Core permanece sem acoplamento direto ao adapter concreto.
- Integração local referência fica disponível por registro explícito.
- Contexto de produção bloqueia backend não elegível.
- Bootstrap padrão continua vazio (sem auto-registro).
