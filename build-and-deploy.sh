#!/bin/bash
# Script para build e deploy do MasterPalm

echo "🔄 Sincronizando versão web com pubspec..."
fvm dart run tool/sync_web_version.dart

echo "🔨 Compilando Flutter Web..."
fvm flutter build web --release

echo "📄 Copiando arquivos estáticos..."
mkdir -p build/web/.well-known
cp public/.well-known/assetlinks.json build/web/.well-known/
[ -f public/privacidade.html ] && cp public/privacidade.html build/web/

echo "🚀 Fazendo deploy no Firebase Hosting..."
firebase deploy --only hosting

echo "✅ Deploy concluído!"
echo "📱 Para testar deep links no Android:"
echo "   1. Compile e instale o APK: fvm flutter build apk --release"
echo "   2. Instale no dispositivo"
echo "   3. Clique em um link https://mastepalm.com.br/pedido/XXXXX"
echo "   4. O app MasterPalm deve abrir automaticamente"
