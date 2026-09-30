@echo off
chcp 65001 >nul
title Organizador de HD
cd /d "%~dp0"
echo ==============================================
echo            ORGANIZADOR DE HD
echo   Nada e apagado. Tudo pode ser desfeito.
echo ==============================================
echo.
set /p LETRA=Letra do HD externo (Enter = I): 
if "%LETRA%"=="" set LETRA=I
echo.
echo  1 - INVENTARIO  (so le e gera relatorio - comece por aqui)
echo  2 - ORGANIZAR   (move os arquivos conforme o relatorio)
echo  3 - DESFAZER    (devolve tudo ao lugar original)
echo.
set /p OP=Escolha 1, 2 ou 3: 
set MODO=
if "%OP%"=="1" set MODO=Inventario
if "%OP%"=="2" set MODO=Organizar
if "%OP%"=="3" set MODO=Desfazer
if "%MODO%"=="" (echo Opcao invalida. & pause & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OrganizarHD.ps1" -Unidade "%LETRA%" -Modo %MODO%
echo.
pause
