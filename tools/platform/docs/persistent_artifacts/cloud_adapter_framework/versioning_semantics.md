# Versioning Semantics

**Status:** draft

## Conceitos

- `PersistentArtifactCloudObjectVersionReference` ≠ artifact version PA.
- Provider version ID opaco; não confundir com digest canônico.
- Conditional writes usam version/ETag do provider.

## Operações

| Cenário | Status PA |
|---------|-----------|
| Put com version match | success / idempotent |
| Put com version mismatch | versionConflict |
| List versions | paginação opaca |

`versioningSemanticsApproved` permanece `false`.
