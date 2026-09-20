# MASTERPALM — P0
# MIRJOIAS CLOUD SALE + LOCAL RECEIVABLE FAILURE
# FIX AND RELEASE

```text
TICKET=MASTERPALM_MIRJOIAS_CLOUD_SALE_LOCAL_RECEIVABLE_FAILURE_P0_FIX_AND_RELEASE
STORE=mirjoias
WINDOW_UTC=2026-09-19T23:48:00Z/2026-09-19T23:58:00Z
SALE_ID_SANITIZED=37dc1c56
OPERATION_ID_SANITIZED=37dc1c56
SALE_INTENT_SANITIZED=34277810
RESTORE_OP_SANITIZED=restore_b991625a
CR_DOC_SANITIZED=cr_37dc1c56_p1
PII_EXPOSED=false
```

## 1. Correlação

```text
SALE_REQUEST_FOUND=true
SALE_ID_SANITIZED=37dc1c56
SALE_CREATED=true (23:52:21Z atomic PDV) then RESTORED (00:17:45Z)
SALE_CREATE_COUNT=1
STOCK_OPERATION_CREATED=true
STOCK_DECREMENTED=true then RESTORED
FINANCIAL_OPERATION_CREATED=false
CLOUD_RECEIVABLE_CREATED=true (00:20:07Z repair) then CANCELLED (orphan)
LOCAL_RECEIVABLE_CREATED=false
LOCAL_RECEIVABLE_FAILED=true
HTTP_STATUS=200
BACKEND_RESULT=atomic sale+stock applied (legacyCompat simple)
TOTAL=1520
PAYMENT_METHODS=fiado
IS_FIADO=true
```

## 2. Duplicidade

```text
SALE_CREATE_COUNT=1
DECISION_DUPLICATE=false
```

## 3. Estado autoritativo (após restore do cliente)

```text
AUTHORITATIVE_SALE_STATE=E
  (original incident was B SALE_COMMITTED_STOCK_COMMITTED_RECEIVABLE_MISSING)
  (same actorUid restored sourceOperationId=37dc1c56 at 00:17:45Z)
```

## 4. Pagamento Faltam R$ 1520

```text
SALE_TOTAL=1520
PAYMENT_ALLOCATED=0
PAYMENT_REMAINING=1520
PAYMENT_METHODS=fiado
IS_FIADO=true
RECEIVABLE_EXPECTED=true
PAYMENT_STATE_VALID_FOR_SALE=true
PAYMENT_VALIDATION_BYPASSED=false
```

Fiado com allocated=0 é válido. Não foi commit com pagamento incompleto de venda normal.

## 9. Root cause

```text
ROOT_CAUSE=A
  CLOUD_COMMIT_BEFORE_LOCAL_RECEIVABLE_AND_LOCAL_WRITE_FAILED
ROOT_CAUSE_PATH=lib/services/vendas_service.dart
ROOT_CAUSE_SYMBOL=registrarVendaMulti / VENDA_FIADA_CONTA_RECEBER_FAIL
UI_BUG_PATH=lib/screens/nova_venda_modal.dart
UI_BUG_SYMBOL=_salvarVendaEmBackground BACKGROUND_SAVE_FIADO
  ArgumentError after atomic commit returned ok=false
  dialog prefixed "A venda não foi salva."
```

## 6–8. Repair

```text
TARGETED_REPAIR_PERFORMED=true
STOCK_WRITES_DURING_REPAIR=0
SALE_RECREATED=false
CR_CREATED_THEN_CANCELLED=true
  (CR created 00:20Z after sale already restored 00:17Z; cancelled same doc id)
FINANCIAL_REPAIR_WRITES=1 (cancel orphan CR; no lancamento)
```

## 10–12. Code

After atomic/cloud commit, local Hive/CR failure:
- does not restore stock
- does not tell UI the sale was not saved
- throws VendaSalvaComPendenciaSyncException.localMirrorMessage
- UI: success + refresh warning
- remote CR upsert best-effort even if Hive fails
- pullContasReceberRemotas rehydrates on reload

## 13. Tests

```text
P0_RECEIVABLE_FAILURE_TESTS=20/20
FOCUSED_SUITE=100 passed
```

## 15–17. Release

```text
BRANCH=release/cloud-sale-local-receivable-p0
HOSTING_DEPLOYS<=1
FUNCTION_DEPLOYS=0
RULES_DEPLOYS=0
```

## 19. Customer action

```text
CUSTOMER_MUST_RETRY_SALE=false
CUSTOMER_CAN_REFRESH_AFTER_FIX=true
CUSTOMER_MUST_CHECK_HISTORY=true
```

Do not launch a second sale for the same 12 items while refreshing.
Original cloud sale was later restored (stock returned) by the same account at 00:17:45Z.
After refresh: confirm history and Contas a Receber (orphan CR cancelled).
If goods were already delivered, open a separate follow-up to re-register that one fiado sale under a new identity — this ticket does not create a new sale.
