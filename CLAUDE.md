# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Visão geral

App Flutter pessoal para gerenciar uma biblioteca de mangás e ler os capítulos num navegador embutido. O foco é desktop (Windows principal, Linux testado via WSL 2); também gera APK Android. Repositório: `github.com/Daniel-S-Carneiro/Manga_Manager`.

Código, comentários, nomes de variáveis e textos da interface são em **português**. Mantenha esse padrão.

## Comandos (Windows, na raiz do projeto)

```bash
flutter pub get
flutter analyze                      # analisa só lib/ e test/ (pastas de plataforma excluídas)
flutter run -d windows
flutter test                         # todos os testes
flutter test test/browser_helper_test.dart   # um arquivo
flutter test --plain-name "nome do teste"
build_installer.cmd                  # release completo: Windows + APK + Linux (WSL) + instalador NSIS -> dist/ (exige árvore Git limpa)
```

- Os testes cobrem só lógica pura e diálogos (`BrowserHelper`, `atualizacao_leitura_dialog.dart`). Nada que abra o banco ou o WebView é testado automaticamente; isso precisa de teste manual no app.
- `build_installer.cmd` lê a versão da linha `version:` do `pubspec.yaml` (parte antes do `+`) e passa para o `installer.nsi` como `APP_VERSION`. Precisa do NSIS em `C:\Program Files (x86)\NSIS\makensis.exe`.

## Linux via WSL (distro `Ubuntu`)

