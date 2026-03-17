# Patch: Correção do crash Firestore (NoSuchMethodException: *.values [])

## Causas identificadas

| Causa | Descrição |
|-------|-----------|
| **R8/ProGuard** | Com `minifyEnabled=true`, o R8 remove o método `values()` dos enums usados por reflexão pelo Firestore/gRPC. O erro `NoSuchMethodException: D2.J0.values []` ocorre porque `D2.J0` são nomes ofuscados de enums do protobuf. |
| **Protobuf/gRPC** | O Firestore usa gRPC para comunicação; os enums gerados pelo protobuf precisam de `values()` e `valueOf()` para reflexão. Sem regras ProGuard, o R8 os remove. |

## Arquivos alterados

### 1. `android/app/proguard-rules.pro`

**Diff:**

```diff
 # Hive
 -keep class ** extends com.google.protobuf.GeneratedMessageLite { *; }

+# =============================================================================
+# Firestore + gRPC + Protobuf - evita NoSuchMethodException: *.values []
+# O R8 remove métodos de enum usados por reflexão no Firestore. Manter enums.
+# =============================================================================
+
+# Enums: preservar values() e valueOf() usados por protobuf/gRPC
+-keepclassmembers enum * {
+    public static **[] values();
+    public static ** valueOf(java.lang.String);
+}
+
+# Protobuf - classes geradas e runtime
+-keep class com.google.protobuf.** { *; }
+-keep class com.google.protobuf.GeneratedMessageLite { *; }
+-keep class com.google.protobuf.GeneratedMessageLite$Builder { *; }
+
+# gRPC - Firestore usa gRPC para comunicação
+-keep class io.grpc.** { *; }
+-keep class io.grpc.android.** { *; }
+
+# Firestore remote - camada gRPC
+-keep class com.google.firebase.firestore.remote.** { *; }
+
+# gRPC OkHttp - referências a OkHttp 3.x (evita erro R8 Missing class)
+-dontwarn com.squareup.okhttp.CipherSuite
+-dontwarn com.squareup.okhttp.ConnectionSpec
+-dontwarn com.squareup.okhttp.TlsVersion
```

### 2. `android/gradle.properties` — sem alterações

Mantido como está. Não usar `android.enableR8.fullMode=true` (torna o R8 mais agressivo).

### 3. `android/build.gradle.kts` e `android/app/build.gradle.kts` — sem alterações

Não foi necessário `resolutionStrategy` nem BOM. O problema era apenas minificação.

---

## Passo a passo de build e instalação

### 1. Limpar caches

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty

flutter clean
cd android
.\gradlew clean
cd ..
```

### 2. Obter dependências

```powershell
flutter pub get
```

### 3. Build release

```powershell
flutter build apk --release
```

Ou para App Bundle (Play Store):

```powershell
flutter build appbundle --release
```

### 4. Instalar no dispositivo

```powershell
flutter install --release
```

Ou instalar o APK manualmente:

```
build\app\outputs\flutter-apk\app-release.apk
```

---

## Como confirmar no logcat que o Firestore inicializa sem crash

### 1. Conectar o dispositivo via USB

### 2. Limpar o logcat e abrir o app

```powershell
adb logcat -c
adb logcat | findstr "Firestore Firebase flutter"
```

### 3. Abrir o app no dispositivo

### 4. Verificar no logcat

- **Sucesso:** não deve aparecer `FATAL EXCEPTION` nem `NoSuchMethodException`.
- **Firestore OK:** podem aparecer logs como `Firestore` ou `GrpcCallProvider` sem exceções.

### 5. Se ainda houver crash

```powershell
adb logcat *:E
```

Envie o trecho do log com o stack trace para análise.

---

## Fallback: desativar minificação para validar

Se o crash continuar após o patch, teste sem minificação para confirmar que o problema é o R8:

Em `android/app/build.gradle.kts`, altere temporariamente:

```kotlin
buildTypes {
    release {
        // ...
        isMinifyEnabled = false   // era true
        isShrinkResources = false
        // ...
    }
}
```

Se o app funcionar com `isMinifyEnabled = false`, o problema é minificação e as regras ProGuard precisam ser ajustadas. Reverta para `true` e revise as regras.

---

## Resumo das alterações

| Arquivo | Alteração |
|---------|-----------|
| `android/app/proguard-rules.pro` | Regras para preservar enums, protobuf e gRPC usados pelo Firestore |

Nenhuma alteração em: `pubspec.yaml`, `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`.
