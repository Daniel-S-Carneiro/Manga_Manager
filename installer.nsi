!include "MUI2.nsh"
!include "WordFunc.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

# --- Definições do App ---
!define APP_NAME "Onde Parei"
!ifndef APP_VERSION
  !error "APP_VERSION deve ser passado pelo build_installer.cmd (lido do pubspec.yaml)"
!endif
!define PUBLISHER "Daniel S. Carneiro"
!define EXE_NAME "onde_parei.exe"
!define REG_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
# Dados do app. Precisam bater com o CompanyName e o ProductName do
# windows\runner\Runner.rc (o path_provider monta a pasta com eles) e com os
# nomes do lib\database\db_helper.dart
!define PASTA_EMPRESA "$APPDATA\io.github.danielscarneiro"
!define PASTA_DADOS "${PASTA_EMPRESA}\OndeParei"
!define BANCO "onde_parei.db"
!define BANCO_DEBUG "onde_parei_debug.db"
!define CAPAS "$DOCUMENTS\onde_parei_capas"
!define CAPAS_DEBUG "$DOCUMENTS\onde_parei_capas_debug"

Name "${APP_NAME}"
OutFile "OndeParei_Setup.exe"
# O app é de 64 bits. Uma atualização vai para a pasta da instalação
# anterior, se o usuário tiver escolhido outra
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "${REG_UNINSTALL_KEY}" "InstallLocation"
Unicode true

ManifestDPIAware true

Var INSTALACAO_EXISTENTE
Var VERSAO_ANTERIOR
Var MODO_REPARACAO
# "1" na atualização pedida pelo app: /ATUALIZAR (mostra só o progresso) ou
# /S (silenciosa, como o app chamava até a v2.1.0). Não faz perguntas, mantém
# os dados, espera o app fechar e abre o app de novo no fim.
Var ATUALIZACAO

!define MUI_ABORTWARNING
# Ícone do instalador e do desinstalador (o mesmo do app)
!define MUI_ICON "windows\runner\resources\app_icon.ico"
!define MUI_UNICON "windows\runner\resources\app_icon.ico"

# Na atualização só aparece a página de progresso
!define MUI_PAGE_CUSTOMFUNCTION_PRE PularNaAtualizacao
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_CUSTOMFUNCTION_PRE PularNaAtualizacao
!insertmacro MUI_PAGE_DIRECTORY
!define MUI_PAGE_CUSTOMFUNCTION_PRE PularNaAtualizacao
!insertmacro MUI_PAGE_COMPONENTS
!define MUI_PAGE_CUSTOMFUNCTION_SHOW TituloDoProgresso
!insertmacro MUI_PAGE_INSTFILES
# Fim da instalação normal: opção (marcada) de abrir o app
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Abrir o ${APP_NAME}"
!define MUI_FINISHPAGE_RUN_FUNCTION AbrirApp
!define MUI_PAGE_CUSTOMFUNCTION_PRE PularNaAtualizacao
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "PortugueseBR"

Function .onInit
    ${GetParameters} $R0
    ClearErrors
    ${GetOptions} $R0 "/ATUALIZAR" $R1
    ${If} ${Errors}
    ${AndIfNot} ${Silent}
        StrCpy $ATUALIZACAO "0"
    ${Else}
        StrCpy $ATUALIZACAO "1"
    ${EndIf}

    ReadRegStr $VERSAO_ANTERIOR HKLM "${REG_UNINSTALL_KEY}" "DisplayVersion"

    ${If} $VERSAO_ANTERIOR == ""
        StrCpy $INSTALACAO_EXISTENTE "0"
        StrCpy $MODO_REPARACAO "novo"
        Return
    ${EndIf}

    StrCpy $INSTALACAO_EXISTENTE "1"

    # Na atualização pedida pelo app nada é perguntado e os dados ficam
    ${If} $ATUALIZACAO == "1"
        StrCpy $MODO_REPARACAO "atualizacao"
        Return
    ${EndIf}

    ${VersionCompare} "${APP_VERSION}" "$VERSAO_ANTERIOR" $R0

    ${If} $R0 == 0
        MessageBox MB_ICONQUESTION|MB_YESNO "O ${APP_NAME} versão ${APP_VERSION} já está instalado.$\nDeseja realizar uma reparação do zero (apagando dados e capas)?$\nClique em NÃO para reparar/atualizar mantendo seus dados e capas." /SD IDNO IDYES apagar_tudo_reparo IDNO manter_tudo_reparo

        apagar_tudo_reparo:
        StrCpy $MODO_REPARACAO "limpo"
        Goto fim_comparacao

        manter_tudo_reparo:
        StrCpy $MODO_REPARACAO "manter"
        Goto fim_comparacao

    ${ElseIf} $R0 == 1
        MessageBox MB_ICONINFORMATION|MB_OK "Foi detectada uma versão mais antiga ($VERSAO_ANTERIOR) do ${APP_NAME}.$\nO sistema será atualizado para a versão ${APP_VERSION} mantendo seus dados salvos." /SD IDOK
        StrCpy $MODO_REPARACAO "atualizacao"

    ${Else}
        MessageBox MB_ICONEXCLAMATION|MB_OK "Atenção: Uma versão mais recente ($VERSAO_ANTERIOR) já está instalada.$\nOs arquivos serão substituídos pela versão ${APP_VERSION}." /SD IDOK
        StrCpy $MODO_REPARACAO "manter"
    ${EndIf}

    fim_comparacao:
