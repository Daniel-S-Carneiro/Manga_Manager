@echo off
setlocal EnableDelayedExpansion

:: blinter-disable-next-line S019
SET CODEPAGE_UTF8=65001
SET "UTF8_CODEPAGE=%CODEPAGE_UTF8%"
chcp %UTF8_CODEPAGE% >nul
:: ==============================================================================
:: Script: build_installer.cmd
:: Objetivo: Automatizar o build de release (Windows, Android e Linux via WSL)
:: Autor: Daniel da Silva Carneiro
:: Data: 07/09/2026
:: ==============================================================================

echo [1/5] Iniciando build do Flutter (Windows)...
call flutter.bat build windows --release
if not exist "build\windows\x64\runner\Release" goto :error_win

echo.
echo [2/5] Iniciando build do Flutter (Android APK)...
call flutter.bat build apk --release
if not exist "build\app\outputs\flutter-apk\app-release.apk" goto :error_android

echo.
echo [3/5] Iniciando build do Flutter (Linux via WSL)...
:: S024: Separado em duas chamadas wsl para reduzir a complexidade da linha
wsl -d Ubuntu bash -c "cd ~/manga_manager && export PATH=\$HOME/flutter/bin:\$PATH && flutter build linux --release"
if %ERRORLEVEL% NEQ 0 goto :error_linux

wsl -d Ubuntu bash -c "cd ~/manga_manager && mkdir -p dist && tar -czf dist/MangaManager_Linux_x64.tar.gz -C build/linux/x64/release bundle"
if %ERRORLEVEL% NEQ 0 goto :error_linux

echo.
echo [4/5] Iniciando compilacao do instalador Windows com NSIS...
set "APP_VERSION="
for /f "tokens=2 delims= " %%a in ('findstr /r /c:"^version:" "pubspec.yaml"') do (
    for /f "tokens=1 delims=+" %%b in ("%%a") do set "APP_VERSION=%%b"
)
set "APP_VERSION=!APP_VERSION:"=!"
if not defined APP_VERSION goto :error_version
if "!APP_VERSION!"=="" goto :error_version

echo Versao lida do pubspec.yaml: !APP_VERSION!

set "NSIS_PATH=C:\Program Files (x86)\NSIS\makensis.exe"
set "BUILD_PATH=build\windows\x64\runner\Release"
"%NSIS_PATH%" /DAPP_BUILD_DIR="%BUILD_PATH%" /DAPP_VERSION=!APP_VERSION! "installer.nsi"
if %ERRORLEVEL% NEQ 0 goto :error_nsis

echo.
echo [5/5] Organizando arquivos na pasta 'dist'...
if not exist "dist" mkdir dist

:: Mover Instalador Windows com tratamento de erro
if exist "MangaManager_Setup.exe" (
    move /Y "MangaManager_Setup.exe" "dist\" >nul
    if %ERRORLEVEL% NEQ 0 (
        echo ERRO: Falha ao mover o instalador Windows para a pasta dist.
        goto :error_dist
    )
)

:: Mover APK Android com tratamento de erro
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    move /Y "build\app\outputs\flutter-apk\app-release.apk" "dist\MangaManager.apk" >nul
    if %ERRORLEVEL% NEQ 0 (
        echo ERRO: Falha ao mover o APK para a pasta dist.
        goto :error_dist
    )
)

:: Copiar o pacote Linux gerado no WSL para a pasta dist dinamicamente
for /f "tokens=* delims=" %%i in ('wsl wslpath -u "%CD%"') do set "WSL_PATH=%%i"

:: SEC013: Variavel enviada como argumento seguro ($0) para o bash
wsl -d Ubuntu bash -c "cp ~/manga_manager/dist/MangaManager_Linux_x64.tar.gz \"$0/dist/\"" "%WSL_PATH%" 2>nul

echo.
echo ==================================================
echo Processo concluido com sucesso!
echo Arquivos disponiveis na pasta: dist\
echo - Versao:  !APP_VERSION!
echo - Windows: MangaManager_Setup.exe
echo - Android: MangaManager.apk
echo - Linux:   MangaManager_Linux_x64.tar.gz
echo ==================================================
goto :success

:error_win
echo ERRO: O build Windows falhou!
goto :fail

:error_android
echo ERRO: O build do APK falhou!
goto :fail

:error_linux
echo ERRO: O build Linux via WSL falhou!
goto :fail

:error_version
echo ERRO: Nao foi possivel ler a versao em pubspec.yaml (linha version: x.y.z+n).
goto :fail

:error_nsis
echo ERRO: Falha na criacao do instalador NSIS.
goto :fail

:error_dist
echo ERRO: Falha na organizacao dos artefatos na pasta dist.
goto :fail

:success
set "SCRIPT_EXIT_CODE=0"
goto :end

:fail
set "SCRIPT_EXIT_CODE=1"

:end
if "%SCRIPT_EXIT_CODE%"=="1" (
    exit  /b 1
) else (
    exit /b 0
)

exit /b 0