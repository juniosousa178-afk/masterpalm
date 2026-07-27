# Official SDK Decision

**Status:** `reviewRequired`
**officialSdkDecisionRecorded:** permanece `false` até aprovação manual.

## Opções avaliadas

| Opção | Avaliação | Decisão preliminar |
|-------|-----------|-------------------|
| 1. SDK oficial do fornecedor | Manutenção variável em Dart; transitive deps | reviewRequired |
| 2. SDK comunitário | Risco de supply chain | rejected até security review |
| 3. Cliente HTTP direto | Controle máximo; custo de SigV4/parsing | reviewRequired como fallback |
| 4. Bridge para serviço intermediário | Acoplamento operacional extra | notApplicable nesta fase |
| 5. Cliente gerado por spec | Overhead de geração | notApplicable |
| 6. Não implementar | Estado atual | **accepted (interino)** |

## Recomendação preliminar (não aprovada)

1. **Primeira preferência:** SDK oficial ou pacote mantido pelo fornecedor, isolado **atrás** de `PersistentArtifactCloudBackendBridge` em módulo adapter dedicado (fora de `lib/` core até gate).
2. **Fallback:** Cliente HTTP mínimo com assinatura isolada, somente após `dependency_security_review_plan.md` aprovado.
3. **Proibido nesta sprint:** instalar qualquer pacote.

## Critérios de decisão final

- Transitive dependencies e licenças.
- Credential handling sem expor segredos à API pública PA.
- Compatibilidade VM/Flutter conforme runtime alvo.
- Testabilidade com fake/emulator.
- Isolamento: core PA permanece vendor-neutral.

## Lock-in

SDK oficial aumenta lock-in; mitigação via bridge e contratos PA estáveis.
