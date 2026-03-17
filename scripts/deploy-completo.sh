#!/bin/bash
# =============================================================================
# Script completo: build e deploy MasterPalm
# - App Web (catálogo + PWA)
# - APK Android (release) + cópia para download no site
# - Opcional: desktop (Windows/macOS/Linux) e análise estática
# =============================================================================

set -e

# Configuração
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Comando Flutter (use FVM se existir .fvm no projeto)
if [ -d ".fvm" ]; then
  FLUTTER_CMD="fvm flutter"
  DART_CMD="fvm dart"
else
  FLUTTER_CMD="flutter"
  DART_CMD="dart"
fi

# Opções
RUN_ANALYZE=false
BUILD_WEB=true
BUILD_APK=true
BUILD_DESKTOP=false
COPY_APK_TO_WEB=true
SYNC_VERSION=true
DEPLOY_HOSTING=false
FIREBASE_TARGET=""

usage() {
  echo "Uso: $0 [opções]"
  echo ""
  echo "Opções:"
  echo "  --analyze          Executa 'flutter analyze' antes (falha se houver erro)"
  echo "  --no-web           Não faz build web"
  echo "  --no-apk           Não faz build APK"
  echo "  --desktop          Faz build desktop (Windows/macOS/Linux conforme SO)"
  echo "  --no-copy-apk      Não copia APK para build/web/downloads (download no site)"
  echo "  --no-sync-version   Não sincroniza versão web (manifest.json, index.html)"
  echo "  --deploy           Faz 'firebase deploy --only hosting' ao final"
  echo "  --target=NOME      Usa Firebase target (ex: --target=mastepalm)"
  echo "  -h, --help         Mostra esta ajuda"
  echo ""
  echo "Exemplos:"
  echo "  $0                           # Só build web + APK, copia estáticos e APK"
  echo "  $0 --analyze --deploy        # Analisa, build, deploy hosting"
  echo "  $0 --no-apk --deploy         # Só web e deploy"
  echo "  $0 --desktop                 # Inclui build desktop"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --analyze)        RUN_ANALYZE=true ;;
    --no-web)         BUILD_WEB=false ;;
    --no-apk)         BUILD_APK=false ;;
    --desktop)        BUILD_DESKTOP=true ;;
    --no-copy-apk)    COPY_APK_TO_WEB=false ;;
    --no-sync-version) SYNC_VERSION=false ;;
    --deploy)         DEPLOY_HOSTING=true ;;
    --target=*)       FIREBASE_TARGET="${1#--target=}" ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "Opção desconhecida: $1"; usage; exit 1 ;;
  esac
  shift
done

echo "=============================================="
echo "  MasterPalm - Build e Deploy"
echo "=============================================="
echo "  Analisar:      $RUN_ANALYZE"
echo "  Build Web:     $BUILD_WEB"
echo "  Build APK:     $BUILD_APK"
echo "  Build Desktop: $BUILD_DESKTOP"
echo "  Copiar APK:    $COPY_APK_TO_WEB"
echo "  Sync versão:   $SYNC_VERSION"
echo "  Deploy:        $DEPLOY_HOSTING"
echo "=============================================="

# 1) Análise estática (opcional)
if [ "$RUN_ANALYZE" = true ]; then
  echo ""
  echo "🔍 Executando flutter analyze..."
  $FLUTTER_CMD analyze
  echo "✅ Análise concluída sem erros."
fi

# 2) Sincronizar versão web (pubspec -> manifest.json, index.html)
if [ "$SYNC_VERSION" = true ]; then
  echo ""
  echo "🔄 Sincronizando versão web com pubspec..."
  if [ -f "tool/sync_web_version.dart" ]; then
    $DART_CMD run tool/sync_web_version.dart
  else
    echo "⚠️ tool/sync_web_version.dart não encontrado; pulando sync de versão."
  fi
fi

# 3) Build Web (app + catálogo)
if [ "$BUILD_WEB" = true ]; then
  echo ""
  echo "🌐 Compilando Flutter Web (release)..."
  $FLUTTER_CMD build web --release
  echo "✅ Build web concluído."
fi

# 4) Arquivos estáticos para o hosting
echo ""
echo "📄 Copiando arquivos estáticos para build/web..."
mkdir -p build/web/.well-known
if [ -f "public/.well-known/assetlinks.json" ]; then
  cp public/.well-known/assetlinks.json build/web/.well-known/
  echo "  .well-known/assetlinks.json"
fi
if [ -f "public/privacidade.html" ]; then
  cp public/privacidade.html build/web/
  echo "  privacidade.html"
fi

# 5) Build APK e cópia para download no site
if [ "$BUILD_APK" = true ]; then
  echo ""
  echo "📱 Compilando APK Android (release)..."
  $FLUTTER_CMD build apk --release
  echo "✅ Build APK concluído."

  if [ "$COPY_APK_TO_WEB" = true ]; then
    mkdir -p build/web/downloads
    APK_SRC="build/app/outputs/flutter-apk/app-release.apk"
    if [ -f "$APK_SRC" ]; then
      cp "$APK_SRC" build/web/downloads/masterpalm.apk
      echo "  APK copiado para build/web/downloads/masterpalm.apk (disponível no site em /downloads/masterpalm.apk)"
    else
      echo "⚠️ APK não encontrado em $APK_SRC (caminho pode variar por versão do Flutter)"
      # Tentar caminho alternativo
      ALT="build/app/outputs/apk/release/app-release.apk"
      if [ -f "$ALT" ]; then
        cp "$ALT" build/web/downloads/masterpalm.apk
        echo "  APK copiado de $ALT"
      fi
    fi
  fi
fi

# 6) Build Desktop (opcional)
if [ "$BUILD_DESKTOP" = true ]; then
  echo ""
  echo "🖥️ Compilando desktop..."
  case "$(uname -s)" in
    Linux*)   $FLUTTER_CMD build linux --release ;;
    Darwin*)  $FLUTTER_CMD build macos --release ;;
    MINGW*|MSYS*|CYGWIN*) $FLUTTER_CMD build windows --release ;;
    *)        echo "⚠️ SO não suportado para desktop; pulando." ;;
  esac
  echo "✅ Build desktop concluído."
fi

# 7) Deploy Firebase Hosting (opcional)
if [ "$DEPLOY_HOSTING" = true ]; then
  echo ""
  echo "🚀 Fazendo deploy no Firebase Hosting..."
  if [ -n "$FIREBASE_TARGET" ]; then
    firebase deploy --only hosting:"$FIREBASE_TARGET"
  else
    firebase deploy --only hosting
  fi
  echo "✅ Deploy concluído!"
fi

echo ""
echo "=============================================="
echo "  Concluído"
echo "=============================================="
echo "  Web:       build/web (hosting em build/web)"
echo "  Catálogo:  acessível via /loja/<slug> e /c/<link-curto>"
if [ "$BUILD_APK" = true ]; then
  echo "  APK:       build/app/outputs/flutter-apk/app-release.apk"
  [ "$COPY_APK_TO_WEB" = true ] && echo "  Download:  após deploy, /downloads/masterpalm.apk"
fi
echo ""
echo "Para publicar no site: use --deploy ou execute:"
echo "  firebase deploy --only hosting"
echo ""
