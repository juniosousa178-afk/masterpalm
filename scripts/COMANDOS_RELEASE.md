# MasterPalm – Comandos de Release Completo

## Versão atual no pubspec

```
1.0.29+39
```

---

## Opção 1: Script automático (recomendado)

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty
.\scripts\release-completo.ps1
```

- Incrementa versão automaticamente  
- Build web + APK + AAB  
- Copia APK para downloads  
- Exibe instruções de publicação  

Com parâmetros:
```powershell
.\scripts\release-completo.ps1 -Versao "1.0.30+40"
.\scripts\release-completo.ps1 -SkipPlayStore
```

---

## Opção 2: Comandos manuais

### 1. Atualizar versão no pubspec.yaml

Edite `pubspec.yaml`:
```yaml
version: 1.0.29+39   # incremente: 1.0.30+40
```

### 2. Preparar projeto

```powershell
fvm flutter pub get
fvm flutter clean
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart run tool/sync_web_version.dart
```

### 3. Build Web (app web + mobile web + desktop + catálogo online)

```powershell
fvm flutter build web --release
```

### 4. Build APK (Android instalável direto)

```powershell
fvm flutter build apk --release
```

Copiar APK para downloads:
```powershell
Copy-Item build\app\outputs\flutter-apk\app-release.apk build\web\downloads\masterpalm.apk
```

### 5. Build AAB (Play Store)

```powershell
fvm flutter build appbundle --release
```

Arquivo gerado: `build\app\outputs\bundle\release\app-release.aab`

### 6. Publicar no Firebase (Web + APK para download)

```powershell
firebase deploy --only hosting
```

Publica em:
- **App Web**: https://mastepalm.com.br
- **Mobile Web**: mesmo URL (responsivo)
- **Desktop Web**: mesmo URL
- **Catálogo online**: https://mastepalm.com.br/c/SEU-SLUG
- **Download APK**: https://mastepalm.com.br/downloads/masterpalm.apk

### 7. Publicar no Play Store

1. Acesse: https://play.google.com/console  
2. Selecione o app **MasterPalm**  
3. **Produção** → **Criar nova versão**  
4. Faça upload do arquivo: `build\app\outputs\bundle\release\app-release.aab`  
5. Preencha as notas da versão e publique  

### 8. (Opcional) Functions, Firestore, Storage

```powershell
firebase deploy --only functions
firebase deploy --only firestore:rules
firebase deploy --only storage
```

ou tudo de uma vez:
```powershell
firebase deploy
```

---

## Resumo – checklist de release

| Canal            | Comando / Ação                                                |
|------------------|---------------------------------------------------------------|
| Web (app)        | `fvm flutter build web` + `firebase deploy --only hosting`   |
| Mobile Web       | mesmo build web                                               |
| Desktop Web      | mesmo build web                                               |
| Catálogo Online  | mesmo build web (rota /c/**)                                  |
| APK direto       | `fvm flutter build apk` → copiar para build/web/downloads    |
| Play Store       | `fvm flutter build appbundle` → upload no Google Play Console |
| Firebase Hosting | `firebase deploy --only hosting`                              |
