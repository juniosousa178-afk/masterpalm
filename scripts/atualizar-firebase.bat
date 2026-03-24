@echo off
REM Script para atualizar SHA no Firebase (corrige DEVELOPER_ERROR)
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizar-firebase.ps1" %*
pause
