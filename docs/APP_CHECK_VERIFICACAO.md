# Como ter 100% de certeza que o App Check está funcionando

O App Check protege Firestore, Storage e (se configurado) Cloud Functions contra abuso. Para ter **certeza total**, faça as três verificações abaixo.

---

## 1. No app: token sendo gerado (cliente)

- **Onde:** Tela **Health Check** do app.
- **Como abrir:**
  - **Modo debug:** menu lateral → seção **Desenvolvedor** → **Health Check (App Check)** (visível para qualquer usuário em debug; em release só para tipo Programador).
  - Ou navegar para a rota `/health` (ex.: deep link ou `Navigator.pushNamed(context, '/health')`).
- **O que conferir:**
  - O card **AppCheck** deve estar **verde** com mensagem tipo: *"Token OK (Mobile)"* ou *"Token OK (Web)..."*.
  - Se estiver vermelho ou "Token vazio", o App Check **não** está ativo no cliente (veja logs no console e [tokens de depuração](#debug-android) no Firebase).

**Conclusão:** Verde = o app está gerando e enviando token para o Firebase.

---

## 2. No Firebase Console: enforcement ativo (servidor)

- **Onde:** [Firebase Console](https://console.firebase.google.com) → seu projeto → **App Check**.
- **O que fazer:**
  1. Abra **App Check** e confira as métricas (Firestore, Storage, etc.).
  2. Para cada produto que você quer proteger (ex.: Firestore, Storage):
     - Clique no produto → **Enforce** (Ativar aplicação).
     - Aguarde até ~15 minutos para propagar.
  3. Com **Enforcement** ligado, requisições **sem** token válido passam a ser **rejeitadas**.

**Conclusão:** Se Enforcement estiver **On** para Firestore/Storage, o backend só aceita requisições com App Check válido.

---

## 3. Prova definitiva: requisição sem token é rejeitada

- **Objetivo:** Garantir que o servidor realmente exige o token (não só que o app envia).
- **Como:**
  1. Deixe **Enforcement** ligado para Firestore (e/ou Storage).
  2. Faça uma requisição **sem** App Check:
     - Outro app (sem `firebase_app_check` / sem ativar App Check), ou
     - Chamada direta à API (ex.: REST com API key mas **sem** header de App Check).
  3. O resultado deve ser **erro de permissão** (ex.: 401/403 ou mensagem do Firebase de "unverified request").

**Conclusão:** Se só o app oficial passa e qualquer cliente sem token é barrado, o App Check está **100% em uso**.

---

## Resumo rápido

| O que verificar              | Onde                    | Resultado esperado                          |
|-----------------------------|-------------------------|---------------------------------------------|
| Token no app                | Health Check → AppCheck | Card verde, "Token OK"                      |
| Enforcement no backend      | Console → App Check     | Enforcement **On** para Firestore/Storage   |
| Cliente sem token barrado   | Teste manual (ver item 3)| Erro 401/403 ou "unverified"                |

Quando os três estão ok, você tem **100% de certeza** de que o App Check está funcionando.

---

## Dicas

### "Too many attempts" (FirebaseException)
- O Firebase limita quantas vezes você pode **forçar** a geração de um novo token em pouco tempo.
- Se a Health Check ou o app chamar `getToken(true)` (forçar refresh) com muita frequência, aparece esse erro.
- **O que fizemos:** a Health Check e o self-check do app passaram a usar **token em cache** (`getToken(false)`) quando possível, para não estourar o limite.
- Se ainda aparecer: espere alguns minutos e rode a Health Check de novo (puxe para atualizar), ou reinicie o app.

### Debug (Android) – cadastrar Debug Token
1. Rode o app em **debug** (Android). O token é impresso no **logcat** pelo SDK nativo.
2. Para ver o token:
   - Terminal: `adb logcat | grep -i DebugAppCheckProvider`
   - Android Studio: abra **Logcat** e filtre por `"debug secret"` ou `"App Check"`.
   - Procure uma linha do tipo: `Enter this debug secret into the allow list...` seguida do token (UUID).
3. **Firebase Console:** [App Check](https://console.firebase.google.com) → seu projeto → **App Check** → **Apps** → selecione o app **Android** → **Tokens de depuração** (ou "Manage debug tokens") → **Add token** → cole o token do logcat → Salvar.
4. Durante o desenvolvimento, deixe **Enforcement** em **"Monitor only"** (não "Enforce") para não bloquear requisições enquanto o token ainda não estiver cadastrado ou em testes.
5. Sem cadastrar o token, o app pode retornar 403 "App attestation failed"; após cadastrar, o Health Check deve ficar verde.

### Release (Android)
- Use **Play Integrity** (já configurado no `main.dart` em release).
- Requer aparelho físico e app distribuído pela Play Store (ou com SHA do keystore cadastrado no Firebase).

### Health Check e Firestore/Storage
- A tela Health Check também faz **leitura/escrita no Firestore** e **upload no Storage**.
- Com **Enforcement ligado**, se esses testes passarem (cards verdes), significa que o token está sendo aceito pelo backend; se falharem, pode ser token inválido ou regras de segurança.
 sem