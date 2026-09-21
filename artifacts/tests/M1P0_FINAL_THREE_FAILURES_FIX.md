# M1P0 — Três falhas finais — correção

## FAIL_1 — Hive box already open

**Causa:** `Hive.box(name)` sem tipo no teardown, com box aberta como `Box<Produto>`.  
**Fix:** fechar com `Hive.box<Produto>(name)` + `Hive.close()` antes de `Hive.init` no teste de push.  
Push de cadastro alinhado a `forcePushFromCadastro: true` (contrato do formulário).

FAIL_1_FIXED=true

## FAIL_2 — esperado confirmado, recebido semMudancas

**SEM_MUDANCAS_CONTRACT=** auto-sync (`forcePushFromCadastro=false`) **pode** retornar `semMudancas` quando o guard anti-Hive-stale detecta células locais dominando o remoto (ex.: qty 5→9) ou remoto mais novo.  
Save explícito do cadastro usa `forcePushFromCadastro=true` → `confirmado` quando há write.

**Fix:** teste de edição de variação alinhado ao contrato real do formulário. Não alteramos o retorno só para passar o teste.

FAIL_2_FIXED=true

## FAIL_3 — custoReal no doc público

**Causa:** `enforceStockRevisionWriteContract` no upsert do catálogo público `produtos`. Payload público tem `quantidade`/`variacoes` sem `stockRevision` → `MISSING_REVISION_FIELDS` → set público não rodava → `custoReal` legado permanecia.

**Fix:** `enforceStockRevision: false` no upsert público (projeção). Strip via `_publicoInternoKeysToStrip` + `forceRemoveKeys` continua ativo. Autoridade CAS permanece em `estoque_produtos`.

Campos privados stripados: custoReal, custo, precoCusto, fornecedor, frete, gastosFixos, gastosVariaveis, precoSugerido, custoEditadoNoCadastro, dataEntrada, ativoNoRascunho.

FAIL_3_FIXED=true

## Verificação

M1P0 QA Bot run `20260921_115026`: **GO** — 112 passed / 0 failed.
