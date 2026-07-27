# Least Privilege Policy

**Status:** draft — aguarda IAM review manual.

## Papéis propostos

| Papel | Put | Get | Head | List | Delete | Copy | Multipart | Version list | Retention | Legal hold |
|-------|-----|-----|------|------|--------|------|-----------|--------------|-----------|------------|
| object-writer | ✓ | — | ✓ | — | — | — | ✓ | — | — | — |
| object-reader | — | ✓ | ✓ | ✓ | — | — | — | — | — | — |
| metadata-reader | — | — | ✓ | ✓ | — | — | — | — | — | — |
| manifest-writer | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — | — | — |
| manifest-reader | — | ✓ | ✓ | ✓ | — | — | — | — | — | — |
| quarantine-operator | — | ✓ | ✓ | ✓ | — | — | — | — | — | — |
| deletion-operator | — | — | ✓ | ✓ | ✓ | — | — | — | — | — |
| recovery-operator | — | ✓ | ✓ | ✓ | — | ✓ | — | ✓ | — | — |
| audit-reader | — | — | ✓ | ✓ | — | — | — | — | — | — |

Nenhum papel recebe `*` ou admin no bucket/container.

## Separação

- Identidade de **integração test** ≠ identidade futura de staging ≠ produção (bloqueadas).
- PA runtime usa apenas referências; IAM bindings são infraestrutura externa.

## Gap

Políticas IAM concretas dependem de fornecedor selecionado e aprovação manual.
