# Encryption and Key Ownership

**Status:** draft

## Opções avaliadas

| Modo | Descrição | Recomendação draft |
|------|-----------|-------------------|
| Provider-managed SSE | Chave gerida pelo provider | Aceitável para protótipo |
| Customer-managed keys (CMK) | KMS do cliente | Preferido para produção futura |
| Customer-supplied keys (SSE-C) | Chave fornecida por request | notApplicable inicialmente |

## Ownership

- Chaves de criptografia em repouso: ownership do cliente via KMS quando CMK.
- Chaves em trânsito: TLS controlado pela policy de endpoint.
- Rotação: automática via KMS; documentar procedimento.
- Revogação: disable key → operações falham com `authenticationUnavailable` / `permissionDenied`.

## PA mapping

- `PersistentArtifactCloudEncryptionCapability` permanece declarativo.
- Nenhuma key reference real nesta sprint.
