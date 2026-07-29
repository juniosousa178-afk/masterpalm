# Checklist — App Check produção (R8.4.38)

**Somente leitura.** Não alterar enforcement nem configuração.

## Passos para o operador

1. Abrir [Firebase Console](https://console.firebase.google.com/)
2. Selecionar projeto `masterpalm-58c46`
3. Menu **Build** → **App Check**
4. Localizar o app **Web** do MasterPalm
5. Registrar os campos abaixo (sem copiar chaves completas nem tokens)

## Campos de evidência

```
WEB_APP_REGISTERED=
PROVIDER=
DOMAIN_AUTHORIZED=
VALID_REQUEST_METRICS=
INVALID_REQUEST_METRICS=
FIRESTORE_ENFORCEMENT=
STORAGE_ENFORCEMENT=
FUNCTIONS_ENFORCEMENT=
VERIFIED_AT=
VERIFIED_BY=
```

## Verificações

- [ ] Web app cadastrada (sim/não)
- [ ] Provider configurado (ex.: reCAPTCHA v3) — **não** registrar chave completa
- [ ] Domínio `app.mastepalm.com.br` autorizado
- [ ] Métricas de requisições válidas/inválidas anotadas
- [ ] Enforcement Firestore (monitoring/enforced)
- [ ] Enforcement Storage
- [ ] Enforcement Functions
- [ ] Data/hora da verificação
- [ ] Nenhuma opção alterada durante a auditoria

## Classificação

Até o checklist ser preenchido com evidência:

`APP_CHECK_PRODUCTION_CONSOLE_VERIFICATION_REQUIRED`

Após preenchimento com evidência (sem segredos):

`APP_CHECK_PRODUCTION_CONFIGURATION_VERIFIED` ou `APP_CHECK_PRODUCTION_CONFIGURATION_INCOMPLETE`
