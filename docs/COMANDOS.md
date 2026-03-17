# Comandos para o projeto funcionar 100%

Execute na pasta raiz do projeto: `c:\Users\Pichau\apk_nathy\temp_naty`

---

## 1. Pré-requisitos

- **Flutter** instalado e no PATH (`flutter doctor`)
- **Node.js 20** (para Cloud Functions)
- **Firebase CLI** (`npm install -g firebase-tools`)
- **Conta Firebase** e projeto configurado

---

## 2. Flutter – app

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty
```

### Instalar dependências
```powershell
flutter pub get
```

### Limpar e garantir cache
```powershell
flutter clean
flutter pub get
```

### Verificar ambiente
```powershell
flutter doctor
flutter doctor -v
```

### Analisar código (sem erros)
```powershell
flutter analyze
```

### Gerar código (Hive, etc.)
```powershell
dart run build_runner build --delete-conflicting-outputs
```

### Rodar o app

**Web (Chrome):**
```powershell
flutter run -d chrome
```

**Web (com release):**
```powershell
flutter run -d chrome --release
```

**Android:**
```powershell
flutter run -d android
```

**iOS (apenas em Mac):**
```powershell
flutter run -d ios
```

**Escolher dispositivo:**
```powershell
flutter devices
flutter run -d <device_id>
```

### Build para produção

**Web (para Firebase Hosting):**
```powershell
flutter build web --release
```

**Android APK:**
```powershell
flutter build apk --release
```

**Android App Bundle (Google Play):**
```powershell
flutter build appbundle --release
```

**iOS (apenas em Mac):**
```powershell
flutter build ios --release
```

---

## 3. Firebase

### Login e projeto
```powershell
firebase login
firebase use masterpalm-58c46
```
*(troque `masterpalm-58c46` pelo ID do seu projeto se for outro.)*

### Deploy completo (Hosting + Functions + Firestore rules, etc.)
```powershell
firebase deploy
```

### Só Hosting (app web)
```powershell
flutter build web --release
firebase deploy --only hosting
```

### Só Functions
```powershell
firebase deploy --only functions
```

### Só Firestore rules
```powershell
firebase deploy --only firestore:rules
```

### Só Storage rules
```powershell
firebase deploy --only storage
```

---

## 4. Cloud Functions (Node)

As functions ficam em `functions/` (e opcionalmente `main/`). Instale dependências e faça deploy pelo Firebase.

### Instalar dependências das functions
```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty\functions
npm install
cd ..
```

### Deploy das functions (a partir da raiz do projeto)
```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty
firebase deploy --only functions
```

### Emulador local (testar functions)
```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty
firebase emulators:start --only functions
```

---

## 5. Sequência “tudo 100%” (desenvolvimento)

Ordem sugerida para deixar tudo pronto para desenvolvimento e rodar o app:

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty

flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter run -d chrome
```

*(Para Android: use `flutter run -d android` no lugar da última linha.)*

---

## 6. Sequência “tudo 100%” (publicar web)

Para gerar o build web e publicar no Firebase Hosting:

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty

flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter build web --release
firebase use masterpalm-58c46
firebase deploy --only hosting
```

---

## 7. Sequência “tudo 100%” (app + backend)

Para app, hosting e functions:

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty

flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter build web --release

cd functions
npm install
cd ..

firebase use masterpalm-58c46
firebase deploy
```

---

## 8. Comandos úteis rápidos

| Objetivo              | Comando |
|-----------------------|--------|
| Só rodar app web      | `flutter run -d chrome` |
| Só rodar app Android  | `flutter run -d android` |
| Só analisar           | `flutter analyze` |
| Só dependências       | `flutter pub get` |
| Só build web         | `flutter build web --release` |
| Só deploy hosting    | `firebase deploy --only hosting` |
| Só deploy functions  | `firebase deploy --only functions` |
| Ver dispositivos      | `flutter devices` |

---

## 9. Problemas comuns

- **Erro de dependência:** `flutter clean` e depois `flutter pub get`.
- **Hive / generated:** rodar de novo `dart run build_runner build --delete-conflicting-outputs`.
- **Firebase “project not found”:** `firebase use <seu-project-id>`.
- **Functions falham no deploy:** em `functions/` rodar `npm install` e conferir Node 20.
- **Android build:** ter Android SDK e aceitar licenças (`flutter doctor --android-licenses`).

Se algo falhar, use a saída de `flutter doctor -v` e a mensagem de erro para depurar.
