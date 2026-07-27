# Secure Filesystem Reference Adapter

## 1. Objetivo
Adapter de filesystem seguro para `Persistent Artifacts`, com isolamento de root e armazenamento enderecado por digest.

## 2. Escopo
Implementa stores de conteúdo e manifesto, resolução de localização, leitura/escrita e deleção física com quarentena opcional.

## 3. Fora de escopo
Não altera bootstrap, core de plataforma, registro automático, fingerprints legados ou wire names existentes.

## 4. Contratos atendidos
`PersistentArtifactContentStore`, `PersistentArtifactManifestStore`, `PersistentArtifactLocationResolver`, `PersistentArtifactContentReader`, `PersistentArtifactContentWriter`, `PersistentArtifactPhysicalDeletionProvider`.

## 5. Diretório do adapter
`lib/persistent_artifacts/adapters/filesystem/`.

## 6. Requisitos de runtime
`dart:io`, `package:crypto`, `package:path`.

## 7. Configuração mínima
`backendId`, `rootDirectory` absoluto e `maximumContentSizeBytes`.

## 8. Validação de configuração
Rejeita raiz relativa, raiz de sistema e home sem opt-in explícito.

## 9. Endereçamento de conteúdo
`content/<namespace>/<prefix>/<fingerprint>`.

## 10. Endereçamento de manifesto
`manifests/<namespace>/<artifactId>/<versionId>.json`.

## 11. Digest
SHA-256 via `package:crypto`.

## 12. Idempotência
Mesmo digest em mesmo objeto retorna sucesso idempotente.

## 13. Conflitos
Digest divergente para payload já existente retorna conflito.

## 14. Escrita atômica
Arquivo temporário em `temp/` com rename para destino final.

## 15. Verificação pós-escrita
Opcional via `verifyDigestAfterWrite`.

## 16. Limite de tamanho
`maximumContentSizeBytes` com rejeição explícita.

## 17. Proteção de traversal
Bloqueia `..`, formas percent-encoded, paths absolutos e UNC.

## 18. Caracteres proibidos
Bloqueia null byte e caracteres de controle.

## 19. Confinamento de root
Normalização de path e validação de prefixo de root.

## 20. Symlink policy
Fail-closed: rejeita caminhos com `FileSystemEntityType.link`.

## 21. Privacidade em mensagens
Sem vazamento de path absoluto em referências públicas.

## 22. Logging seguro
Sem conteúdo de payload em logs ou mensagens de exceção.

## 23. Quarentena
Delete move para `quarantine/` quando habilitado.

## 24. Delete físico
Quando quarentena desabilitada, faz delete simples (sem secure erase).

## 25. Inspeção de recuperação
`SecureFilesystemRecoveryInspector` só atua com opt-in.

## 26. Registro manual
Factory não registra backend automaticamente.

## 27. Integração com registry
Consumidor registra manualmente no `PersistentArtifactBackendRegistry`.

## 28. Testes de segurança
Cobre traversal, malformed input, UNC e isolamento de bootstrap.

## 29. Testes de carga
Stress com 5000 objetos e 1000 manifests.

## 30. Checklist de release
Ver `release_checklist.md` no mesmo diretório.

## 31. Entrypoint isolado
Tipos concretos de filesystem são exportados somente por `lib/masterpalm_platform_filesystem.dart`.

## 32. Integração backend controlada
Registro ocorre por `SecureFilesystemBackendFactory.createRegistration` e `registerInto`.

## 33. Classificação de ambiente
Backend filesystem é classificado como `localReference` e `productionEligible=false`.

## 34. Operações físicas no provider
`PlatformPersistentArtifactProvider` expõe operações físicas com `backendId` explícito.

## 35. Sem auto-bootstrap
Nenhuma mudança em bootstrap global para auto-registro de backend.

## 36. Telemetria sanitizada
Observable provider delega operações físicas sem incluir path absoluto ou payload em metadata pública.

## 37. Checklist de integração controlada
Ver `integration_release_checklist.md` para validação de release desta integração.

## 38. Bridge vendor-neutral obrigatória
Operações físicas do provider devem usar `PersistentArtifactPhysicalBackendBridge`, sem dependência de tipos concretos SecureFilesystem no core.

## 39. Core sem imports de adapter
`persistent_artifact_operational_core.dart` não pode importar `SecureFilesystem*`.

## 40. Registro com bridge opcional
`PersistentArtifactBackendRegistration` aceita `bridge` opcional para preservar compatibilidade de backends legados.

## 41. Registry com bridgeOf
`PersistentArtifactBackendRegistry` expõe `bridgeOf(backendId)` para resolução explícita por backend.

## 42. Registry com evaluateEnvironment
`PersistentArtifactBackendRegistry.evaluateEnvironment` aplica gate declarativo por ambiente de runtime.

## 43. Gate de ambiente explícito
`PersistentArtifactEnvironmentGate` define decisões com `allowed/blocked` e razão auditável.

## 44. Produção bloqueada sempre
Fluxos físicos em produção retornam `environmentBlocked` e não executam I/O.

## 45. Staging bloqueado por padrão
Staging só é permitido via configuração explícita do gate.

## 46. Test/dev/local-reference permitidos
Execução local controlada mantém capacidade de validação em desenvolvimento e testes.

## 47. Critérios de promoção declarativos
`PersistentArtifactBackendPromotionCriteria` documenta requisitos sem executar ações.

## 48. Correlação por operação física
`PersistentArtifactPhysicalCorrelation` gera correlation IDs por operação para observabilidade.

## 49. Propagação de correlation no observable
`ObservablePersistentArtifactProvider` injeta `correlationId` em operações físicas observadas.

## 50. Estados físicos ampliados
Status incluem `idempotent`, `quarantined`, `environmentBlocked`, `backendDisabled`, `unregistered` e demais estados de hardening.

## 51. Mapper de status ampliado
`PersistentArtifactPhysicalStatusMapper` cobre outcomes filesystem e mapeamento por issue code.

## 52. Modelos físicos serializáveis
Requests/results físicos possuem `toJson`, `toComparableJson` e codec `fromJson` para replay.

## 53. Handles serializados por primitivos
Serialização preserva neutralidade de vendor convertendo handle para `handleId/backendId`.

## 54. Service físico centralizado
`PersistentArtifactPhysicalOperationsService` implementa fluxos físicos por registry+bridge.

## 55. Contenção de falhas
Exceções de bridge são contidas em status `failed`, mantendo isolamento de erro.

## 56. Composição local-reference
`PersistentArtifactLocalReferenceComposition` cria runtime explícito com registry+provider.

## 57. Runtime com dispose idempotente
`PersistentArtifactLocalReferenceRuntime.dispose/unregister` são idempotentes e não apagam conteúdo.

## 58. Sem auto-registro por bootstrap
Composição não altera bootstrap global nem ativa registro implícito em produção.

## 59. Export isolado no entrypoint filesystem
Composição e bridge concrete são exportados por `masterpalm_platform_filesystem.dart`.

## 60. Export vendor-neutral no entrypoint core
Decisão de ambiente, critérios e contratos de bridge ficam disponíveis em `masterpalm_platform.dart`.

## 61. Suite de hardening dedicada
`test/persistent_artifacts/hardening/` cobre replay, goldens, gate, composição, observabilidade e contenção.
