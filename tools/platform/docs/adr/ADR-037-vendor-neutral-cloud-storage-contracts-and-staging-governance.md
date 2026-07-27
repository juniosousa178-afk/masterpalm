# ADR-037 — Vendor-Neutral Cloud Storage Contracts and Staging Governance

## Status
Accepted (Part 1)

## Context
O domínio de Persistent Artifacts precisava de contratos cloud agnósticos de fornecedor para manter extensibilidade sem acoplamento a SDK.

## Decision
- Introduzir enums/modelos cloud com serialização determinística e `toComparableJson`.
- Definir `PersistentArtifactCloudBackendBridge` como contrato de operações cloud.
- Estender `PersistentArtifactBackendRegistration` com `cloudDescriptor` e `cloudBridge` opcionais.
- Adicionar avaliador puro de governança de staging.
- Bloquear produção por padrão (`productionEligible=false`) nesta fase.
- Bloquear material sensível (accessKey/secretKey/token/password/presigned/JWT) nos validadores.

## Consequences
- Evolução segura para adapters reais em parte futura.
- Sem mudança em bootstrap, rede, SDK cloud ou produção.
- Testabilidade elevada via fake bridge em `test/`.

## Constraints
- Sem `dart:io`/HTTP na camada cloud.
- Sem auto-registro de bridge cloud.
- Retrocompatibilidade mantida.
