# Cost Control Plan

**Status:** draft

## Controles propostos

- Budget mensal para ambiente de integração.
- Alertas em 50%, 80%, 100%.
- Quotas: max objects, max storage GB, max egress GB/mês.
- Request rate caps em testes automatizados.
- Multipart limits para evitar uploads massivos acidentais.
- Cleanup scheduled de prefixos de teste.
- Runaway protection: abort test suite se custo diário > threshold.

`costControlsApproved` permanece `false`.
