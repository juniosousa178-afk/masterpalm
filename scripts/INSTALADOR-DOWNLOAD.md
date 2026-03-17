# Instalador MasterPalm - Download e hospedagem no site mastepalm.com.br

## O que foi criado

1. **`scripts/build-installer-hosting.ps1`** – Script que gera o APK e prepara tudo para o deploy
2. **`web/download.html`** – Página de download para o site
3. **Configuração Firebase** – Headers para o APK (veja abaixo se precisar configurar manualmente)

---

## Como usar

### 1. Gerar o instalador e preparar para deploy

Execute na raiz do projeto (PowerShell):

```powershell
.\scripts\build-installer-hosting.ps1
```

O script vai:
- Rodar `flutter pub get`
- Gerar o APK (release)
- Gerar o build web
- Copiar o APK para `build/web/downloads/masterpalm.apk`
- Copiar a página de download para `build/web/download.html`

### 2. Publicar no Firebase (mastepalm.com.br)

```powershell
firebase deploy
```

Ou só o hosting:

```powershell
firebase deploy --only hosting
```

---

## URLs após o deploy

- **Página de download:** `https://mastepalm.com.br/download.html` (ou app.mastepalm.com.br)
- **Link direto do APK:** `https://mastepalm.com.br/downloads/masterpalm.apk`

---

## Headers do APK (Firebase Hosting)

Para garantir que o APK seja baixado (e não exibido no navegador), adicione no `firebase.json` na seção `headers` de cada target de hosting:

```json
{
  "source": "/downloads/*.apk",
  "headers": [
    {"key": "Content-Type", "value": "application/vnd.android.package-archive"},
    {"key": "Content-Disposition", "value": "attachment; filename=\"masterpalm.apk\""}
  ]
}
```

O `firebase.json` deve ficar assim em cada bloco de hosting (exemplo):

```json
"headers": [
  {"source": "/.well-known/assetlinks.json", "headers": [{"key": "Content-Type", "value": "application/json"}]},
  {"source": "/downloads/*.apk", "headers": [
    {"key": "Content-Type", "value": "application/vnd.android.package-archive"},
    {"key": "Content-Disposition", "value": "attachment; filename=\"masterpalm.apk\""}
  ]}
]
```

---

## Resumo

| Passo | Comando |
|-------|---------|
| 1. Build instalador | `.\scripts\build-installer-hosting.ps1` |
| 2. Deploy no site | `firebase deploy` |
