# Real Adapter Admission Evidence Matrix

**Atualizado:** Sprint 05.3.3 Parte 1 — documentos draft/reviewRequired; nenhum critério `approved`.

Estados: `evidenceMissing`, `draft`, `reviewRequired`, `approved`, `rejected`, `notApplicable`.

| Critério | Estado | Evidência | Qualidade | Gap | Owner | Aprovação exigida |
|----------|--------|-----------|-----------|-----|-------|-------------------|
| targetProviderSelected | reviewRequired | provider_recommendation.md, provider_comparison_matrix.md | draft | Aprovação manual de fornecedor | Platform Architecture | Architecture Review |
| protocolSpecificationReviewed | reviewRequired | protocol_specification_review.md | draft | PoC protocolo | Platform Architecture | Design Review |
| officialSdkDecisionRecorded | reviewRequired | official_sdk_decision.md | draft | Security + ADR SDK | Platform Architecture | ADR |
| dependencySecurityReviewApproved | draft | dependency_security_review_plan.md | draft | Execução do plano | Security | Security sign-off |
| credentialArchitectureApproved | reviewRequired | credential_architecture.md | draft | Implementação + review | Security | Security Architecture |
| leastPrivilegePolicyApproved | reviewRequired | least_privilege_policy.md | draft | IAM bindings reais | Security | IAM review |
| workloadIdentityDecisionApproved | reviewRequired | workload_identity_decision.md | draft | Stack org definida | Security | Identity review |
| networkBoundaryApproved | reviewRequired | network_boundary_design.md | draft | Infra real | Security/Infra | Network review |
| endpointPolicyApproved | reviewRequired | endpoint_and_tls_policy.md | draft | Allowlist produção | Security/Infra | Endpoint review |
| TLSPolicyApproved | reviewRequired | endpoint_and_tls_policy.md | draft | Validação TLS | Security | TLS review |
| dataResidencyApproved | reviewRequired | data_residency_decision.md | draft | Decisão Compliance org | Compliance | Compliance review |
| encryptionPolicyApproved | reviewRequired | encryption_and_key_ownership.md | draft | KMS decision | Security | Encryption review |
| keyOwnershipApproved | reviewRequired | encryption_and_key_ownership.md | draft | CMK ownership formal | Security | Key management |
| retentionSemanticsApproved | reviewRequired | retention_semantics.md | draft | PoC Object Lock | Platform Ops | Ops review |
| legalHoldSemanticsApproved | reviewRequired | legal_hold_semantics.md | draft | PoC legal hold | Legal/Compliance | Legal review |
| deletionSemanticsApproved | reviewRequired | deletion_semantics.md | draft | PoC delete paths | Platform Ops | Ops review |
| versioningSemanticsApproved | reviewRequired | versioning_semantics.md | draft | PoC versioning | Platform Architecture | Design review |
| consistencySemanticsDocumented | reviewRequired | consistency_semantics.md | draft | Medição consistência | Platform Architecture | Design review |
| retrySemanticsApproved | reviewRequired | retry_and_timeout_semantics.md | draft | Adapter retry policy | Platform Architecture | Ops review |
| timeoutSemanticsApproved | reviewRequired | retry_and_timeout_semantics.md | draft | Timeouts operacionais | Platform Architecture | Ops review |
| idempotencyStrategyApproved | reviewRequired | idempotency_strategy.md | draft | Testes idempotência | Platform Architecture | Design review |
| multipartStrategyApproved | reviewRequired | multipart_strategy.md | draft | PoC multipart | Platform Architecture | Design review |
| observabilityPolicyApproved | reviewRequired | observability_policy.md | draft | Telemetry adapter | Observability | Observability review |
| secretRedactionApproved | reviewRequired | secret_redaction_policy.md | draft | Security audit logs | Security | Security review |
| integrationTestEnvironmentApproved | draft | integration_test_environment_design.md | draft | Ambiente não criado | QA/Infra | Infra approval |
| costControlsApproved | draft | cost_control_plan.md | draft | Budgets reais | FinOps | FinOps review |
| rateLimitStrategyApproved | reviewRequired | rate_limit_strategy.md | draft | Limites calibrados | Platform Ops | Ops review |
| incidentResponseApproved | draft | cloud_storage_incident_response.md | draft | Drill não executado | Platform Ops | Ops approval |
| operationalOwnerAssigned | evidenceMissing | operational_ownership.md | placeholder | Nomes formais | Engineering Mgmt | Management |
| rollbackPlanApproved | reviewRequired | rollback_plan.md | draft | Drill rollback | Platform Ops | Ops approval |
| ADRApproved | reviewRequired | ADR-040 (Proposed) | draft | Aceite manual ADR | Platform Architecture | ADR sign-off |

## Baseline evaluator (critérios booleanos permanecem false)

| Campo | Valor |
|-------|-------|
| criteria input | Todos `false` |
| manualApprovalReference | ausente |
| decision status | `notEvaluated` |
| approvedForPrototype | **false** |
| stagingApproved | **false** |
| productionApproved | **false** |
| realAdapterWorkAuthorized | **false** |

Documentos draft **não** preenchem campos booleanos do criteria model.
