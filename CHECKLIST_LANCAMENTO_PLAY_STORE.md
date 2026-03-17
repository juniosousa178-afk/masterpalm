# 🚀 Checklist de Lançamento – MasterPalm na Play Store

**Objetivo:** Publicar o app blindado, sem dores de cabeça futuras.

---

## 1. ANTES DE GERAR O APK

### 1.1 Configuração Android
- [x] `key.properties` (assinatura release) – **verificar se arquivo existe**
- [x] `targetSdk = 34` (exigência Google 2024+)
- [x] `minSdk = 23` (Android 6+)
- [x] ProGuard/R8 habilitado (ofuscação)
- [x] `isShrinkResources = true` (remove recursos não usados)
- [ ] **Remover `debugPrint` e `print` desnecessários** (ou usar `kReleaseMode`)

### 1.2 Verificações de código
```bash
# Rodar antes de publicar
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
flutter build apk --release
```

### 1.3 Segredos e credenciais
- [ ] **Nenhum token/API key hardcoded** no código
- [ ] Variáveis sensíveis só em Firebase Remote Config ou secrets
- [ ] `google-services.json` no `.gitignore` (se aplicável para repositório público)

---

## 2. PLAY STORE – REQUISITOS OBRIGATÓRIOS

### 2.1 Conta Google Play
- [ ] Conta de desenvolvedor (pagamento único ~US$25)
- [ ] Aplicativo criado no Console
- [ ] App signing configurado (upload key ou Play App Signing)

### 2.2 Política de Privacidade
- [x] **Página criada:** `public/privacidade.html`
- [x] **Rewrite Firebase:** `/privacidade` → `/privacidade.html`
- [ ] **Deploy:** rode `./build-and-deploy.sh` (ou `flutter build web` + copiar `public/privacidade.html` para `build/web/` + `firebase deploy --only hosting`)
- [ ] **URL para Play Store:** `https://mastepalm.com.br/privacidade` (ou domínio do seu projeto)

**Conteúdo incluído:**
- Quais dados o app coleta (login, cadastro, vendas, contatos)
- Como são usados (funcionamento do app, suporte)
- Com quem são compartilhados (Firebase, Mercado Pago, etc.)
- Direitos do usuário (acesso, exclusão, portabilidade)
- Contato para dúvidas

### 2.3 Data Safety (Formulário Google)
- [ ] Preencher no Console: dados coletados, finalidade, compartilhamento
- [ ] Indicar se dados são opcionais ou obrigatórios
- [ ] Se usa criptografia em trânsito (Firebase/Auth usa HTTPS – sim)

### 2.4 Permissões
- [ ] Justificar cada permissão no Store Listing (se solicitado)
- [ ] `READ_CONTACTS` – seleção de clientes
- [ ] `POST_NOTIFICATIONS` – notificações
- [ ] `READ_MEDIA_IMAGES` – fotos de produtos
- [ ] Considerar `permission_handler` para pedir permissões em runtime (evita rejeição)

### 2.5 Conteúdo do app
- [ ] Classificação etária (geralmente 3+ ou 12+)
- [ ] Declaração de conteúdo sensível (pagamentos, dados pessoais)
- [ ] Screenshots (mínimo 2, recomendado 8)
- [ ] Ícone 512x512
- [ ] Vídeo curto (opcional, recomendado)

---

## 3. SEGURANÇA E PROTEÇÃO (o que já está feito)

| Item | Status |
|------|--------|
| App Check (Play Integrity) | ✅ Implementado |
| Rate limiting nas APIs | ✅ Implementado |
| Idempotência (webhook, cupom) | ✅ Implementado |
| Firestore Rules | ✅ Implementadas |
| ProGuard/R8 | ✅ Habilitado |
| Webhook MP (estoque + variações) | ✅ Corrigido |

