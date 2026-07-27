# Multipart Strategy

**Status:** draft — sem implementação.

## Limites propostos

| Parâmetro | Valor draft |
|-----------|-------------|
| Threshold mínimo | 8 MiB (ajustável pós review) |
| Part size | 5–100 MiB |
| Max parts | 10 000 (S3 limit) |
| Checksum por part | obrigatório no adapter |

## Lifecycle

1. beginMultipart → uploadId opaco
2. uploadPart → partNumber sequencial, sem overlap
3. complete → validar parts + digests
4. abort → cleanup provider-side (futuro)

## Orphaned uploads

- Cleanup job futuro; não automático no adapter v1.

## Observability

- Correlation ID por multipart; sem conteúdo em logs.

`multipartStrategyApproved` permanece `false`.
