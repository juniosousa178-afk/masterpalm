# Ponto de restauração – MasterPalm

**Data:** Março 2026  
**Status:** ✅ Build Android funcionando com FVM Flutter 3.24.0

---

## Ambiente que funciona

| Item | Versão |
|------|--------|
| **Flutter (FVM)** | 3.24.0 |
| **FVM** | 3.2.1 (`dart pub global activate fvm`) |
| **Dart** | 3.5.0 (via Flutter 3.24) |
| **Gradle** | 8.13 |
| **AGP** | 8.11.1 |
| **Kotlin** | 2.2.20 |
| **NDK** | 27.0.12077973 |
| **minSdk** | 23 (Firebase exige 23+) |
| **compileSdk** | 36 |
| **targetSdk** | 35 |

---

## Dependências críticas (pubspec.yaml)

```yaml
path: ^1.9.0          # flutter_test exige 1.9.0
intl: ^0.19.0         # flutter_localizations exige 0.19.0

dependency_overrides:
  collection: 1.18.0
  meta: 1.15.0
  http_parser: 4.0.2
  font_awesome_flutter: 10.4.0
```

**APIs usadas para Flutter 3.24:**
- `Color.withOpacity(x)` — **não** usar `withValues(alpha: x)` (inexistente em 3.24)
- `DropdownButtonFormField(value: x)` — **não** usar `initialValue`
- `CardTheme` e `DialogTheme` — **não** usar CardThemeData/DialogThemeData
- `Matrix4.scale(x, y, z)` — **não** usar scaleByDouble em vector_math
- `RadioListTile(groupValue:, onChanged:)` — **não** usar RadioGroup

---

## Estrutura Android (Kotlin DSL .kts)

O projeto usa **arquivos .kts** (Kotlin DSL), não .gradle (Groovy).

**Arquivos principais:**
- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/app/build.gradle.kts`
- `android/flutter_plugin_ext.gradle` ← **obrigatório** (ext.flutter para plugins)

---

## Procedimento de restauração

### 1. FVM / Flutter

```bash
# Reativar FVM (se erro "Can't load Kernel binary")
dart pub global activate fvm

# Usar Flutter 3.24 via FVM
fvm use 3.24.0
fvm flutter pub get
```

### 2. Dependências Dart

Se houver conflitos em `flutter pub get`, conferir:
- `path: ^1.9.0`
- `intl: ^0.19.0`

### 3. Build Android

Se plugins (ex.: app_links) reclamarem de `flutter.compileSdkVersion`, garantir que exista `android/flutter_plugin_ext.gradle` e que o root `build.gradle.kts` o aplique:

```kotlin
apply(from = "flutter_plugin_ext.gradle")
```

### 4. NDK

Se aparecer "plugins require Android NDK 27.x", em `android/app/build.gradle.kts`:

```kotlin
ndkVersion = "27.0.12077973"
```

### 5. minSdk

Se houver erro de `firebase-auth` exigindo minSdk 23:

```kotlin
minSdk = 23
```

E em `android/flutter_plugin_ext.gradle`:

```groovy
minSdkVersion: 23,
```

### 6. APIs Dart / Flutter 3.24

Se surgirem erros de API:

| Erro | Ajuste |
|------|--------|
| `withValues` não existe | trocar por `withOpacity(x)` |
| `initialValue` não existe em DropdownButtonFormField | trocar por `value` |
| `CardThemeData` não existe | trocar por `CardTheme` |
| `DialogThemeData` não existe | trocar por `DialogTheme` |
| `scaleByDouble` não existe (vector_math) | trocar por `scale(x, y, z)` |
| `RadioGroup` não existe | usar `RadioListTile` com `groupValue` e `onChanged` |

---

## Conteúdo do flutter_plugin_ext.gradle

```groovy
gradle.beforeProject { subproj ->
    if (subproj.name != "app" && subproj != rootProject) {
        subproj.ext.flutter = [
            compileSdkVersion: 36,
            minSdkVersion: 23,
            targetSdkVersion: 35,
            ndkVersion: "25.1.8937393",
            versionCode: 1,
            versionName: "1.0"
        ]
    }
}
```

---

## Comandos para build e execução

```bash
# Resolver dependências
fvm flutter pub get

# Limpar e rodar
fvm flutter clean
fvm flutter pub get
fvm flutter run
```

---

## Backup sugerido

Para ter um ponto de restauração real:

```bash
# Criar commit de restauração
git add .
git commit -m "Ponto de restauração: build Flutter 3.24 Android funcionando"
```

Ou copiar a pasta do projeto para outro diretório antes de alterações grandes.
