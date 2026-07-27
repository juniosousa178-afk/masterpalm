# Provider Comparison Matrix

Estados por célula: `supported`, `partiallySupported`, `unsupported`, `unknown`, `evidenceMissing`, `notApplicable`.

**Nota:** Classificações baseadas em alinhamento arquitetural com contratos PA existentes e documentação pública conhecida. Não constitui seleção aprovada nem evidência de testes de integração.

| Critério | AWS S3 | GCS | Azure Blob | S3-Compatible | Evidência | Confiança |
|----------|--------|-----|------------|---------------|-----------|-----------|
| Object put/get/head/list | supported | supported | supported | partiallySupported | Contratos PA + APIs públicas | medium |
| Conditional writes | supported | supported | supported | partiallySupported | Vendor docs (reviewRequired) | medium |
| Object versioning | supported | supported | supported | partiallySupported | Vendor docs (reviewRequired) | medium |
| Multipart upload | supported | supported | supported | partiallySupported | Vendor docs (reviewRequired) | medium |
| Server-side copy | supported | supported | supported | partiallySupported | Vendor docs (reviewRequired) | medium |
| Retention lock / governance | supported | partiallySupported | supported | unknown | Vendor docs (reviewRequired) | low |
| Legal hold | supported | supported | supported | unknown | Vendor docs (reviewRequired) | low |
| SSE / CMK | supported | supported | supported | partiallySupported | Vendor docs (reviewRequired) | medium |
| Private endpoint | supported | supported | supported | partiallySupported | Vendor docs (reviewRequired) | medium |
| Workload identity | supported | supported | supported | evidenceMissing | Plataforma alvo TBD | low |
| Official Dart SDK | partiallySupported | partiallySupported | partiallySupported | evidenceMissing | Pub/ecossistema (reviewRequired) | low |
| List pagination token | supported | supported | supported | partiallySupported | Contratos PA list | medium |
| Throttling model | supported | supported | supported | unknown | Vendor error codes (reviewRequired) | low |
| Strong read-after-write (regional) | supported | partiallySupported | partiallySupported | unknown | Consistency docs (reviewRequired) | low |
| Cross-region replication | supported | supported | supported | notApplicable | Vendor feature matrix | medium |
| Cost observability | supported | supported | supported | evidenceMissing | Billing APIs (reviewRequired) | low |
| Emulator for integration tests | supported | partiallySupported | partiallySupported | partiallySupported | LocalStack/Azurite/GCS emulator | medium |
| Lock-in risk | medium | medium | medium | low | Arquitetural | medium |

## Resumo por candidato

| Candidato | Prós | Contras |
|-----------|------|---------|
| AWS S3 | API de facto para object storage; amplo ecossistema | Lock-in AWS; SDK Dart não first-class |
| GCS | Integração GCP; uniform bucket access | Semântica diferente de S3; SDK via googleapis |
| Azure Blob | Enterprise Azure; hierarchical namespace opcional | API divergente; mais complexidade de auth |
| S3-Compatible | Portabilidade; testes com MinIO/LocalStack | Variabilidade entre implementações; gaps em governance |

Nenhum candidato está **selecionado** (`targetProviderSelected` permanece `false`).
