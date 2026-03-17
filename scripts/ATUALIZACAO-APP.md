# Atualização automática do app MasterPalm

## Como funciona

1. **Ao abrir o app** – É feita uma verificação: se a versão no Firestore (`apkVersion` em site_config) for maior que a versão instalada, aparece um diálogo pedindo para atualizar.

2. **Notificação push** – Quando você altera a versão em **Configurar Site** e salva, uma Cloud Function envia uma notificação push para todos os usuários inscritos no tópico. Ao tocar na notificação, o app abre e mostra o diálogo de atualização.

3. **Ao tocar em "Atualizar"** – O link de download do APK é aberto (navegador). O usuário baixa e instala o APK manualmente.

## O que você precisa fazer ao lançar uma nova versão

### 1. Atualizar o pubspec.yaml
```yaml
version: 1.0.1+2   # incrementar
```

### 2. Fazer build e deploy
```powershell
.\scripts\build-installer-hosting.ps1
firebase deploy
```

### 3. Atualizar a configuração no app
- Abra o app → Configurar Site (menu admin)
- Atualize o campo **Versão** para a nova versão (ex: 1.0.1)
- Preencha **Novidades da atualização** com as melhorias e correções (exibidas ao usuário no diálogo de atualização)
- Clique em **Salvar configurações**

Ao salvar, a Cloud Function `onSiteConfigUpdated` detecta a mudança de versão e envia a notificação push para todos os usuários. O diálogo de atualização exibirá as novidades e correções que você digitou.

## Arquivos criados/alterados

- `lib/services/app_update_service.dart` – Verificação de versão
- `lib/widgets/update_app_dialog.dart` – Diálogo de atualização
- `lib/widgets/update_check_wrapper.dart` – Wrapper que dispara a verificação
- `lib/services/fcm_pedido_service.dart` – Inscrição no tópico e tratamento da notificação
- `functions/index.js` – Cloud Function `onSiteConfigUpdated`
- `lib/main.dart` – Integração do `UpdateCheckWrapper`