- Use sempre `~/flutter/bin/flutter`. Num `wsl -d Ubuntu -- bash -c "..."` não interativo, `flutter` puro aponta para o SDK do **Windows** (`/mnt/c/tools/flutter`).
- O Flutter do WSL (`~/flutter`) e o do Windows (`C:\tools\flutter`) ficam na **mesma versão** (hoje 3.47.9 stable), para os três pacotes saírem do mesmo SDK. Atualize os dois juntos e recompile tudo.
- `~/StudioProjects/manga_manager` é o clone Git usado no Linux (o usuário abre esse clone no VS Code via Remote WSL). Ele tem o remote `win`, que aponta para o repositório do Windows. Para testar no Linux basta commitar no Windows e rodar `git pull --ff-only win <branch>` no clone, sem precisar de push para o GitHub. O código só passa de um lado para o outro pelo Git, nunca por cópia.
- O passo 3 do `build_installer.cmd` chama o `build_linux.sh`, que sincroniza esse clone com o commit atual do Windows, falha se houver divergência ou alteração pendente, compila e grava o pacote direto em `dist\`. O `build_installer.cmd` também recusa rodar com alterações não commitadas, para que os três pacotes saiam do mesmo commit.
- Executar no Linux: `flutter run -d linux --no-enable-impeller` com `GDK_BACKEND=x11` (configuração do `.vscode/launch.json`).
- Build: `~/flutter/bin/flutter build linux --release` gera `build/linux/x64/release/bundle`, que é empacotado como `MangaManager_Linux_x64.tar.gz`.

Exemplo a partir do Windows:

```bash
wsl -d Ubuntu -- bash -c 'cd ~/StudioProjects/manga_manager && git pull --ff-only win main && ~/flutter/bin/flutter build linux --release'
```

## Arquitetura

**Estado global sem biblioteca de gerenciamento de estado.** São `ValueNotifier`/`ChangeNotifier` globais:
- `appZoomNotifier` e `ctrlPressedNotifier` (`lib/main.dart`): o zoom é aplicado no `MaterialApp.builder` dividindo o `MediaQuery.size`, multiplicando o `devicePixelRatio` e usando `Transform.scale`. Ctrl + roda do mouse altera o zoom e trava o scroll da grade. O valor é salvo com debounce na chave `zoom`.
- `ThemeController.themeNotifier` (`lib/utils/theme_notifier.dart`): tema salvo na chave `tema`.
- `globalRefreshController` (`lib/controllers/refresh_controller.dart`): quem altera o banco fora da tela principal (por exemplo, restauração de backup) chama `.refresh()` para a `MainScreen` recarregar a lista.

**Banco (`lib/database/db_helper.dart`).** Singleton `DbHelper` sobre sqflite. No desktop usa FFI, e `setupDatabaseFactory()` em `main()` precisa rodar antes de qualquer acesso. Os registros são `Map<String, dynamic>` puros, sem classes de modelo.
- Tabela `mangas`: `id, nome_pt, nome_en, capitulo, link_url, capa_path, status_leitura, ordem_leitura`.
- Tabela `configuracoes`: chave/valor usada para **todas** as preferências (`tema`, `zoom`, `barra_x`, `barra_y`, `barra_vertical`, `user_agent_custom`, `adblock_domains_list`, `allowed_domains_list`, `browser_helper_last_update`).
- O schema está na versão 2. Mudança de schema exige subir a `version` em `_initDatabase` e adicionar um passo em `_onUpgrade`, porque usuários instalados já têm bancos antigos.
- Debug e release usam dados separados por `kDebugMode`: `manga_manager_debug.db` / `manga_manager_capas_debug` contra `manga_manager.db` / `manga_manager_capas`. As capas ficam como arquivos em Documentos e o banco guarda o caminho (`capa_path`). No Windows o banco fica em `%APPDATA%\com.example\manga_manager`, e o `installer.nsi` depende desse caminho para limpar dados.
- `lockDatabase()`/`unlockDatabase()`: durante backup/restauração qualquer acesso a `database` lança exceção.

**Tela principal (`MainScreen` em `lib/main.dart`).** Paginação de 30 em 30 com scroll infinito e busca com debounce. A reordenação por arrasto fica bloqueada durante uma busca ou antes de carregar a lista inteira, porque `reordenarMangas` regrava `ordem_leitura` a partir da lista em memória. Os cards se atualizam individualmente com `_atualizarMangaEspecifico`.

**Leitor embutido.** `MangaCardWidget._abrirLink` (`lib/widgets/manga_card.dart`) abre `LinuxBrowserScreen` (webview_cef) no Linux e `BrowserScreen` (flutter_inappwebview, WebView2 no Windows) nas demais plataformas. O `BrowserScreen` retorna um `Map` com `url` e `capitulo`. O `LinuxBrowserScreen` retorna só a URL, porque não detecta o capítulo. O card compara esse retorno com o que está salvo (`MudancasLeitura` em `lib/widgets/atualizacao_leitura_dialog.dart`) e **sempre pede confirmação** antes de gravar o link ou o capítulo, porque a detecção do capítulo pode errar. A lógica comum fica em `lib/utils/browser_helper.dart`: script de adblock injetado, filtro de navegação por **host** permitido, scripts de stealth (o de Android é diferente), detecção do número do capítulo pelo título ou pela URL, user agent e sincronização remota das listas (só https em release). As duas telas salvam a posição da `FloatingControlBar`. Ao mudar o comportamento do leitor, **mantenha as duas telas coerentes**.

**Backup (`lib/services/backup_service.dart`).** Gera um `.tar.gz` com o banco e as capas via `TarStreamHelper` dentro de `Isolate.run`. A restauração substitui tudo ou mescla (a mescla evita duplicados por `nome_pt`). A restauração procura o arquivo de banco com o nome do modo atual, então um backup feito em debug não restaura em release, e vice-versa.

**Atualização automática.** `lib/services/update_service.dart` e `lib/widgets/version_updater_button.dart` consultam a última release do GitHub, comparam a tag (sem o `v`) com a versão do app (`pubspec.yaml`) e escolhem o asset pela extensão: `.exe` no Windows, `.apk` no Android e `.tar.gz` no Linux. As releases precisam manter essas extensões. No Windows o instalador baixado roda elevado e silencioso (`/S`) via PowerShell `Start-Process -Verb RunAs`.

## Armadilhas

- `installer.nsi` está em **Windows-1252**, não em UTF-8, e as ferramentas Edit/Write recusam o arquivo. Edite preservando a codificação, por exemplo com PowerShell e `[System.Text.Encoding]::GetEncoding(1252)`.
- Scripts `.sh` precisam de fim de linha LF, garantido pelo `.gitattributes`. Com CRLF o bash do WSL falha.
- **Android:** usa Gradle 9.3.1, AGP 9.1.0 e Kotlin 2.4.0, as mesmas versões dos modelos do Flutter 3.47 (`templateDefaultGradleVersion` e afins em `packages/flutter_tools/lib/src/android/gradle_utils.dart` do SDK), com `android.builtInKotlin=true` (o app não aplica `kotlin-android`).
  - O `android/gradle.properties` tem `android.r8.proguardAndroidTxt.disallowed=false`. É **temporário**, só enquanto o `flutter_inappwebview_android` estável usar `proguard-android.txt`.
  - Depois de trocar a versão do AGP ou de um plugin Android, rode `flutter clean`. Restos de compilações anteriores fazem o Gradle "compilar" um plugin sem gerar classe nenhuma (erro `cannot find symbol` no `GeneratedPluginRegistrant`).
- **`file_picker` 13:** `pickFile()` devolve um `PlatformFile?`, e no Android o arquivo pode vir só como URI `content://`, sem caminho. Use `caminhoLocalDoArquivo()` (`lib/utils/file_picker_helper.dart`). O `saveFile()` exige os `bytes` e grava o arquivo ele mesmo.
- `.vscode/` e `dist/` estão no `.gitignore`.
