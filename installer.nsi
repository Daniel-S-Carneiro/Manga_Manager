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

ManifestDPIAware true

Var INSTALACAO_EXISTENTE
Var VERSAO_ANTERIOR
Var MODO_REPARACAO

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "PortugueseBR"

Function .onInit
    ReadRegStr $VERSAO_ANTERIOR HKLM "${REG_UNINSTALL_KEY}" "DisplayVersion"

    ${If} $VERSAO_ANTERIOR == ""
        StrCpy $INSTALACAO_EXISTENTE "0"
        StrCpy $MODO_REPARACAO "novo"
    ${Else}
        StrCpy $INSTALACAO_EXISTENTE "1"

        ${VersionCompare} "${APP_VERSION}" "$VERSAO_ANTERIOR" $R0

        ${If} $R0 == 0
            MessageBox MB_ICONQUESTION|MB_YESNO "O ${APP_NAME} versão ${APP_VERSION} já está instalado.$\nDeseja realizar uma reparação do zero (apagando dados e capas)?$\nClique em NÃO para reparar/atualizar mantendo seus dados e capas." IDYES apagar_tudo_reparo IDNO manter_tudo_reparo

            apagar_tudo_reparo:
            StrCpy $MODO_REPARACAO "limpo"
            Goto fim_comparacao

            manter_tudo_reparo:
            StrCpy $MODO_REPARACAO "manter"
            Goto fim_comparacao

        ${ElseIf} $R0 == 1
            MessageBox MB_ICONINFORMATION|MB_OK "Foi detectada uma versão mais antiga ($VERSAO_ANTERIOR) do ${APP_NAME}.$\nO sistema será atualizado para a versão ${APP_VERSION} mantendo seus dados salvos."
            StrCpy $MODO_REPARACAO "atualizacao"

        ${Else}
            MessageBox MB_ICONEXCLAMATION|MB_OK "Atenção: Uma versão mais recente ($VERSAO_ANTERIOR) já está instalada.$\nOs arquivos serão substituídos pela versão ${APP_VERSION}."
            StrCpy $MODO_REPARACAO "manter"
        ${EndIf}
    ${EndIf}

    fim_comparacao:
FunctionEnd

Section "Principal (Obrigatório)" SEC01
    SectionIn RO

    ${If} $MODO_REPARACAO == "limpo"
        DetailPrint "Limpando dados anteriores a pedido do usuário..."

        # Verifica se existe banco de debug antes de apagar
        ${If} ${FileExists} "$APPDATA\com.example\manga_manager\manga_manager_debug.db"
            MessageBox MB_ICONQUESTION|MB_YESNO "Detectamos um banco de dados de DEBUG (manga_manager_debug.db).$\nDeseja apagar TAMBÉM os dados de desenvolvimento?" IDYES apagar_tudo_reparo_com_debug IDNO apagar_so_producao_reparo

            apagar_tudo_reparo_com_debug:
            RMDir /r "$APPDATA\com.example\manga_manager"
            RMDir /r "$DOCUMENTS\manga_manager_capas"
            RMDir /r "$DOCUMENTS\manga_manager_capas_debug"
            Goto fim_limpeza_reparo

            apagar_so_producao_reparo:
            Delete "$APPDATA\com.example\manga_manager\manga_manager.db"
            RMDir /r "$DOCUMENTS\manga_manager_capas"
            Goto fim_limpeza_reparo
        ${Else}
            RMDir /r "$APPDATA\com.example\manga_manager"
            RMDir /r "$DOCUMENTS\manga_manager_capas"
        ${EndIf}

        fim_limpeza_reparo:
    ${EndIf}

    Delete "$INSTDIR\${EXE_NAME}"
    RMDir /r "$INSTDIR\data"

    SetOutPath "$INSTDIR"
    File /r "${APP_BUILD_DIR}\*.*"

    File "windows\runner\resources\app_icon.ico"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\app_icon.ico" 0

    WriteUninstaller "$INSTDIR\uninstall.exe"

    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "Publisher" "${PUBLISHER}"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
SectionEnd

Section "Criar atalho na Área de Trabalho" SEC02
    File "windows\runner\resources\app_icon.ico"
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\app_icon.ico" 0
SectionEnd

Section "Uninstall"
    MessageBox MB_ICONQUESTION|MB_YESNO "Deseja apagar os dados da aplicação (banco de dados e capas)?" IDYES checar_debug IDNO manter_tudo

    checar_debug:

    # Se existir o DB de debug, pergunta se o dev quer apagar ele também
    ${If} ${FileExists} "$APPDATA\com.example\manga_manager\manga_manager_debug.db"
        MessageBox MB_ICONQUESTION|MB_YESNO "Detectamos um banco de dados de desenvolvimento (manga_manager_debug.db).$\n$\nDeseja apagar TAMBÉM os dados e capas de DEBUG?" IDYES apagar_tudo_com_debug IDNO apagar_so_producao
    ${Else}
        Goto apagar_tudo_com_debug
    ${EndIf}

    apagar_tudo_com_debug:
    DetailPrint "Removendo todos os dados, incluindo arquivos de debug..."
    RMDir /r "$APPDATA\com.example\manga_manager"
    RMDir /r "$APPDATA\manga_manager"
    RMDir /r "$DOCUMENTS\manga_manager_capas"
    RMDir /r "$DOCUMENTS\manga_manager_capas_debug"
    Goto prosseguir_desinstalacao

    apagar_so_producao:
    DetailPrint "Removendo apenas os dados de produção e mantendo ambiente de debug..."
    Delete "$APPDATA\com.example\manga_manager\manga_manager.db"
    Delete "$APPDATA\manga_manager\manga_manager.db"
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
