# Persistent Artifact Infrastructure

## 1. Objetivo
Especificar a infraestrutura de artefatos persistentes para avaliação, publicação, retenção e exclusão declarativa.

## 2. Escopo
Cobertura para `tools/platform/lib/persistent_artifacts` e `lib/models/persistent_artifacts`.

## 3. Fora de escopo
Sem storage físico, sem adapters de rede e sem autorização de release.

## 4. Princípios
Determinismo, idempotência, observabilidade, e limites operacionais explícitos.

## 5. Glossário
Snapshot, material coletado, referência de fonte, política, tombstone e operação.

## 6. Arquitetura em camadas
Provider -> Resolver -> Collector -> Engine -> Snapshot Builder -> Store.

## 7. Modelo de snapshot
`PersistentArtifactInfrastructureSnapshot` é o artefato central comparável e serializável.

## 8. Identidade canônica
Fingerprint canônico e snapshotId determinístico com escopo de projeto/release.

## 9. Serialização
JSON comparável, roundtrip estável e sem campos secretos.

## 10. Source resolution
Somente `latest/load`; nunca `evaluate/publish` no boundary de resolução.

## 11. Coleta de material
Coleta subjects, policies e source references para avaliação operacional.

## 12. Avaliação operacional
Engine produz `PersistentArtifactOperationResult` determinístico por request.

## 13. Avaliação de integridade
Coberta via path operacional declarativo sem dependência de backend físico.

## 14. Avaliação de storage policy
Validações estruturais de política com baseline sem IO físico.

## 15. Avaliação de retenção
Retenção operacional sem writes externos e com metadata auditável.

## 16. Avaliação de replicação
Regras declarativas de réplica sem adapters de replicação real.

## 17. Avaliação de disponibilidade
Disponibilidade baseada em resultado operacional e consistência de snapshot.

## 18. Avaliação de lifecycle
Lifecycle derivado do contexto de operação e estado de publicação.

## 19. Avaliação de publicação
Publicação persiste apenas em store in-memory sob testes.

## 20. Avaliação de deleção
`legalHold=true` bloqueia deleção mesmo com `force=true`.

## 21. Tombstone
Construção de tombstone é declarativa e separada da deleção física.

## 22. Store
Store in-memory com idempotência e detecção de conflito por fingerprint.

## 23. Segurança estática
Sem `HttpClient`, sem `Socket.connect`, sem `Process.run` no domínio.

## 24. Golden files
Goldens normativos vivem em `test/goldens/persistent_artifacts/`.

## 25. Política de atualização de goldens
Sem auto-update em teste. Atualização consciente via revisão humana e commit explícito.

## 26. Replay e determinismo
Replay com múltiplos ciclos mantém fingerprint e snapshotId para mesmas entradas.

## 27. Stress e performance
Stress inclui 5000 snapshots; performance usa limites amplos com `Stopwatch`.

## 28. Integração com módulos
Compatível com report engine, history mapper, dashboard e observability.

## 29. Governança de mudanças
Sem alteração de wireNames e sem modificar governança de release neste sprint.

## 30. Critérios de aceite do Sprint 05.3 Part 3
Hardening completo, testes novos >=120, analyze limpo e suíte específica passando.

## Procedimento consciente para atualizar goldens
1. Executar suíte de hardening localmente e validar divergências.
2. Revisar diffs dos JSONs com foco em keys normativas.
3. Atualizar manualmente os arquivos em `test/goldens/persistent_artifacts/`.
4. Reexecutar `dart test test/persistent_artifacts/persistent_artifact_golden_test.dart`.
5. Registrar justificativa no changelog/review do PR.
