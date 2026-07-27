# Observability Policy

**Status:** draft

## Telemetry permitida

- operationId, correlationId, backendId
- provider type (enum), operation type, status
- bytesProcessed (agregado), latencyMs, retryClassification
- issue codes (sanitizados)

## Proibido em telemetry pública

- Conteúdo ou content handle
- Object key completo (usar hash prefix se necessário)
- Container/namespace sensível
- Endpoint hostname completo
- Tokens, credentials, authorization headers
- Identity claims
- Stack traces não sanitizados

## Spans (futuro)

environment → registry → capability → service → bridge → mapping

Alinhado a `ObservablePersistentArtifactProvider` — decorator opt-in.
