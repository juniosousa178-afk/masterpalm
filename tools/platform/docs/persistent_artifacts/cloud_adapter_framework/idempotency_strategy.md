# Idempotency Strategy

**Status:** draft

## Por operação

| Operação | Chave de idempotência | Conflito |
|----------|----------------------|----------|
| put | object key + conditional version/ETag | alreadyExists / conflict |
| conditional put | If-None-Match / If-Match | preconditionFailed |
| multipart begin | object key + client token (futuro) | conflict |
| upload part | uploadId + partNumber | duplicate part |
| complete | uploadId + part ETags | multipartIncomplete |
| abort | uploadId | idempotent abort |
| copy | source + dest + conditions | destination conflict |
| delete | object key + version | notFound / versionConflict |

## Distinções PA

- duplicate request → idempotent success quando seguro.
- ETag provider ≠ SHA-256 canônico PA.
- Operation IDs opacos em request; não reutilizar como digest.
