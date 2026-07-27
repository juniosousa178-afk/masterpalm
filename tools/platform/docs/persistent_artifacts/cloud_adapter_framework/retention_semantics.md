# Retention Semantics

**Status:** draft — não assumir equivalência entre fornecedores.

## Conceitos

| Conceito | Mapeamento PA | Notas |
|----------|---------------|-------|
| Retention period | Descriptor + governance evaluator | Bloqueia delete até expirar |
| Governance mode | Provider-specific | evidenceMissing até PoC |
| Minimum retention | `retentionSemanticsApproved` false | |

## Comportamento esperado do adapter

- Delete durante retention → `stagingBlocked` ou status específico de retention lock.
- PA retention evaluator **não** chama delete remoto.

## Gap

Validação empírica com bucket em modo Object Lock / equivalente GCS/Azure.
