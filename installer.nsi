!include "MUI2.nsh"
!include "WordFunc.nsh"
!include "LogicLib.nsh"

# --- Definições do App ---
!define APP_NAME "Manga Manager"
!define APP_VERSION "1.1.0"
!define PUBLISHER "Daniel-S-Carneiro"
!define EXE_NAME "manga_manager.exe"
!define REG_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

Name "${APP_NAME}"
OutFile "MangaManager_Setup.exe"
InstallDir "$PROGRAMFILES\${APP_NAME}"
Unicode true

# --- DPI Awareness ---
ManifestDPIAware true

# --- Variáveis de Controle ---
Var INSTALACAO_EXISTENTE
Var VERSAO_ANTERIOR
Var MODO_REPARACAO

# --- Páginas da Interface Moderna ---
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME

# Página personalizada ou verificação via .onInit para detecção de versão
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "PortugueseBR"

# --- Função executada no início para detectar versão anterior ---
Function .onInit
    # Lê a versão anterior instalada no registro
    ReadRegStr $VERSAO_ANTERIOR HKLM "${REG_UNINSTALL_KEY}" "DisplayVersion"

    ${If} $VERSAO_ANTERIOR == ""
        # Sem instalação anterior
        StrCpy $INSTALACAO_EXISTENTE "0"
        StrCpy $MODO_REPARACAO "novo"
    ${Else}
        # Já existe uma versão instalada
        StrCpy $INSTALACAO_EXISTENTE "1"

        # Compara a versão atual com a instalada
        ${VersionCompare} "${APP_VERSION}" "$VERSAO_ANTERIOR" $R0

        ${If} $R0 == 0
            # Versões iguais
            MessageBox MB_ICONQUESTION|MB_YESNO "O ${APP_NAME} versão ${APP_VERSION} já está instalado.$\nDeseja realizar uma reparação do zero (apagando dados e capas)?$\nClique em NÃO para reparar/atualizar mantendo seus dados e capas." IDYES apagar_tudo_reparo IDNO manter_tudo_reparo

            apagar_tudo_reparo:
            StrCpy $MODO_REPARACAO "limpo"
            Goto fim_comparacao

            manter_tudo_reparo:
            StrCpy $MODO_REPARACAO "manter"
            Goto fim_comparacao

        ${ElseIf} $R0 == 1
            # Versão nova (Atualização)
            MessageBox MB_ICONINFORMATION|MB_OK "Foi detectada uma versão mais antiga ($VERSAO_ANTERIOR) do ${APP_NAME}.$\nO sistema será atualizado para a versão ${APP_VERSION} mantendo seus dados e capas salvos."
            StrCpy $MODO_REPARACAO "atualizacao"

        ${Else}
            # Versão instalada é mais recente que o instalador (Downgrade)
            MessageBox MB_ICONEXCLAMATION|MB_OK "Atenção: Uma versão mais recente ($VERSAO_ANTERIOR) já está instalada.$\nOs arquivos serão substituídos pela versão ${APP_VERSION}."
            StrCpy $MODO_REPARACAO "manter"
        ${EndIf}
    ${EndIf}

    fim_comparacao:
FunctionEnd

# --- Seção Principal de Instalação ---
Section "Principal (Obrigatório)" SEC01
    SectionIn RO

    ${If} $MODO_REPARACAO == "limpo"
        DetailPrint "Limpando banco de dados e capas anteriores a pedido do usuário..."
        RMDir /r "$APPDATA\manga_manager"
        RMDir /r "$DOCUMENTS\manga_manager_capas"
    ${EndIf}

    # Remove os binários antigos do diretório de instalação do programa
    Delete "$INSTDIR\${EXE_NAME}"
    RMDir /r "$INSTDIR\data"

    SetOutPath "$INSTDIR"
    File /r "${APP_BUILD_DIR}\*.*"

    # Menu Iniciar com ícone definido
    DetailPrint "Criando atalho com ícone: $INSTDIR\${EXE_NAME}"
    File "windows\runner\resources\app_icon.ico"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\app_icon.ico" 0

    # Criar desinstalador
    WriteUninstaller "$INSTDIR\uninstall.exe"

    # Registro para "Adicionar/Remover Programas" (Salvando a versão atual para controle futuro)
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "Publisher" "${PUBLISHER}"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
SectionEnd

# --- Seção do Atalho na Área de Trabalho ---
Section "Criar atalho na Área de Trabalho" SEC02
    File "windows\runner\resources\app_icon.ico"
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\app_icon.ico" 0
SectionEnd

# --- Seção de Desinstalação (Com Pergunta sobre Dados) ---
Section "Uninstall"
    # Pergunta ao usuário se ele deseja apagar os dados salvos (Banco de dados e Capas)
    MessageBox MB_ICONQUESTION|MB_YESNO "Deseja apagar também o banco de dados (histórico de leitura) e as capas dos mangás salvos no computador? Clique em NÃO se quiser preservá-los para uma futura instalação." IDYES apagar_tudo IDNO manter_tudo

    apagar_tudo:
    RMDir /r "$APPDATA\manga_manager"
    RMDir /r "$DOCUMENTS\manga_manager_capas"
    Goto prosseguir_desinstalacao

    manter_tudo:
    DetailPrint "Banco de dados e capas preservados pelo usuário."

    prosseguir_desinstalacao:
    Delete "$SMPROGRAMS\${APP_NAME}.lnk"
    Delete "$DESKTOP\${APP_NAME}.lnk"
    Delete "$INSTDIR\app_icon.ico"
    Delete "$INSTDIR\${EXE_NAME}"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"

    DeleteRegKey HKLM "${REG_UNINSTALL_KEY}"
SectionEnd
