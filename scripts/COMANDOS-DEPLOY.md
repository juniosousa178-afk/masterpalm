# Comandos para tudo funcionar 100% – MasterPalm

Use o script **`build-e-deploy-tudo.ps1`** para rodar tudo de uma vez, ou execute os comandos abaixo na ordem (na raiz do projeto).

---

## Pré-requisitos

- **Flutter** instalado e no PATH (`flutter doctor`)
- **Node.js** (LTS) e **npm** instalados
- **Firebase CLI**: `npm install -g firebase-tools` e `firebase login`

---

## 1. Dependências Flutter

```powershell
flutter pub get
```

---

## 2. Dependências Cloud Functions

```powershell
cd functions
npm install
cd ..

cd main
npm install
cd ..
```

*(Se a pasta `main` não existir, pule esse `cd main`.)*

---

## 3. Build Web (catálogo online / app web)

```powershell
flutter build web --release
```

Saída em: `build/web` (usado pelo Firebase Hosting)

---

## 4. Build Android (APK)

```powershell
flutter build apk --release
```

APK gerado em: `build/app/outputs/flutter-apk/app-release.apk`

*(Opcional – App Bundle para Play Store: `flutter build appbundle --release`)*

---

## 5. Deploy Firebase (regras + functions + hosting)

```powershell
firebase deploy
```

Isso publica:

- **Firestore rules** – segurança do banco
- **Cloud Functions** – notificações, webhooks, etc.
- **Hosting** – catálogo online (site público)

---

## Resumo em uma linha (PowerShell, na raiz)

Para quem quiser rodar tudo manualmente em sequência:

```powershell
flutter pub get; cd functions; npm install; cd ..; flutter build web --release; flutter build apk --release; firebase deploy
```

*(Ajuste se tiver pasta `main`: inclua `cd main; npm install; cd ..` antes do build web.)*

---

## Uso do script

Na raiz do projeto:

```powershell
.\scripts\build-e-deploy-tudo.ps1
```

- Só instalar deps: `.\scripts\build-e-deploy-tudo.ps1 -ApenasSetup`
- Só build, sem deploy: `.\scripts\build-e-deploy-tudo.ps1 -SemDeploy`
- Sem build web: `.\scripts\build-e-deploy-tudo.ps1 -SemWeb`
- Sem build Android: `.\scripts\build-e-deploy-tudo.ps1 -SemApk`

Com isso, **catálogo online**, **app web**, **aplicativo Android** e **todas as plataformas do sistema** ficam cobertas por um único fluxo.
