# Baseline estável — MasterPalm Web

**BuildId:** `diag-20260427-APPSTARTFIX-f14fe79`  
**Data:** 2026-04-27

**Status:** Validada em PC, Android, iPhone Web, Safari, Chrome e WhatsApp WebView.

O detalhe por ambiente encontra-se abaixo (tabela de validação).

## BuildId (referência única)

```
diag-20260427-APPSTARTFIX-f14fe79
```

## Ambientes validados

- PC: OK
- Android: OK
- iPhone Web: OK
- Safari iPhone: OK
- Chrome iPhone: OK
- WhatsApp WebView iPhone: OK

## URLs validadas

- https://app.mastepalm.com.br/
- https://app.mastepalm.com.br/loja/nathy-pratas-e-folheados

## Correções consolidadas

- Rota raiz do app protegida
- app.mastepalm.com.br/ não cai mais como loja inválida
- Firebase.apps protegido no WebKit
- Boot web do iPhone corrigido
- Splash “Preparando tudo...” destravado
- Catálogo público funcionando
- Diagnósticos mantidos temporariamente

## Política de congelamento

Não alterar nesta fase:

- Firebase
- rotas
- catálogo
- Firestore rules
- hosting rules
- diagnóstico web (sem remoção agressiva)

Os diagnósticos appStartTrace, bootTrace, netTest e overlays `diag` devem permanecer por enquanto. Ver [SECURITY_BASELINE.md](SECURITY_BASELINE.md).

## Observação

Qualquer nova melhoria deve partir desta baseline, com buildId novo e escopo separado.

## Regressão

Testes automáticos: `test/catalog_initial_web_route_test.dart` (ver checklist em [DEPLOY_CHECKLIST.md](DEPLOY_CHECKLIST.md)).
