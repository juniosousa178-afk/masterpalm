# Checklist antes de publicar nova versão

Use este checklist antes de gerar build de release (APK/AAB) ou publicar na loja. Não substitui testes completos; reduz chance de enviar versão com erro óbvio.

---

## Autenticação e loja

- [ ] Login com e-mail/senha funciona (conta de teste).
- [ ] Após login, a loja correta aparece (store_id / lojaId esperado).
- [ ] Trocar de loja (se o app permitir) não mistura dados de outra loja.
- [ ] Logout e login de novo mantêm comportamento correto.

---

## Dados e sync

- [ ] Após login, a sincronização inicial (FullSync) termina sem erro (ver log “FULL-SYNC FINALIZADA” ou equivalente).
- [ ] Lista de produtos da loja carrega (pelo menos uma tela: estoque ou catálogo interno).
- [ ] Lista de clientes ou vendas carrega (conforme o app).
- [ ] Fazer uma venda de teste (ou criar um produto/cliente) e verificar que aparece na lista e, se aplicável, que a Sync Queue processa (ver diagnóstico ou log).

---

## Catálogo público (se aplicável)

- [ ] Abrir o catálogo público (link ou tela) com a loja correta.
- [ ] Lista de produtos do catálogo aparece.
- [ ] Configuração (ex.: pagamentos) não gera PERMISSION_DENIED (ver log; se usar App Check, token de debug cadastrado).

---

## Funcionalidades críticas (escolher 2–3 por versão)

- [ ] Uma venda concluída de ponta a ponta (produto, cliente, pagamento).
- [ ] Cadastro ou edição de produto e salvamento.
- [ ] Tela de diagnóstico (se for build de programador) abre e não mostra erro novo em “Erros”.

---

## Build e ambiente

- [ ] `flutter analyze` sem erros (ou apenas avisos conhecidos).
- [ ] Testes automatizados rodando: `flutter test test/vendas_service_test.dart test/store_access_guard_test.dart` (ou o conjunto que existir).
- [ ] Versão e nome do app no pubspec/build.gradle corretos para a release.

---

## Opcional (se tiver tempo)

- [ ] App Check: em debug, token cadastrado; em release, SHA correto no Firebase.
- [ ] Firestore/Storage: sem erro novo no console após usar o app por 1–2 minutos.

---

*Marque os itens conforme for testando. Se algo falhar, corrija antes de publicar.*
