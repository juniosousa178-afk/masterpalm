# Cloud Adapter Framework (Part 1)

## 1. Objetivo
Contratos vendor-neutral para armazenamento cloud em Persistent Artifacts.

## 2. Escopo
Parte 1 cobre apenas modelos, validação, bridge e governança de staging.

## 3. Fora de Escopo
Sem SDK cloud, sem HTTP, sem IO de rede e sem habilitação de produção.

## 4. Princípios
Declarativo, determinístico, seguro por padrão e retrocompatível.

## 5. Estrutura de Pastas
`lib/models/persistent_artifacts/cloud` e `lib/persistent_artifacts/cloud`.

## 6. Enumerações
Todas possuem `wireName` e `fromWireName` com `FormatException`.

## 7. Modelos
Todos implementam `toJson`, `fromJson`, `toComparableJson`, `copyWith`.

## 8. Comparabilidade
`toComparableJson` normaliza ordem e remove variabilidade temporal.

## 9. Fingerprint
Hash SHA-256 derivado de JSON comparável normalizado.

## 10. Bridge Cloud
Interface de contrato para operações cloud sem binding de fornecedor.

## 11. Capabilities
Matriz explícita de capabilities de bridge para introspecção.

## 12. Registro de Backend
`PersistentArtifactBackendRegistration` ganhou campos cloud opcionais.

## 13. Registry Extension
`cloudBridgeOf(backendId)` expõe bridge cloud sem auto-registro.

## 14. Governança de Staging
Avaliador puro decide prontidão para staging.

## 15. Critérios de Promoção
Durabilidade, replicação, consistência, criptografia e metadados.

## 16. Segurança
Bloqueio de material sensível: accessKey, secretKey, token, password, URL assinada, JWT.

## 17. Defaults de Elegibilidade
`productionEligible=false`, `stagingEligible=false`, `approved=false`.

## 18. Restrições Técnicas
Sem `dart:io`, sem rede, sem bootstrap e sem side effects externos.

## 19. Determinismo
Serialização comparável e fingerprint estáveis em execuções repetidas.

## 20. Boundary Rules
Validação de tamanhos, retries, timeout, ids e faixas numéricas.

## 21. Status de Operações
Modelo cobre fluxo put/get/head/list/delete/copy/multipart.

## 22. Multipart
Início, upload de parte, finalização e abort com status explícito.

## 23. Retry/Timeout
Políticas explícitas por request para governança e auditabilidade.

## 24. Issue Model
Issue tipado com código, severidade, path e metadados.

## 25. Testes
Suíte dedicada cloud em `test/persistent_artifacts/cloud`.

## 26. Hardening
Teste guarda-chuva valida invariantes de segurança e elegibilidade.

## 27. Retrocompatibilidade
Sem quebra de APIs existentes; campos cloud são opcionais.

## 28. Evolução
Parte 2 deverá introduzir adaptadores concretos por fornecedor.

## 29. Riscos
Risco principal: tentativa de injetar segredo em metadados.

## 30. Checklist de Liberação
Executar analyze/testes, validar baseline e manter produção bloqueada.

## 31. Parte 2 — Operacional
Parte 2 adiciona integração operacional offline para cloud bridge com gate de
ambiente, classificação de retry, mapeamento de status sem perda semântica e
API de provider dedicada.

## 32. Status Operacionais
`PersistentArtifactCloudOperationStatus` passa a cobrir estados de sucesso,
idempotência, conflito, indisponibilidade, autenticação, throttle, timeout,
precondição, multipart e bloqueios de governança.

## 33. Gate de Ambiente
`offlineSimulation` é permitido apenas em `test`, `development` e
`localReference`; `staging` e `production` permanecem bloqueados por padrão.
`contractOnly` não executa I/O.

## 34. Serviço de Operações Cloud
`PersistentArtifactCloudOperationsService` executa:
`put/get/head/exists/list/delete/copy` e ciclo multipart
`begin/upload/complete/abort`, com correlation ID e fallback `unavailable`
quando não houver bridge registrada.

## 35. Registry Expandido
`PersistentArtifactBackendRegistry` expõe consultas cloud retrocompatíveis:
`cloudRegistrationOf`, `resolveCloudBackend*`, `queryCloudCapabilities` e
`evaluateCloudEnvironment`.

## 36. Provider Operacional
`PlatformPersistentArtifactProvider` implementa
`PersistentArtifactCloudOperationsProvider` e delega ao serviço cloud sem
disparar I/O durante `evaluate/evaluateAndPublish`.

## 37. Testes Operacionais
A suíte operacional vive em `test/persistent_artifacts/cloud/operational`,
inclui replay de 100 ciclos, auditoria de mapeamento, hardening e goldens
fixos (sem auto-update).

## 38. Parte 3 — Hardening Offline
Composition root de referência em `test/support/`:
`PersistentArtifactOfflineCloudReferenceComposition`.

## 39. Runtime Lifecycle
Create, register, use, unregister, dispose idempotente; dispose não executa
delete remoto nem limpa storage normativo.

## 40. Environment Gate Hardening
`contractOnly`: permitido em test/development/localReference para validação;
bloqueado em staging/production. `offlineSimulation`: permitido em não-prod;
bloqueado em staging/production.

## 41. Replay Cross-Layer
100 ciclos request→JSON→service→provider com IDs e status estáveis.

## 42. Goldens Finais
30 snapshots em `test/goldens/persistent_artifacts/cloud_hardening/`.

## 43. Real-Adapter Admission Gate
`PersistentArtifactRealCloudAdapterAdmissionCriteria` (31 critérios),
`PersistentArtifactRealCloudAdapterAdmissionDecision`,
`PersistentArtifactRealCloudAdapterAdmissionEvaluator`.

## 44. Prototype Admission
`approvedForPrototype` exige critérios completos + `manualApprovalReference`;
não habilita staging, produção, SDK ou release.

## 45. Suíte Hardening
`test/persistent_artifacts/cloud/hardening/` — composition, admission, replay,
goldens, audit, observability, property/mutation, stress, security.

## 46. Fronteiras conceituais
Success offline ≠ persistência remota; capability declarada ≠ suporte real;
cloud success ≠ autorização de release.

## 47. Roadmap
Próximo passo: sprint de protótipo de adapter real somente após gate completo
e aprovação manual explícita — fora do escopo desta entrega.

## 48. Sprint 05.3.2 Closure Status

| Verificação | Resultado |
|-------------|-----------|
| `dart analyze lib` | limpo |
| Testes cloud | 366+ |
| Testes PA | 1356+ |
| Suíte total | 3385+ |
| Guardian targeted files | 772 |
| Guardian targeted unresolved | 0 |
| Guardian targeted fingerprint | `7ca8d89e…3666` (estável 5×) |
| Repository-wide findings | atribuídos fora de platform |
| Admission status | `notEvaluated` |
| realAdapterWorkAuthorized | **false** |
| Staging / production | bloqueados |

Documentos: `guardian_scope_attribution.md`, `real_adapter_admission_evidence_matrix.md`, `closure_release_checklist.md`.

## 49. Sprint 05.3.3 Parte 1 — Design Admission

Pacote de design em `real_adapter_design_review_package.md` (28 documentos).

- Recomendação draft: AWS S3 como referência (não aprovada).
- `targetProviderSelected=false`, `approvedForPrototype=false`, `realAdapterWorkAuthorized=false`.
- ADR-040 Proposed, AR-026.