### 3.1 Firestore / App Check
- [ ] **No Firebase Console:** App Check ativado para Firestore
- [ ] **Enforcement:** Habilitar enforcement após período de teste
- [ ] Tokens de debug somente em build debug

### 3.2 Backend (Cloud Functions)
- [ ] Deploy das functions: `firebase deploy --only functions`
- [ ] Webhook Mercado Pago configurado na URL correta
- [ ] Variáveis de ambiente (MP token, etc.) configuradas
- [ ] Monitorar logs: Firebase Console → Functions → Logs

---

## 4. ESTABILIDADE E MONITORAMENTO

### 4.1 Crashlytics (recomendado)
- [ ] Adicionar `firebase_crashlytics` ao projeto
- [ ] Enviar crashes e erros não tratados
- [ ] Útil para detectar problemas em produção

### 4.2 Tratamento de erros
- [ ] Try/catch em operações críticas (login, checkout, sync)
- [ ] Mensagens amigáveis ao usuário (não expor stack trace)
- [ ] Fallback quando offline (sync quando reconectar)

### 4.3 Testes manuais prioritários
- [ ] Login / Cadastro
- [ ] Nova venda completa
- [ ] Checkout via catálogo (Mercado Pago)
- [ ] Webhook MP (testar pagamento aprovado)
- [ ] Troca de loja / multi-tenant
- [ ] Deep links (link de pedido abre o app)
- [ ] Notificações push
- [ ] Uso offline básico

---

## 5. LEGAL E LGPD

### 5.1 Documentos
- [ ] Política de Privacidade publicada
- [ ] Termos de Uso (se aplicável)
- [ ] Contrato de adesão (já existe em `assets/contrato_adesao.md`)

### 5.2 Na prática
- [ ] Consentimento explícito para coleta de dados sensíveis
- [ ] Opção de exclusão de conta/dados
- [ ] Encriptação em trânsito (HTTPS) – Firebase já faz

---

## 6. PÓS-LANÇAMENTO

### 6.1 Monitorar
- [ ] Avaliações e comentários na Play Store
- [ ] Taxa de crash (Crashlytics)
- [ ] Uso de APIs (Firebase Console, Cloud Functions)
- [ ] Custos Firebase (alertas de orçamento)

### 6.2 Atualizações
- [ ] Versionamento: `version: 1.0.0+1` (nome + versionCode)
- [ ] Ao publicar nova versão: incrementar `versionCode` obrigatoriamente
- [ ] **Web:** rodar `dart run tool/sync_web_version.dart` antes do deploy para sincronizar manifest/index com pubspec

---

## 7. COMANDOS ÚTEIS

### Gerar APK release
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release
# APK em: build/app/outputs/flutter-apk/app-release.apk
```

### Gerar App Bundle (recomendado para Play Store)
```bash
flutter build appbundle --release
# AAB em: build/app/outputs/bundle/release/app-release.aab
```

### Verificar assinatura
```bash
# Ver se key.properties existe
ls -la android/key.properties  # Linux/Mac
dir android\key.properties    # Windows
```

---

## 8. RESUMO – O QUE FALTA FAZER

| Prioridade | Item |
|------------|------|
| 🔴 Obrigatório | Política de Privacidade (URL pública) |
| 🔴 Obrigatório | Data Safety no Console |
| 🔴 Obrigatório | `key.properties` para assinatura release |
| 🟠 Recomendado | Crashlytics |
| 🟠 Recomendado | App Check enforcement no Firebase |
| 🟠 Recomendado | Testes manuais completos |
| 🟡 Opcional | Remover prints de debug |
| 🟡 Opcional | Vídeo e mais screenshots |

---

## 9. LINKS ÚTEIS

- [Política do desenvolvedor Google Play](https://play.google.com/about/developer-content-policy/)
- [Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- [App Check](https://firebase.google.com/docs/app-check)
- [Firebase Console](https://console.firebase.google.com)

---

*Documento criado em 12/02/2026.*
