# Release Checklist — Secure Filesystem Adapter

- [ ] `dart format lib test docs`
- [ ] `dart analyze lib`
- [ ] `dart test test/persistent_artifacts`
- [ ] `dart test`
- [ ] confirmar backend registry vazio por padrão
- [ ] confirmar ausência de auto-register no bootstrap
- [ ] validar bloqueio de traversal e UNC
- [ ] validar confinamento de root e symlink fail-closed
- [ ] validar `maximumContentSizeBytes`
- [ ] validar escrita atômica em `temp/`
- [ ] validar ausência de path absoluto em mensagens públicas
- [ ] revisar ADR-034 e AR-020 aprovados
