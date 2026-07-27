# Retry and Timeout Semantics

**Status:** draft — alinhado a `PersistentArtifactCloudRetryClassifier` (puro, sem execução).

## Retryable (classifier PA)

- throttled, timeout, endpointUnavailable, regionUnavailable, unavailable, interrupted (policy-dependent).

## Not retryable

- invalid, permissionDenied, conflict, preconditionFailed, versionConflict, stagingBlocked, corrupted.

## Execution plan

- `PersistentArtifactCloudExecutionPlan`: uma execução nesta sprint; sem Timer.
- Adapter futuro pode consultar plano; não implementar loop automático no core.

## Timeout

- connect/read/write via `PersistentArtifactCloudTimeoutPolicy` — declarativo.
- Timeout policy **não cancela** operação nesta sprint.

## Backoff

- Documentar exponential backoff + jitter para adapter futuro.
- maximumAttempts coerente com retry policy do descriptor.
