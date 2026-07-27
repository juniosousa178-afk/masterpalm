# Part 1 Release Checklist

- [ ] `dart format lib test docs`
- [ ] `dart analyze lib`
- [ ] `dart test test/persistent_artifacts/cloud`
- [ ] `dart test test/persistent_artifacts`
- [ ] `dart test`
- [ ] Confirmar `productionEligible=false` por padrão
- [ ] Confirmar `stagingEligible=false` por padrão
- [ ] Confirmar `approved=false` por padrão em decisão de staging
- [ ] Confirmar zero uso de SDK cloud / HTTP / `dart:io` na cloud lib
- [ ] Confirmar fake bridge somente em `test/`
- [ ] Validar retrocompatibilidade do registry
- [ ] Validar fingerprint determinístico
- [ ] Validar bloqueio de segredos em validadores
- [ ] Registrar contagem de testes antes/depois
