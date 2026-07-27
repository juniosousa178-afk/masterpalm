# Network Boundary Design

**Status:** draft

## Recomendação

| Ambiente futuro | Endpoint | Egress |
|-----------------|----------|--------|
| Integration test | Private endpoint ou emulator local | Allowlist restrita |
| Development | Emulator local preferencial | Sem acesso production |
| Staging | **bloqueado** | — |
| Production | **bloqueado** | — |

## Controles

- TLS obrigatório (ver `endpoint_and_tls_policy.md`).
- DNS policy: resolver controlado; sem override silencioso.
- Metadata service: acesso negado exceto quando identity exigir (documentar por provider).
- Firewall/allowlist por região.
- Sem conexão nesta sprint.
