# Cloud Storage Incident Response

**Status:** draft

## Cenários

| Incidente | Ação imediata | Evidência |
|-----------|---------------|-----------|
| Credential compromise | Revogar identity, unregister backend | Preservar audit logs |
| Unexpected deletion | Stop writes, assess retention/hold | Inventory list |
| Data corruption | Halt promotion, compare digests | PA integrity evaluator |
| Cost spike | Disable backend, alert FinOps | Billing dashboard |
| Provider outage | Surface `unavailable`, no retry storm | Status page |

## Escalation

1. On-call Platform Ops (evidenceMissing)
2. Security (credential events)
3. Engineering management (prolonged outage)

`incidentResponseApproved` permanece `false`.
