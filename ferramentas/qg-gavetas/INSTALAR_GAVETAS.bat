@echo off
chcp 65001 >nul
title Gavetas QG LUTERUEL TECH
echo ==============================================
echo      PAINEL DE GAVETAS - QG LUTERUEL TECH
echo ==============================================
echo.
echo  1 - INSTALAR / ATUALIZAR
echo  2 - REMOVER
echo.
set /p OP=Escolha 1 ou 2: 
if "%OP%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar.ps1"
if "%OP%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar.ps1" -Remover
echo.
pause
