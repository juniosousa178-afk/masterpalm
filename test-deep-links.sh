#!/bin/bash
# Script para testar e debugar deep links no Android

echo "🔍 DIAGNÓSTICO DE DEEP LINKS - MasterPalm"
echo "=========================================="
echo ""

# 1. Verificar se o dispositivo está conectado
echo "1️⃣ Verificando dispositivo Android..."
if ! adb devices | grep -q "device$"; then
    echo "❌ Nenhum dispositivo Android conectado!"
    echo "   Conecte um dispositivo ou inicie um emulador"
    exit 1
fi
echo "✅ Dispositivo conectado"
echo ""

# 2. Verificar se o app está instalado
echo "2️⃣ Verificando se o app está instalado..."
if adb shell pm list packages | grep -q "com.masterpalm.app"; then
    echo "✅ App MasterPalm instalado"
else
    echo "❌ App não está instalado!"
    echo "   Execute: fvm flutter install"
    exit 1
fi
echo ""

# 3. Limpar dados do app e forçar re-verificação
echo "3️⃣ Limpando cache e forçando re-verificação..."
adb shell pm clear com.masterpalm.app
sleep 2
adb shell pm verify-app-links --re-verify com.masterpalm.app
sleep 3
echo "✅ Verificação forçada"
echo ""

# 4. Verificar status dos App Links
echo "4️⃣ Status dos App Links para mastepalm.com.br:"
adb shell pm get-app-links com.masterpalm.app
echo ""

# 5. Verificar domínios aprovados
echo "5️⃣ Domínios verificados:"
adb shell dumpsys package domain-preferred-apps | grep -A 10 "com.masterpalm.app"
echo ""

# 6. Testar deep link
echo "6️⃣ Testando deep link..."
echo "   URL: https://mastepalm.com.br/pedido/TEST123?loja=masterpalm_gmail_com"
adb shell am start -W -a android.intent.action.VIEW \
  -d "https://mastepalm.com.br/pedido/TEST123?loja=masterpalm_gmail_com" \
  com.masterpalm.app

echo ""
echo "✅ Comando executado!"
echo ""
echo "📱 O app MasterPalm deve ter aberto automaticamente."
echo "   Se ainda abre no navegador, possíveis causas:"
echo ""
echo "   1. SHA256 incorreto no assetlinks.json"
echo "      - Verifique: https://mastepalm.com.br/.well-known/assetlinks.json"
echo "      - Certificado atual: 53:CC:53:91:C2:59:92:DD:ED:F6:BB:6A:E2:30:7F:FF:FA:2B:B5:6C:50:BB:4B:C6:C1:F6:38:A6:9A:E5:BD:1D"
echo ""
echo "   2. Android precisa de tempo para verificar (até 24h)"
echo "      - Solução: use custom scheme temporariamente"
echo ""
echo "   3. DNS do domínio customizado com problema"
echo "      - Teste: curl https://mastepalm.com.br/.well-known/assetlinks.json"
echo ""
echo "🔧 TESTE ALTERNATIVO (custom scheme - sempre funciona):"
echo "   adb shell am start -W -a android.intent.action.VIEW \\"
echo "     -d \"mastepalm://pedido/TEST123?loja=masterpalm_gmail_com\" \\"
echo "     com.masterpalm.app"