FunctionEnd

Function PularNaAtualizacao
    ${If} $ATUALIZACAO == "1"
        Abort
    ${EndIf}
FunctionEnd

Function TituloDoProgresso
    ${If} $ATUALIZACAO == "1"
        !insertmacro MUI_HEADER_TEXT "Atualizando o ${APP_NAME}" "Instalando a versão ${APP_VERSION}. O app abre sozinho ao terminar."
    ${EndIf}
FunctionEnd

# Abre o app sem privilégio de administrador: o instalador roda elevado e um
# processo aberto direto por ele herdaria isso. Pelo explorer, o app abre como
# o usuário da sessão.
Function AbrirApp
    Exec '"$WINDIR\explorer.exe" "$INSTDIR\${EXE_NAME}"'
FunctionEnd

Function .onInstSuccess
    # O Windows guarda os ícones em cache: avisa que mudaram (atalhos e
    # Painel de Controle mostram o ícone novo sem precisar reiniciar)
    System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
    ${If} $ATUALIZACAO == "1"
        Call AbrirApp
    ${EndIf}
FunctionEnd

# Espera o app liberar o .exe (aberto, ele não pode ser substituído). O app
# que pede a atualização fecha logo depois de abrir o instalador.
!macro FUNCAO_ESPERAR_APP_FECHAR un
Function ${un}EsperarAppFechar
    ${IfNot} ${FileExists} "$INSTDIR\${EXE_NAME}"
        Return
    ${EndIf}
    StrCpy $R1 0
    tentar:
        ClearErrors
        FileOpen $R0 "$INSTDIR\${EXE_NAME}" a
        ${IfNot} ${Errors}
            FileClose $R0
            Return
        ${EndIf}
        IntOp $R1 $R1 + 1
        # Até 30 s
        ${If} $R1 < 120
            Sleep 250
            Goto tentar
        ${EndIf}
        MessageBox MB_ICONEXCLAMATION|MB_RETRYCANCEL "O ${APP_NAME} ainda está aberto.$\nFeche o app e clique em Repetir." /SD IDCANCEL IDRETRY de_novo
        Abort "O ${APP_NAME} continuou aberto."
    de_novo:
        StrCpy $R1 0
        Goto tentar
FunctionEnd
!macroend
!insertmacro FUNCAO_ESPERAR_APP_FECHAR ""
!insertmacro FUNCAO_ESPERAR_APP_FECHAR "un."

