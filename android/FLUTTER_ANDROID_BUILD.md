# Build Android – Flutter 3.24.0 via FVM

A pasta `android/` foi alinhada ao **template do Flutter 3.24.0** (Groovy, AGP 7.3, Gradle 8.5) para evitar o erro "afterEvaluate when project already evaluated" que ocorre no Flutter 3.41+ com AGP 9.

> **Importante:** Use **FVM** com Flutter 3.24.0 para build Android: `fvm flutter run` ou `fvm flutter build apk --debug`. Código Dart que use APIs mais novas (ex.: `Color.withValues`) precisa ser ajustado para Flutter 3.24 (ex.: `withOpacity`) se o build falhar na compilação Dart.

## O que está configurado (template Flutter 3.24)

- **settings.gradle** (Groovy): plugin-management, includeBuild Flutter, AGP 7.3.0, Kotlin 1.7.10, google-services 4.3.15, crashlytics 2.9.9
- **build.gradle** (root, Groovy): ext flutter para plugins, allprojects, subprojects, evaluationDependsOn(":app"), task clean
- **app/build.gradle** (Groovy): plugins (Android, Kotlin, Flutter, Firebase), namespace/applicationId com.masterpalm.app, compileSdk 34, minSdk 21, targetSdk 34, signingConfigs, buildTypes, desugaring, Crashlytics workaround
- **gradle-wrapper.properties:** Gradle 8.5 (compatível com Java 21)
- **gradle.properties:** jvmargs, useAndroidX, enableJetifier

Testado sem sucesso: opt-out em `settings.gradle.kts`, env `ORG_GRADLE_PROJECT_android_newDsl`, remoção do loader (passa do afterEvaluate mas quebra `GeneratedPluginRegistrant` por falta dos plugins).

## Solução adotada: FVM com Flutter 3.24.0

O projeto usa **FVM** para rodar com Flutter 3.24.0 neste repositório, contornando a incompatibilidade do Flutter 3.41 com AGP 9.

### Opção 1: Downgrade do Flutter (se não precisar das últimas mudanças do SDK)

```powershell
# Cuidado: remove alterações locais no SDK do Flutter
flutter downgrade --force
```

Depois:

```powershell
flutter clean
flutter pub get
flutter run
```

### Opção 2: FVM (Flutter Version Management) – **configuração já presente no projeto**

O projeto já possui `.fvmrc` configurado para Flutter 3.24.0. Execute:

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty
fvm install 3.24.0
fvm use 3.24.0
fvm flutter clean
fvm flutter pub get
fvm flutter run
# ou: fvm flutter build apk --debug
```

### Opção 3: Canal stable anterior

```powershell
flutter channel
git -C <caminho_do_flutter> fetch
git -C <caminho_do_flutter> checkout 3.24.0
flutter --version
flutter run
```

## Referências

- https://docs.flutter.dev/release/breaking-changes/migrate-to-agp-9
- https://github.com/flutter/flutter/issues/180899
