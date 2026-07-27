# Secret Redaction Policy

**Status:** draft

## Regras

1. Nenhum segredo em `toJson` / `toComparableJson` de resultados PA.
2. Issues sanitizadas — sem mensagens de exceção interna com credenciais.
3. Logs: redact patterns para `Authorization`, `X-Amz-`, `sig=`, `token=`.
4. Telemetry: mesmas regras de observability_policy.md.
5. Snapshots PA: sem credential resolution output.

## Validação

- Static security review em cada sprint de implementação.
- Mutation tests: token nunca aparece em serialização.

`secretRedactionApproved` permanece `false` até security sign-off.
