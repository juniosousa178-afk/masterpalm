# Cloud Adapter Framework — Part 2 Release Checklist

## Pré-release
- [ ] Guardian simulado executado em working tree
- [ ] Sem alterações em produção/staging para cloud I/O
- [ ] Sem import de SDK/HTTP/dart:io na lib cloud operacional

## Validação técnica
- [ ] `dart format lib test docs`
- [ ] `dart analyze lib`
- [ ] `dart test test/persistent_artifacts/cloud`
- [ ] `dart test test/persistent_artifacts`
- [ ] `dart test`

## Regressão funcional
- [ ] baseline cloud Part 1 preservado
- [ ] fallback `unavailable` sem bridge validado
- [ ] gate de staging/produção bloqueando corretamente
- [ ] replay operacional 100 ciclos aprovado

## Governança
- [ ] goldens operacionais presentes e estáveis
- [ ] ADR-038 e AR-024 publicados
- [ ] nenhum commit/push/deploy sem autorização explícita
