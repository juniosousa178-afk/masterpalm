# Data Residency Decision

**Status:** reviewRequired — decisão organizacional ausente.

## Classificação proposta (draft)

- Artefatos PA: metadados de release, evidências, manifests — classificação **interna**.
- Conteúdo binário: mesmo nível ou superior conforme política org.

## Regiões

- **Permitidas:** evidenceMissing — requer decisão Compliance.
- **Replicação cross-region:** apenas se política org aprovar.
- **Logs/telemetry:** mesma residência que dados ou região agregada aprovada.

## Transferência internacional

- Não assumir permissão; requer review legal.

## Impacto PA

- `PersistentArtifactCloudRegionReference` permanece declarativo.
- `dataResidencyApproved` permanece `false`.
