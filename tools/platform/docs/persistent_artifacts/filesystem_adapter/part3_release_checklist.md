# Part 3 Release Checklist

## Build and Analysis
- [ ] `dart format lib test docs`
- [ ] `dart analyze lib`
- [ ] `dart test test/persistent_artifacts`
- [ ] `dart test`

## Hardening Controls
- [ ] Core sem import `SecureFilesystem*` em `persistent_artifact_operational_core.dart`
- [ ] Bridge vendor-neutral registrada no backend registration
- [ ] Produção bloqueada (`environmentBlocked`)
- [ ] Staging bloqueado por padrão
- [ ] Bootstrap sem auto-registro de backend

## Compatibility
- [ ] Goldens legados inalterados
- [ ] Novos goldens em `test/goldens/persistent_artifacts/integration/`
- [ ] Entrypoint core sem exports vendor-specific
- [ ] Entrypoint filesystem exporta composição local-reference
