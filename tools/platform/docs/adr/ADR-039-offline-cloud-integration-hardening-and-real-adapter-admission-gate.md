# ADR-039 — Offline Cloud Integration Hardening and Real-Adapter Admission Gate

## Status
Accepted

## Contexto
A Parte 2 integrou contratos cloud operacionais em modo offline-simulation, com
registry, service, provider, status mapper, environment gate e fake bridge
exclusivamente em testes. A Parte 3 consolida hardening cross-layer e introduz
um gate declarativo para admissão futura de adapter real — sem implementá-lo.

## Problema
Sem composition root offline explícito, admission criteria e suíte de hardening
dedicada, o fluxo cloud offline permaneceria fragmentado entre helpers de teste
operacional e sem fronteira formal contra promoção indevida a staging,
produção ou protótipo com SDK.

## Decisão
1. Introduzir `PersistentArtifactOfflineCloudReferenceComposition` (test-only)
   com lifecycle create/register/use/unregister/dispose.
2. Endurecer `PersistentArtifactCloudEnvironmentGate` para `contractOnly`
   permitir validação estrutural em ambientes não-produtivos.
3. Introduzir Real-Adapter Admission Gate:
   - `PersistentArtifactRealCloudAdapterAdmissionCriteria`
   - `PersistentArtifactRealCloudAdapterAdmissionDecision`
   - `PersistentArtifactRealCloudAdapterAdmissionEvaluator`
4. Adicionar 30 goldens finais em `cloud_hardening/`.
5. Expandir suíte `test/persistent_artifacts/cloud/hardening/`.

## Restrições mantidas
- Sem adapter cloud real
- Sem SDK
- Sem HTTP/rede
- Sem credenciais resolvidas
- Staging bloqueado
- Production bloqueada
- Bootstrap sem backend cloud
- Fake bridge somente em test/

## Alternativas rejeitadas
- Auto-registro de adapter no bootstrap
- Composition root em `lib/`
- Aprovação automática de protótipo quando critérios satisfeitos
- Habilitar staging após policy satisfeita

## Riscos
- Falsa sensação de prontidão após sucesso offline
- Confusão entre ETag de provider e digest canônico
- Tentativa de usar admission gate como autorização de release

## Limitações
- Success offline não prova persistência remota
- Multipart offline não prova multipart remoto
- Retry classifier e execution plan permanecem declarativos
- `approvedForPrototype` não instala SDK nem habilita ambientes

## Consequências
- Arquitetura offline auditável e reproduzível
- Gate explícito para futura sprint de protótipo
- Maior cobertura de invariantes via property/mutation/stress

## Validação
- `dart analyze lib`
- `dart test test/persistent_artifacts/cloud`
- `dart test test/persistent_artifacts`
- `dart test`
- Guardian verde
