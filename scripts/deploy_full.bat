@echo off
REM ============================================================
REM MasterPalm - Script completo de deploy
REM Atualiza: app web, APK Android, site, catálogo, functions
REM ============================================================
REM Uso: scripts\deploy_full.bat [skip-apk]
REM   skip-apk = pula build do APK (mais rápido, só web+functions)
REM ============================================================

setlocal EnableDelayedExpansion
cd /d "%~dp0\.."

echo.
echo ========================================
echo  MasterPalm - Deploy Completo
echo ========================================
echo.

REM 1) Dependencies
echo [1/7] fvm flutter pub get...
call fvm flutter pub get
if errorlevel 1 (echo ERRO: fvm flutter pub get falhou & goto :error)

REM 2) Analyze
echo.
echo [2/7] fvm flutter analyze...
call fvm flutter analyze
if errorlevel 1 (echo AVISO: analyze encontrou problemas, continuando...)

REM 3) Build Web
echo.
echo [3/7] fvm flutter build web --release...
call fvm flutter build web --release
if errorlevel 1 (echo ERRO: build web falhou & goto :error)

REM 4) Build APK (a menos que skip-apk)
if "%1"=="skip-apk" (
  echo.
  echo [4/7] APK: pulado (skip-apk)
) else (
  echo.
  echo [4/7] fvm flutter build apk --release...
  call fvm flutter build apk --release
  if errorlevel 1 (echo ERRO: fvm build apk falhou & goto :error)

  REM Copiar APK para pasta de download do site
  if not exist "build\web\downloads" mkdir "build\web\downloads"
  if exist "build\app\outputs\flutter-apk\app-release.apk" (
    copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\web\downloads\masterpalm.apk" >nul
    echo      APK copiado para build\web\downloads\masterpalm.apk
  ) else if exist "android\app\build\outputs\apk\release\app-release.apk" (
    copy /Y "android\app\build\outputs\apk\release\app-release.apk" "build\web\downloads\masterpalm.apk" >nul
    echo      APK copiado para build\web\downloads\masterpalm.apk
  ) else (
    echo AVISO: APK nao encontrado, verifique o output do build
  )
)

REM 5) Deploy Functions
echo.
echo [5/7] firebase deploy --only functions...
call firebase deploy --only functions
if errorlevel 1 (echo ERRO: deploy functions falhou & goto :error)

REM 6) Deploy Hosting (web + APK em /downloads)
echo.
echo [6/7] firebase deploy --only hosting...
call firebase deploy --only hosting
if errorlevel 1 (echo ERRO: deploy hosting falhou & goto :error)

REM 7) Firestore/Storage rules (opcional, geralmente nao muda)
echo.
echo [7/7] firebase deploy --only firestore:rules,storage...
call firebase deploy --only firestore:rules,storage 2>nul
if errorlevel 1 (echo AVISO: firestore/storage rules pode ter falhado, verifique)

echo.
echo ========================================
echo  Deploy concluido com sucesso!
echo ========================================
echo.
echo - App Web:   https://mastepalm.com.br (ou seu dominio)
echo - Download:  https://mastepalm.com.br/downloads/masterpalm.apk
echo - Catálogo:  https://mastepalm.com.br/c/SEU-SLUG
echo.
goto :end

:error
echo.
echo ========================================
echo  ERRO: Deploy falhou
echo ========================================
exit /b 1

:end
endlocal
exit /b 0
