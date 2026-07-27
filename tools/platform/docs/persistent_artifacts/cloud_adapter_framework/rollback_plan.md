# Rollback Plan

**Status:** draft

## Gatilhos

- Falha crítica em adapter após protótipo futuro.
- Comprometimento de credencial.
- Regressão em testes de integração bloqueante.

## Procedimento

1. `unregister` backend cloud no registry.
2. Desabilitar feature flag / composition root (se existir).
3. Reverter deploy do módulo adapter (não do core PA).
4. Revogar identities temporárias.
5. Preservar logs e evidence para post-mortem.
6. Confirmar bootstrap sem cloud backend restaurado.

## PA-specific

- Rollback **não** altera snapshots normativos existentes.
- Cryptographic Trust inalterado.

`rollbackPlanApproved` permanece `false`.
