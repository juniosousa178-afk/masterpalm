# ADR-036 — Non-production Filesystem Composition and Promotion Boundaries

## Status
Accepted

## Context
Sprint 05.3.1 Part 3 exige endurecimento da integração de filesystem sem abrir caminho para uso implícito em produção.

## Decision
- Introduzir bridge vendor-neutral (`PersistentArtifactPhysicalBackendBridge`).
- Remover dependências `SecureFilesystem*` do core operacional.
- Definir gate de ambiente com produção bloqueada sempre.
- Bloquear staging por padrão.
- Consolidar composição local-reference em entrypoint filesystem.
- Manter critérios de promoção declarativos.

## Consequences
- Integração física fica auditável e isolada por bridge.
- Backends não registrados/desabilitados têm status explícitos.
- Observabilidade ganha correlação consistente para operações físicas.
- Bootstrap global permanece sem auto-registro.
