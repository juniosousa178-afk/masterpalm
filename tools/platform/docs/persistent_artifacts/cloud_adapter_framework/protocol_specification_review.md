# Protocol Specification Review

**Candidato de referência:** AWS S3 API (REST, SigV4) — **reviewRequired**, sem implementação.

## Escopo

Revisão documental para mapeamento futuro aos contratos `PersistentArtifactCloud*`. Nenhum request signing, XML ou cliente implementado nesta sprint.

## Protocolo de objetos

| Operação PA | Mapeamento S3 conceitual | Status documental |
|-------------|--------------------------|-------------------|
| putObject | PUT Object | reviewRequired |
| getObject | GET Object | reviewRequired |
| headObject | HEAD Object | reviewRequired |
| listObjects | ListObjectsV2 | reviewRequired |
| deleteObject | DELETE Object | reviewRequired |
| copyObject | CopyObject | reviewRequired |
| beginMultipart | CreateMultipartUpload | reviewRequired |
| uploadPart | UploadPart | reviewRequired |
| completeMultipart | CompleteMultipartUpload | reviewRequired |
| abortMultipart | AbortMultipartUpload | reviewRequired |

## Autenticação e assinatura

- Workload identity / IAM role preferencial (ver `credential_architecture.md`).
- SigV4 para requests REST — **não implementado**.
- Bearer/session tokens via STS — **não implementado**.

## Metadata e conditional operations

- ETag como referência opaca de provider (`PersistentArtifactCloudObjectReference.etag` ≠ digest canônico PA).
- Conditional headers (`If-Match`, `If-None-Match`) — mapear para `preconditionFailed` / `versionConflict`.

## Paginação

- Continuation token opaco — alinhado a `PersistentArtifactCloudObjectListResult.nextToken`.

## Error model

- Mapear HTTP 403/404/409/412/429/503 para status PA (`authenticationRejected`, `notFound`, `conflict`, `throttled`, etc.).
- Classifier PA permanece puro; adapter traduz erros do fornecedor.

## Throttling e retry

- Ver `retry_and_timeout_semantics.md`.
- Adapter futuro não deve executar retry automático fora do plano PA.

## Consistência

- Read-after-write regional documentado como `partiallySupported` até validação empírica.

## Lacunas

- Equivalência exata Object Lock / legal hold vs contratos PA.
- Comportamento de listagem eventual em buckets versionados.