Section "Principal (Obrigatório)" SEC01
    SectionIn RO

    DetailPrint "Esperando o ${APP_NAME} fechar..."
    Call EsperarAppFechar

    ${If} $MODO_REPARACAO == "limpo"
        DetailPrint "Limpando dados anteriores a pedido do usuário..."

        # Verifica se existe banco de debug antes de apagar
        ${If} ${FileExists} "${PASTA_DADOS}\${BANCO_DEBUG}"
            MessageBox MB_ICONQUESTION|MB_YESNO "Detectamos um banco de dados de DEBUG (${BANCO_DEBUG}).$\nDeseja apagar TAMBÉM os dados de desenvolvimento?" /SD IDNO IDYES apagar_tudo_reparo_com_debug IDNO apagar_so_producao_reparo

            apagar_tudo_reparo_com_debug:
            RMDir /r "${PASTA_DADOS}"
            RMDir /r "${CAPAS}"
            RMDir /r "${CAPAS_DEBUG}"
            Goto fim_limpeza_reparo

            apagar_so_producao_reparo:
            Delete "${PASTA_DADOS}\${BANCO}"
            RMDir /r "${CAPAS}"
            Goto fim_limpeza_reparo
        ${Else}
            RMDir /r "${PASTA_DADOS}"
            RMDir /r "${CAPAS}"
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
    # Ícone, tamanho e detalhes mostrados no Painel de Controle
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${EXE_NAME},0"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/Daniel-S-Carneiro/Onde-Parei"
    WriteRegStr HKLM "${REG_UNINSTALL_KEY}" "Comments" "Gerenciador de leitura (mangá, manhwa, webtoon e novel) com leitor embutido"
    WriteRegDWORD HKLM "${REG_UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${REG_UNINSTALL_KEY}" "NoRepair" 1
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "${REG_UNINSTALL_KEY}" "EstimatedSize" "$0"

    # Atualização: fecha a janela de progresso sozinha ao terminar
    ${If} $ATUALIZACAO == "1"
        SetAutoClose true
    ${EndIf}
SectionEnd

Section "Criar atalho na Área de Trabalho" SEC02
    # Na atualização só refaz o atalho se ele já existia
    ${If} $ATUALIZACAO == "1"
    ${AndIfNot} ${FileExists} "$DESKTOP\${APP_NAME}.lnk"
        Return
    ${EndIf}
    File "windows\runner\resources\app_icon.ico"
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\app_icon.ico" 0
SectionEnd

Section "Uninstall"
    Call un.EsperarAppFechar

    MessageBox MB_ICONQUESTION|MB_YESNO "Deseja apagar os dados da aplicação (banco de dados e capas)?" /SD IDNO IDYES checar_debug IDNO manter_tudo

    checar_debug:

    # Se existir o DB de debug, pergunta se o dev quer apagar ele também
    ${If} ${FileExists} "${PASTA_DADOS}\${BANCO_DEBUG}"
        MessageBox MB_ICONQUESTION|MB_YESNO "Detectamos um banco de dados de desenvolvimento (${BANCO_DEBUG}).$\n$\nDeseja apagar TAMBÉM os dados e capas de DEBUG?" /SD IDNO IDYES apagar_tudo_com_debug IDNO apagar_so_producao
    ${Else}
        Goto apagar_tudo_com_debug
    ${EndIf}

    apagar_tudo_com_debug:
    DetailPrint "Removendo todos os dados, incluindo arquivos de debug..."
    RMDir /r "${PASTA_DADOS}"
    RMDir /r "${CAPAS}"
    RMDir /r "${CAPAS_DEBUG}"
    RMDir "${PASTA_EMPRESA}"
    Goto prosseguir_desinstalacao

    apagar_so_producao:
    DetailPrint "Removendo apenas os dados de produção e mantendo ambiente de debug..."
    Delete "${PASTA_DADOS}\${BANCO}"
    RMDir /r "${CAPAS}"
    Goto prosseguir_desinstalacao

    manter_tudo:
    DetailPrint "Banco de dados e capas preservados pelo usuário."

    prosseguir_desinstalacao:
    Delete "$SMPROGRAMS\${APP_NAME}.lnk"
    Delete "$DESKTOP\${APP_NAME}.lnk"
    # Só os tipos de arquivo e as pastas que o instalador põe ali: nunca
    # RMDir /r no $INSTDIR, que pode ter sido trocado por uma pasta com outras
    # coisas
    Delete "$INSTDIR\${EXE_NAME}"
    Delete "$INSTDIR\uninstall.exe"
    Delete "$INSTDIR\app_icon.ico"
    Delete "$INSTDIR\*.dll"
    Delete "$INSTDIR\*.pak"
    Delete "$INSTDIR\*.dat"
    Delete "$INSTDIR\*.bin"
    Delete "$INSTDIR\*.json"
    RMDir /r "$INSTDIR\data"
    RMDir /r "$INSTDIR\locales"
    RMDir /r "$INSTDIR\licencas"
    RMDir /r "$INSTDIR\${EXE_NAME}.WebView2"
    RMDir "$INSTDIR"

    DeleteRegKey HKLM "${REG_UNINSTALL_KEY}"

    System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd
