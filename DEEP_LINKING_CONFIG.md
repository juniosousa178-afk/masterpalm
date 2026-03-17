# Configuração de Deep Linking

## ✅ Configuração Atual (RECOMENDADA)

O app está configurado para usar **links HTTPS clicáveis** que abrem automaticamente no app quando instalado.

### Formato do Link
```
https://mastepalm.com.br/c/nathy-pratas-e-folheados?pedido=abc123
```

### Vantagens
- ✅ **Clicável no WhatsApp** - aparece como link azul
- ✅ **Abre no app automaticamente** quando instalado
- ✅ **Funciona no navegador** como fallback
- ✅ **Compatível com compartilhamento** em redes sociais

---

## Como Funciona

### 1. Link é Enviado no WhatsApp
Formato: `https://mastepalm.com.br/c/nathy-pratas-e-folheados?pedido=abc123`

### 2. Usuário Clica no Link
- Se o app estiver instalado → Abre direto no app
- Se o app não estiver instalado → Abre no navegador web

### 3. App Intercepta o Link
O AndroidManifest está configurado para capturar links do domínio `mastepalm.com.br`

---

## Configuração Anterior (Custom Scheme)

Anteriormente, o app usava custom scheme que **não era clicável** no WhatsApp.

### Por que foi alterado?

O WhatsApp não reconhece custom schemes (`mastepalm://`) como links clicáveis, aparecendo apenas como texto normal.

## Solução 1: Usar Esquema Customizado (Mais Simples)

### Como funciona:
Links no formato `mastepalm://pedido/...` sempre abrem no app, sem necessidade de verificação.

### Configuração no WhatsApp:

Modificar o link enviado para usar o esquema customizado:

```dart
// Ao invés de:
https://mastepalm.com.br/c/nathy-pratas-e-folheados?pedido=abc123

// Usar:
mastepalm://pedido/abc123?loja=nathy-pratas-e-folheados
```

### Vantagens:
- ✅ Funciona imediatamente, sem configuração de servidor
- ✅ Sempre abre no app
- ✅ Não requer domínio configurado

### Desvantagens:
- ❌ Não funciona se o app não estiver instalado
- ❌ Link não pode ser aberto em navegador web

---

## Solução 2: Configurar App Links Verificados (Recomendado)

### O que é necessário:

1. **Arquivo `.well-known/assetlinks.json` no servidor**

Criar o arquivo em: `https://mastepalm.com.br/.well-known/assetlinks.json`

Conteúdo do arquivo:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.masterpalm.app",
      "sha256_cert_fingerprints": [
        "COLE_AQUI_O_SHA256_DO_SEU_CERTIFICADO"
      ]
    }
  }
]
```

2. **Obter o SHA256 do certificado**

```bash
# Para release (keystore de produção):
keytool -list -v -keystore android/app/upload-keystore.jks -alias upload

# Para debug:
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Copie o SHA256 (tem formato: `AB:CD:EF:12:34...`)

3. **Configurar o servidor**

- Fazer upload do arquivo `assetlinks.json` para a pasta `.well-known/` no servidor
- Garantir que o arquivo é acessível em: `https://mastepalm.com.br/.well-known/assetlinks.json`
- O arquivo deve retornar `Content-Type: application/json`

### Vantagens:
- ✅ Links funcionam tanto no app quanto no navegador
- ✅ Melhor experiência do usuário
- ✅ Links podem ser compartilhados

### Desvantagens:
- ❌ Requer acesso ao servidor
- ❌ Requer configuração adicional

---

## Solução Atual no App

O app **já está configurado** para ambas as soluções:

### AndroidManifest.xml (linhas 64-82):

```xml
<!-- HTTPS App Links -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="mastepalm.com.br" />
    <data android:scheme="https" android:host="mastepalm.com.br" android:pathPrefix="/pedido" />
    <data android:scheme="https" android:host="www.mastepalm.com.br" />
    <data android:scheme="https" android:host="www.mastepalm.com.br" android:pathPrefix="/pedido" />
</intent-filter>

<!-- Esquema customizado -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="mastepalm" android:host="pedido" />
</intent-filter>
```

---

## Recomendação

**Use a Solução 1 (Esquema Customizado)** se:
- Você não tem acesso ao servidor web
- Precisa de uma solução rápida
- Os links são enviados apenas via WhatsApp/SMS

**Use a Solução 2 (App Links Verificados)** se:
- Você tem acesso ao servidor
- Quer que os links funcionem também no navegador
- Planeja compartilhar links em redes sociais

---

## Como Modificar o Código para Usar Esquema Customizado

No arquivo `lib/services/pre_pedido_service.dart`, modificar:

```dart
static String gerarUrlPedido({
  required String prePedidoId,
  required String lojaId,
  String baseUrl = 'https://mastepalm.com.br',
  bool useCustomScheme = true, // MUDAR PARA true
}) {
  if (useCustomScheme) {
    return 'mastepalm://pedido/$prePedidoId?loja=$lojaId';
  } else {
    return '$baseUrl/admin/pedidos?id=$prePedidoId&loja=$lojaId';
  }
}
```

Ou passar `useCustomScheme: true` ao chamar a função.
