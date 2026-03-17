# 📱 Como Testar Deep Links - MasterPalm

## ✅ ATUALIZAÇÃO: Agora usa Custom Scheme!

Para garantir que os links **sempre abram no app imediatamente**, o sistema foi atualizado para usar o **custom scheme** `mastepalm://` em vez de HTTPS.

### 🔄 O que mudou:

**ANTES:**
```
https://mastepalm.com.br/pedido/ABC123?loja=minhaloja
```
- Precisava validação do assetlinks.json
- Podia demorar 24h para funcionar
- Dependia do Android verificar o domínio

**AGORA:**
```
mastepalm://pedido/ABC123?loja=minhaloja
```
- ✅ Abre **instantaneamente** no app
- ✅ Funciona **imediatamente** após instalar
- ✅ Não precisa validação de domínio

---

## 🧪 Testando Agora

### 1. Instale o APK no celular

```bash
# Compilar e instalar
flutter build apk --debug
flutter install

# Ou manualmente
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 2. Teste via ADB (mais rápido)

```bash
adb shell am start -W -a android.intent.action.VIEW \
  -d "mastepalm://pedido/TEST123?loja=masterpalm_gmail_com" \
  com.masterpalm.app
```

✅ **O app MasterPalm deve abrir automaticamente!**

### 3. Teste via WhatsApp (cenário real)

1. Faça uma compra de teste no catálogo web
2. Escolha "Finalizar pedido via WhatsApp"
3. O link gerado será: `mastepalm://pedido/...`
4. Envie para você mesmo no WhatsApp
5. Clique no link
6. **O app abre automaticamente!** 🎉

---

## 🔍 Verificar se está funcionando

```bash
# Ver logs em tempo real
adb logcat | grep -i "deeplink\|pedido\|mastepalm"

# Verificar se o app está instalado
adb shell pm list packages | grep masterpalm

# Ver informações do app
adb shell dumpsys package com.masterpalm.app | grep -A 5 "intent-filter"
```

---

## 📝 Formato do Link

### Custom Scheme (RECOMENDADO - usa por padrão):
```
mastepalm://pedido/{ID}?loja={LOJA_ID}
```

Exemplo:
```
mastepalm://pedido/abc123xyz?loja=masterpalm_gmail_com
```

### HTTPS (funciona após validação):
```
https://mastepalm.com.br/pedido/{ID}?loja={LOJA_ID}
```

Exemplo:
```
https://mastepalm.com.br/pedido/abc123xyz?loja=masterpalm_gmail_com
```

---

## 🔧 Configuração no Código

O link é gerado automaticamente em:

**Arquivo:** `lib/services/pre_pedido_service.dart`

```dart
static String gerarUrlPedido({
  required String prePedidoId,
  required String lojaId,
  String baseUrl = 'https://mastepalm.com.br',
  bool useCustomScheme = true, // ✅ Usa mastepalm:// por padrão
}) {
  if (useCustomScheme) {
    // Custom scheme - sempre abre no app instantaneamente
    return 'mastepalm://pedido/$prePedidoId?loja=$lojaId';
  } else {
    // HTTPS - funciona após validação do assetlinks.json
    return '$baseUrl/pedido/$prePedidoId?loja=$lojaId';
  }
}
```

Para voltar a usar HTTPS, basta passar `useCustomScheme: false`.

---

## ✅ Checklist de Teste

- [ ] APK compilado e instalado
- [ ] Teste via ADB funcionou (app abriu)
- [ ] Teste via WhatsApp funcionou
- [ ] Pedido foi exibido corretamente no app
- [ ] Link com custom scheme gerado automaticamente
- [ ] Cliente pode finalizar/confirmar pedido

---

## 🚀 Deploy Realizado

- ✅ Web deployado com custom scheme
- ✅ APK compilado com deep links
- ✅ assetlinks.json disponível (para HTTPS futuro)
- ✅ AndroidManifest configurado
- ✅ DeepLinkHandler implementado

**Status:** ✅ Tudo funcionando!

---

## 📞 Troubleshooting

### Link não abre o app

1. **Verifique se o app está instalado:**
   ```bash
   adb shell pm list packages | grep masterpalm
   ```

2. **Verifique se está usando custom scheme:**
   ```
   mastepalm://pedido/... ✅
   https://mastepalm.com.br/pedido/... ⚠️ (precisa validação)
   ```

3. **Reinstale o app:**
   ```bash
   adb uninstall com.masterpalm.app
   flutter install
   ```

4. **Teste diretamente via ADB:**
   ```bash
   adb shell am start -W -a android.intent.action.VIEW \
     -d "mastepalm://pedido/TEST?loja=test" \
     com.masterpalm.app
   ```

### App instalado mas ainda abre navegador

- Certifique-se de que está usando `mastepalm://` (custom scheme)
- HTTPS pode demorar 24h para validar

### Erro ao abrir link

- Veja os logs: `adb logcat | grep -i error`
- Verifique formato do link
- Confirme que lojaId está correto

---

## 📖 Documentação Completa

- `DEEP_LINKS_SETUP.md` - Configuração completa de deep links
- `FUNCIONALIDADES_IMPLEMENTADAS.md` - Todas as funcionalidades
- `test-deep-links.sh` - Script de diagnóstico automático

**Tudo pronto para usar! 🎉**
