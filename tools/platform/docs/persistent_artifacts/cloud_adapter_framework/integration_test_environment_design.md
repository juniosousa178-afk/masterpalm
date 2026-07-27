# Integration Test Environment Design

**Status:** draft — ambiente **não criado**.

## Princípios

- **Não é staging** nem production (ambos bloqueados).
- Conta/projeto cloud dedicado e isolado.
- Containers/buckets com naming convention `pa-integration-*`.
- Dados sintéticos apenas; sem PII.
- Credenciais temporárias via workload identity / role de teste.
- Budget alerts e quotas rígidas.
- Teardown automático de objetos > 7 dias.
- Network restrictions (private endpoint ou emulator local).
- Audit logs habilitados.
- Owner: Platform QA (evidenceMissing — nome formal pendente).

## Emuladores (design)

- LocalStack / MinIO / Azurite — avaliar após SDK decision.
- Nenhum emulator instalado nesta sprint.
