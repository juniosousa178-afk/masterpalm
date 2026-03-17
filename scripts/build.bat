@echo off
REM Script Flutter - temp_naty
REM Uso: scripts\build.bat [get|analyze|run|apk|web|clean|full]

setlocal
cd /d "%~dp0\.."

if "%1"=="" set "CMD=full"
if "%1"=="get" set "CMD=get"
if "%1"=="analyze" set "CMD=analyze"
if "%1"=="run" set "CMD=run"
if "%1"=="apk" set "CMD=apk"
if "%1"=="web" set "CMD=web"
if "%1"=="clean" set "CMD=clean"
if "%1"=="full" set "CMD=full"

echo === Flutter Script - %CMD% ===

if "%CMD%"=="get" goto :get
if "%CMD%"=="analyze" goto :analyze
if "%CMD%"=="run" goto :run
if "%CMD%"=="apk" goto :apk
if "%CMD%"=="web" goto :web
if "%CMD%"=="clean" goto :clean
if "%CMD%"=="full" goto :full

:get
fvm flutter pub get
goto :end

:analyze
fvm flutter analyze
goto :end

:run
fvm flutter run
goto :end

:apk
fvm flutter build apk --release
goto :end

:web
fvm flutter build web --release
goto :end

:clean
fvm flutter clean
fvm flutter pub get
goto :end

:full
fvm flutter pub get
fvm flutter analyze
echo.
echo Analise OK. Para build: scripts\build.bat apk ou web
goto :end

:end
echo.
echo === Concluido ===
endlocal
