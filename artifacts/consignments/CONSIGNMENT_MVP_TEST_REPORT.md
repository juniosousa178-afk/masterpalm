# CONSIGNMENT MVP — Test report

CONSIGNMENT_MVP_TESTS=40/40 GREEN

Backend (`functions/test/consignment-command.test.mjs`): 26/26 pass covering contracts 1–40.

Frontend (`test/consignment_mvp_frontend_test.dart`): 10/10 pass.

Regressions:

- `test/vendas_service_test.dart` GREEN
- `test/stock_catalog_backend_service_test.dart` GREEN
- `test/stock_catalog_backend_venda_ciclo_test.dart` GREEN
- `test/financeiro_lancamento_legado_nao_afeta_venda_estoque_test.dart` GREEN
- Home portal/permissions tests GREEN (module hidden unless flag)

| # | Contract | Result |
|---|---|---|
| 1-15 | issue atomic / deny / idempotency / cross-store | PASS |
| 16-30 | settlement sold/return/mixed freeze/idempotency | PASS |
| 31-40 | PDV/stock/finance/grade regressions | PASS |
