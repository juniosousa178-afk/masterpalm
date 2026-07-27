# Persistent Artifact Cloud Provider Recommendation

**Status:** draft — aguarda revisão manual
**targetProviderSelected:** `false` (não alterado)

## Candidato recomendado (para revisão)

**AWS S3** como protocolo/API primária de referência para o primeiro adapter real, com avaliação paralela de compatibilidade S3-compatible para portabilidade futura.

Esta é uma **recomendação arquitetural**, não aprovação de fornecedor.

## Alternativas

1. **Google Cloud Storage** — viável se residência/stack GCP for mandatória organizacionalmente.
2. **Azure Blob Storage** — viável se stack Azure for mandatória.
3. **S3-Compatible dedicado** (ex.: MinIO em ambiente isolado) — viável para protótipo controlado sem vendor lock-in imediato.

## Critérios de escolha

- Alinhamento com `PersistentArtifactCloudBackendBridge` e capabilities existentes.
- Suporte a multipart, versioning, conditional operations, metadata.
- Caminho credencial via workload identity (sem long-lived keys).
- Maturidade de documentação e ferramentas de integração.
- Custo e operabilidade em ambiente de testes isolado.

## Vantagens (S3 como referência)

- Modelo mental alinhado a `PersistentArtifactCloudProviderType.s3Compatible`.
- Amplo material de referência para semântica de erros, throttling e multipart.
- Emuladores maduros para ambiente de integração futuro (sem uso nesta sprint).

## Desvantagens

- SDK Dart oficial limitado em relação a outros runtimes.
- Semânticas de governance (Object Lock, legal hold) exigem validação por ambiente.
- Lock-in de API e billing AWS se não houver camada de abstração disciplinada.

## Riscos

- Supor equivalência S3 ↔ contratos PA sem testes reais.
- Escolher SDK antes de security review de dependências.
- Confundir recomendação com `approvedForPrototype`.

## Requisitos não atendidos (ainda)

- Seleção organizacional formal de cloud provider.
- Evidência de testes de integração.
- Aprovação manual de arquitetura.

## Confiança

**Média-baixa** — recomendação baseada em fit arquitetural, não em PoC executado.

## Evidências utilizadas

- Contratos PA Sprint 05.3.2 (vendor-neutral).
- Comparison matrix desta sprint.
- Estado admission: todos critérios sem `approved`.

## Evidências ausentes

- Benchmark de SDK Dart em runtime alvo.
- Decisão organizacional de residência/compliance.
- PoC de autenticação workload identity no ambiente real.

## Impactos

| Área | Impacto |
|------|---------|
| Contratos | Mínimo se adapter mapear para status PA existentes |
| Dependências | SDK/HTTP futuro — fora desta sprint |
| Operações | Incident response, cost controls — documentados como draft |
| Segurança | Credential architecture draft; sem segredos |
| Financeiro | Cost plan draft |
| Reversão | Bridge isolada permite troca de backend com novo adapter |
