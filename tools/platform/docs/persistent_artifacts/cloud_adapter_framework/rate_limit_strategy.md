# Rate Limit Strategy

**Status:** draft

## Abordagem

- Mapear throttling do provider → `PersistentArtifactCloudOperationStatus.throttled`.
- Classifier PA: retryable conforme policy.
- Adapter: **não** implementar retry loop no core; respeitar execution plan.
- Concurrency caps por backendId em ambiente de teste.
- Exponential backoff documentado para adapter layer futuro.

## Limites draft

| Recurso | Limite integração |
|---------|-------------------|
| PUT/s | 50 |
| GET/s | 200 |
| LIST/s | 20 |
| Multipart parts/s | 100 |

Valores ajustáveis pós PoC.
