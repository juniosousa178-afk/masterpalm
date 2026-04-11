# E2E — scheduler de downgrade (`scheduledExpiredPaidReconcile`)

## Erro: “Java version before 21”

O **Firebase Emulator Suite** (Firestore) passou a exigir **JDK 21 ou superior** no `firebase-tools` recente.

### Windows (rápido)

1. Instale o JDK 21, por exemplo:

   ```powershell
   winget install EclipseAdoptium.Temurin.21.JDK
   ```

2. Feche e reabra o terminal (ou reinicie o PC) e confira:

   ```powershell
   java -version
   ```

   Deve aparecer versão **21** ou superior.

3. Na **raiz do repositório** (onde está `firebase.json`), suba só o Firestore:

   ```powershell
   cd C:\Users\Pichau\apk_nathy\temp_naty
   firebase emulators:start --only firestore
   ```

4. Em **outro** terminal, na pasta `functions`:

   ```powershell
   cd C:\Users\Pichau\apk_nathy\temp_naty\functions
   npm run test:e2e:only
   ```

## Um comando (emulador + teste)

Com JDK 21+ configurado:

```powershell
cd C:\Users\Pichau\apk_nathy\temp_naty\functions
npm run test:e2e
```

(Isso usa `firebase emulators:exec` — ainda depende do mesmo JDK.)

## Pastas

- Já está em `...\temp_naty\functions` → **não** rode `cd functions` de novo (não existe `functions\functions`).

## O que o teste faz

Escreve `users/{uid}` no **emulador**, executa a **mesma query** de vencidos que o job, restringe o lote ao UID do cenário (contadores determinísticos), roda `runScheduledReconcileBatch` com **`computePlanState` real** (sem mock), valida o documento final e **apaga** o doc no `afterEach`.
