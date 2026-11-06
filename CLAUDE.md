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

- Os testes cobrem lógica pura e diálogos (`BrowserHelper`, `LeitorBase`, `ConfigRolagem`, `PainelRolagem`, `AtualizacaoDialog`, `CapaHelper`, `atualizacao_leitura_dialog.dart`, o diálogo do `VersionUpdaterButton` em larguras de celular, a limpeza das cópias do `usarArquivoEscolhido`) e a exportação e a restauração do backup, que abre um banco SQLite de verdade em pastas temporárias. O resto do que usa o banco, e tudo o que usa o WebView, precisa de teste manual no app.
- Em `testWidgets`, código que chama canal de plataforma (banco, `window_manager`, `path_provider`) precisa de `tester.runAsync(...)`. Sem isso o teste espera para sempre uma resposta que nunca chega.
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
- Tabela `configuracoes`: chave/valor usada para **todas** as preferências (`tema`, `zoom`, `barra_x`, `barra_y`, `barra_vertical`, `rolagem_ativa`, `rolagem_intensidade`, `rolagem_suavidade`, `versao_app`, `user_agent_custom`, `adblock_domains_list`, `allowed_domains_list`, `browser_helper_last_update`).
- O schema está na versão 2. Mudança de schema exige subir a `version` em `_initDatabase` e adicionar um passo em `_onUpgrade`, porque usuários instalados já têm bancos antigos.
- Debug e release usam dados separados por `kDebugMode`: `manga_manager_debug.db` / `manga_manager_capas_debug` contra `manga_manager.db` / `manga_manager_capas`. As capas ficam como arquivos em Documentos e o banco guarda o caminho (`capa_path`). No Windows o banco fica em `%APPDATA%\com.example\manga_manager`, e o `installer.nsi` depende desse caminho para limpar dados.
- `lockDatabase()`/`unlockDatabase()`: durante backup/restauração qualquer acesso a `database` lança exceção.

**Tela principal (`MainScreen` em `lib/main.dart`).** Paginação de 30 em 30 com scroll infinito e busca com debounce. A reordenação por arrasto fica bloqueada durante uma busca ou antes de carregar a lista inteira, porque `reordenarMangas` regrava `ordem_leitura` a partir da lista em memória. Os cards se atualizam individualmente com `_atualizarMangaEspecifico`.

**Capas (`lib/utils/capa_helper.dart`).**
- **Gravação** (`CapaHelper.gravar`, usado pelos dois formulários): no Windows o arquivo original é copiado. No Android e no Linux vira WebP (qualidade 90), reduzido até um dos lados chegar a 720×1080; o `flutter_image_compress` nunca aumenta. Antes eram 300×450, e o celular (2,75×) esticava a capa umas duas vezes. As capas gravadas antes disso continuam pequenas até serem escolhidas de novo.
- **No card** (`CapaHelper.tamanhoDecodificado`): a capa é decodificada no tamanho em que aparece, em pixels reais (tamanho lógico × `devicePixelRatio`, que já inclui o zoom do app). Quando o quadro é mais estreito que uma capa, a altura manda; senão, a largura. O valor é arredondado de 64 em 64, para não decodificar de novo a cada pixel ao redimensionar a janela.

**Leitor embutido.** `MangaCardWidget._abrirLink` (`lib/widgets/manga_card.dart`) abre `LinuxBrowserScreen` (webview_cef) no Linux e `BrowserScreen` (flutter_inappwebview, WebView2 no Windows) nas demais plataformas. O flutter_inappwebview estável não tem Linux; o suporte só existe em beta, com WPE WebKit, que não está no apt do Ubuntu.
- **Comum às duas telas:** fica no mixin `LeitorBase` (`lib/screens/leitor_base.dart`): URL permitida (por **host**), URL atual e última permitida, detecção do capítulo (título, URL e cabeçalho), barra flutuante (carregar, salvar, manter dentro da tela), painel da rolagem do mouse, tela cheia/F11 e o resultado ao fechar (`{'url', 'capitulo'}`). Cada tela só cria o seu navegador e liga os eventos dele a `registrarUrl`, `aplicarCapituloDoTexto` e `detectarCapituloDaPagina`. **Comportamento novo do leitor vai para o `LeitorBase`**, não para uma das telas.
- **Scripts e listas:** ficam em `lib/utils/browser_helper.dart`: adblock injetado, scripts de stealth (o de Android é diferente), clique agressivo, leitura do cabeçalho, listas de domínios, user agent e sincronização remota das listas (só https em release).
- **Limitações do webview_cef** (sem como igualar): não intercepta requisições, não tem `shouldOverrideUrlLoading` e não tem evento de erro de carregamento (usa um tempo limite de 25 s).
- **Bloqueio de navegação por script (`bloquearNavegacaoPorScript`, só no Linux):** cancela, **antes** de sair da página, a navegação da janela principal para um host não permitido (pop-under via `location.href`, `assign`, `replace`, `top.location` ou link). Usa o evento `navigate` da Navigation API do Chromium. Testado no Chromium: cancela sem recarregar e deixa passar o mesmo host e o voltar/avançar. **Em investigação:** com ele ligado nos dois sistemas, o Nexus passou a mostrar "Erro ao carregar o capítulo" ao abrir um link salvo, por isso o Windows (que já cancela pelo `shouldOverrideUrlLoading`) não o usa. Se algo escapar, o Linux ainda detecta no `onUrlChanged` e volta para a última URL permitida, mas isso **recarrega** o capítulo.
- **Investigar falhas de sites no Linux:** com `_kDebugLinuxBrowser` ligado, o adblock roda em modo diagnóstico (`getAdBlockScript(diagnostico: true)`). A página anota requisições com erro (com o servidor que respondeu, o começo do corpo e se foi desafio da Cloudflare), erros de JavaScript e navegações bloqueadas em `window.__mangaDiag`, e ao fechar o leitor o log mostra `diagnóstico da página`. O `BrowserScreen` faz o mesmo com `_isDebugMode`. As duas chaves seguem o `kDebugMode`: ficam ligadas no `flutter run` e desligadas no build de release (para investigar um release, troque por `true`). O log interno do flutter_inappwebview (uma linha por requisição) fica desligado pelo `_logDoPlugin`, para não abafar o nosso. O `onConsoleMessage` do webview_cef não entrega as mensagens do console, por isso o diagnóstico é lido assim.
- **User agent no desktop:** é o do próprio motor (WebView2 no Windows, CEF/Chromium 149 no Linux). O UA fixo antigo ("Chrome/131") contradizia os client hints (`sec-ch-ua`), e o Nexus passou a responder `503` às chamadas da API dele. No Linux, um UA salvo pelo usuário (`user_agent_custom`) ainda vale; no Windows ele é ignorado, porque o sync remoto grava um UA de Linux.
- **Regra de domínio de anúncio** (`hostCasaComEntrada` no Dart e `hostCasa` no JS, que precisam ficar iguais):
  - Entrada **com ponto** casa por rótulos inteiros do host: `adjust.com` não pega `cadjust.com`, e `pagead2.googlesyndication` pega `pagead2.googlesyndication.com`.
  - Entrada **sem ponto** é palavra-chave e casa por trecho do host.
  - Entrada com `/` casa na URL inteira.
  - O host da sessão e os domínios permitidos **nunca** são anúncio, para que uma entrada genérica não derrube os scripts e as imagens do próprio site.
- **Bloqueio de scripts e quadros de anúncio** (`bloquearElementosDeAnuncio`, ligado por padrão): o adblock recusa que a página **insira** `<script>`/`<iframe>` de domínio de anúncio. Cobre o `src` (propriedade e `setAttribute`), `appendChild`/`insertBefore`/`append`/`prepend`, fragmentos e um `MutationObserver` para o que escapar (ex.: iframe via `innerHTML`). Script escrito direto no HTML original passa. É o que impede o anúncio de rodar no Linux, onde o CEF não bloqueia o download. O diagnóstico anota cada recusa em `elementos`. Testado no Chromium com o script gerado pelo app.
- **Anúncio preso no `<html>` (`removerForaDoBody`, ligado por padrão):** o adblock remove tudo o que a página prender direto no `<html>` fora do `<head>` e do `<body>` (observa só os filhos do `<html>`). Página de verdade não põe nada ali; as redes de anúncio põem. Era assim que vinham os pop-ups falsos do Opera no Nexus: um `div` fixo com `z-index` 2147483646 e quadros sem `src`, de uma rede que troca de domínio toda semana (`leedbrott.com`, `pistilairwash.cfd`, `*.qpon`, `*.cyou`...). Por isso a regra não depende da lista. Não insira nada no `<html>` pelos nossos scripts: a regra removeria. Avisos dentro da página, onde o bloqueio por domínio não alcança (inclusive os do próprio site), ficam escondidos por CSS em `adoptedStyleSheets`, a partir da lista `BrowserHelper.seletoresEscondidos`: os blocos do AdSense (`ins.adsbygoogle`, ex.: "Descobrir mais" no Nexus) e o balão "Apoie o site" do plugin de doações MangaJS (`#mjsDonationModal`, mangalivre.blog), cujo "ocultar" fica gravado no servidor. Use só seletores bem específicos, porque a lista vale para todos os sites. O teste `JS gerado tem sintaxe válida` confere o script no Node (pula sem Node).
- **Anúncio que toma a página no Linux:** costuma vir de um iframe de outro domínio, que o bloqueio por script não cancela. O leitor volta pelo **histórico** (`goBack`), o que pode restaurar o capítulo sem recarregar, e só recarrega a URL se o capítulo não voltar em 2,5 s.
- **Rolagem do mouse (só desktop):** os plugins entregam à página um giro da roda multiplicado. O `flutter_inappwebview_windows` 0.6.0 multiplica por 6 o delta do Flutter (`InAppWebView::sendScroll`), e a página recebe uns 5 giros (~500 px). O `webview_cef` 0.6.2 multiplica por 10 (`WebviewHandler::sendScrollEvent`), dando ~530 px. Por isso a página "pulava".
  - O `BrowserHelper.scriptRolagem` intercepta a roda (`passive: false`), desfaz o exagero com o `fatorBaseRolagem` de cada tela (0,2 no Windows e 100/530 no Linux) e desliza até o destino.
  - O usuário ajusta pelo botão do mouse na barra flutuante: ligado/desligado, distância por giro (100% ≈ 100 px) e suavidade. A configuração fica em `ConfigRolagem` (`lib/utils/config_rolagem.dart`) e o painel em `lib/widgets/painel_rolagem.dart`.
  - A mudança vale na hora: o script já instalado só troca a configuração. Ela também vale nas páginas seguintes: no Windows, troca o user script do grupo `manga_rolagem`; no Linux, troca o item na lista do `InjectUserScripts`, que o webview_cef relê a cada carregamento.
  - O script deixa a rolagem com o navegador quando nada pode rolar naquela direção, e também com Ctrl, Shift, rolagem horizontal, página trancada (`overflow: hidden`) e roda que a própria página já tratou. Uma caixa interna rolável tem prioridade e, ao chegar ao fim, passa a rolagem para a página.
  - Se um plugin for atualizado, confira no `diagnóstico da página` os `deltas` de `rolagem`, que mostram o que chega por giro, e ajuste o fator.
  - Testado no Chromium com roda real e eventos sintéticos. O painel do navegador embutido precisa estar visível, porque escondido ele pausa o `requestAnimationFrame` e a animação para no meio.
- **Pedidos de permissão (`onPermissionRequest` no `BrowserScreen`):** o leitor nega todos. Não remova o handler: no Windows, o `flutter_inappwebview_windows` 0.6.0 lê a resposta do Dart sem conferir se é nula (`PermissionRequestCallback` em `webview_channel_delegate.cpp`), e sem handler o Dart responde `null` e o app fecha (`0xc0000005` em `flutter_inappwebview_windows_plugin.dll`, em `std::variant::index`). Aconteceu no Nexus. Para achar a função de um deslocamento do log do Windows no build de debug: `llvm-symbolizer --obj=<dll> --relative-address <deslocamento>` (o do NDK do Android serve), com o `.pdb` em `build\windows\x64\plugins\...\Debug`.
- **Diferenças de propósito:** o `cliqueAgressivoScript` roda só no `BrowserScreen` desktop. No CEF ele quebrou sites SPA, então o Linux fica só com o adblock "suave".
- **Tentativas que não funcionaram no Linux:** o `zikzak_inappwebview` (fork com WPE) travou com `Gtk-CRITICAL: gtk_widget_draw` logo depois do `onWebViewCreated`, testado no WSL. Também não dá para ter o `flutter_inappwebview` estável e o beta juntos no `pubspec`.
- O card compara o retorno com o que está salvo (`MudancasLeitura` em `lib/widgets/atualizacao_leitura_dialog.dart`) e **sempre pede confirmação** antes de gravar o link ou o capítulo, porque a detecção do capítulo pode errar.

**Backup (`lib/services/backup_service.dart`).** Gera um `.tar.gz` com o banco na raiz e as capas em `capas/`, via `TarStreamHelper` dentro de `Isolate.run`. A restauração substitui tudo ou mescla (a mescla evita duplicados por `nome_pt`).
- **Qualquer origem:** o backup pode vir de outro modo (app instalado ou debug) e de outro sistema (Windows → celular). O `bancoDoBackup` prefere o banco do modo atual, mas aceita o outro.
- **Caminho das capas:** o banco guarda o caminho completo do aparelho de origem (ex.: `C:\...\manga_manager_capas/capa_1.jpg`). Depois de restaurar, as capas que vieram no backup passam a apontar para a pasta de capas daqui (`DbHelper.caminhoCapaRestaurada`, que separa o nome com barra normal ou invertida). Antes disso, um backup do Windows restaurado no celular ficava sem capas.
- **Banco travado:** a restauração roda com `lockDatabase()`, então o `database` lança exceção; o código dela usa `bancoEmManutencao()`. Antes, o mesclar chamava `database` e sempre falhava.
- **Substituir:** apaga os restos de diário do SQLite (`-journal`, `-wal`, `-shm`) antes de copiar o banco novo por cima.
- **Leitura dos arquivos (`TarStreamHelper.lerArquivo`):** não use `File.openRead()` no backup. No `_FileStream` do Dart SDK, um erro de leitura no meio (arquivo travado por outro programa) deixa o arquivo aberto e o stream nunca termina; a gravação (`cancelOnError`) só recebe o erro depois do cancelamento, e o backup ficava parado (`Computation ended without result` no `Isolate.run`). A lista de arquivos e os tamanhos são lidos antes de gravar, porque um erro dentro do stream de entradas escapa do `tarWriter`.
- **Manifesto (`manifesto.json`, desde a v2.2.1):** primeira entrada do backup, com `formato` e `arquivos` (nome → tamanho). A extração confere tudo numa pasta temporária e lança `BackupIncompleto` se faltar arquivo ou o tamanho não bater (backup cortado, inclusive exatamente entre dois arquivos, que o tar e o gzip sozinhos não percebem); assim a restauração para antes de mexer nos dados. Backups sem manifesto continuam aceitos. O `manifest.json` de setembro de 2026 (só depuração) é ignorado. Um app antigo (até a v2.2.0) que restaure um backup novo copia o `manifesto.json` para a pasta de capas, o que não causa problema. Se o formato mudar, suba `formato` e mantenha `arquivos`.
- **Arquivos temporários:** a exportação grava direto no destino e apaga o arquivo pela metade se falhar. A restauração roda dentro de `usarArquivoEscolhido` (`lib/utils/file_picker_helper.dart`), que apaga a cópia do backup (no Android o file_picker copia o arquivo escolhido para `cache/file_picker`) e nunca o original.
- **Testes** (`test/backup_service_test.dart`): restauram de verdade com o `sqflite_common_ffi`, trocando o `path_provider` por pastas temporárias e simulando o computador (`debugDefaultTargetPlatformOverride`). Nos testes o Flutter finge ser Android, e o `DbHelper` iria para a pasta de bancos do sqflite. Uma trava no `setUp` falha o teste se o banco ou as capas apontarem para fora da pasta temporária, porque o "substituir" apaga dados.
- No Windows a extração passa os nomes dos arquivos para minúsculas (`p.canonicalize`); como o sistema de arquivos não diferencia maiúsculas, isso não quebra nada.

**Atualização automática.** `lib/services/update_service.dart` e `lib/widgets/version_updater_button.dart` consultam a última release do GitHub, comparam a tag (sem o `v`) com a versão do app (`pubspec.yaml`) e escolhem o asset pela extensão: `.exe` no Windows, `.apk` no Android e `.tar.gz` no Linux. As releases precisam manter essas extensões. Fora do Windows o arquivo abre no navegador.
- **Windows:** a tela `AtualizacaoDialog` (`lib/widgets/atualizacao_dialog.dart`) baixa o instalador com progresso (porcentagem, MB e velocidade) e confere se veio inteiro e se começa com `MZ`.
  - Depois pede a permissão de administrador (PowerShell `Start-Process -Verb RunAs`) e abre o instalador com `/ATUALIZAR`. Então mostra "Fechando para instalar" e fecha o app pela janela (`windowManager.close()`, em `UpdateService._fecharParaInstalar`), não com `exit(0)` (ver "Fechamento no Windows" nas armadilhas).
  - Permissão recusada ou falha no download: a tela mostra o erro e "Tentar de novo". Com o instalador já baixado, só pede a permissão de novo.
  - A gravação do download é síncrona, pedaço a pedaço. Com gravação assíncrona, os testes de widget (relógio falso) travavam esperando o arquivo fechar.
- **Modo de atualização do instalador:** vale com `/ATUALIZAR` ou com `/S`, que é como o app chamava até a v2.1.0.
  - Não faz perguntas e mantém os dados.
  - Mostra só a página de progresso ("Atualizando o Manga Manager") e espera o app soltar o `.exe` (até 30 s).
  - No fim, abre o app de novo pelo `explorer.exe`, para não herdar o privilégio de administrador do instalador. A instalação normal tem a opção "Abrir o Manga Manager" na última página, que abre do mesmo jeito.
  - Refaz o atalho da área de trabalho só se ele já existia.
  - Avisa o Windows (`SHChangeNotify`) para trocar os ícones em cache.
- **Ao abrir:** o app compara a versão com a chave `versao_app` e, se mudou, mostra "Manga Manager atualizado para a vX". Também apaga o instalador que ficou na pasta temporária.
- **Testes:** em `testWidgets`, não dê `await` no `cancel()` de uma assinatura de stream nem no `close()` de um `StreamController` já cancelado. Eles devolvem um futuro da zona raiz, que o relógio falso nunca conclui, e o teste trava sem respeitar o `@Timeout`.

## Armadilhas

- `installer.nsi` está em **Windows-1252**, não em UTF-8, e as ferramentas Edit/Write recusam o arquivo. Edite preservando a codificação, por exemplo com PowerShell e `[System.Text.Encoding]::GetEncoding(1252)`.
  - O instalador grava na chave de desinstalação os dados do Painel de Controle: ícone (`DisplayIcon` aponta para o `.exe`), tamanho (`EstimatedSize`, calculado com `GetSize`), publicador, site e comentário.
  - Todo `MessageBox` precisa de `/SD` (resposta no modo silencioso): sem ele, a caixa aparece mesmo com `/S`. Era a janela de "OK" que surgia no meio da atualização.
  - O desinstalador apaga só os tipos de arquivo que o instalador põe na pasta (`*.dll`, `*.pak`, `*.dat`, `*.bin`, `*.json`) e as pastas `data`, `locales` e `manga_manager.exe.WebView2`. Nunca use `RMDir /r` no `$INSTDIR`, que o usuário pode ter trocado por uma pasta com outras coisas.
  - O `app_icon.ico` também é o ícone do instalador e do desinstalador (`MUI_ICON`/`MUI_UNICON`).
- **Ícone do app (igual em todas as plataformas):** quadrado preto de cantos arredondados com o livro ocupando quase toda a largura. Tudo foi gerado junto a partir do `assets/icon/icon.png`; os outros arquivos da pasta (`ACBam`, `HhVze`, `icon2`, `manga`) são versões antigas do desenho.
  - `windows/runner/resources/app_icon.ico`: 10 tamanhos (16 a 256 px; BMP de 32 bits até 128 e PNG no de 256), com o livro mais justo até 48 px. O `Runner.rc` embute esse arquivo no `.exe`. Os atalhos e o Painel de Controle dependem do instalador. Não gere o `.ico` pelo `flutter_launcher_icons`, que no Windows faz um único tamanho (48 px); por isso o `windows.generate` dele está `false`.
  - `assets/icon/app_icon.png` (1024 px): mestre do `flutter_launcher_icons`, que gera o legado do Android e o iOS (`remove_alpha_ios`, porque o iOS não aceita transparência).
  - `assets/icon/app_icon_adaptativo.png`: frente do ícone adaptativo do Android, com o livro em 56% da largura para caber no recorte em círculo. O fundo é `#000000`.
  - `assets/icon/app_icon_256.png`: ícone da janela no Linux. É o único arquivo da pasta que vai dentro do app (`pubspec`, `assets`); o `my_application.cc` o lê de `data/flutter_assets` ao lado do executável.
  - Depois de trocar os PNGs, rode `dart run flutter_launcher_icons` (Android e iOS). O `dart run flutter_native_splash:create` só é necessário se o `assets/splash/splash.png` ou as cores do splash mudarem.
- **Fechamento no Windows (`windows/runner/main.cpp`):** depois do loop de mensagens, o runner fecha a janela (`window.Destroy()`, que encerra o engine e os plugins) e termina o processo com `TerminateProcess`, sem os destrutores de variáveis estáticas. Não tire isso: o app caía em **todo** fechamento desde a v2.0.0, sem ninguém ver, porque a janela já tinha sumido.
  - O `flutter_inappwebview_windows` 0.6.0 cria ao abrir uma `DispatcherQueueController` e um `Compositor` em estáticas e nunca os desliga; liberados no fim do processo, davam `0xc0000005` em `coremessaging.dll`.
  - O `webview_cef` (registrado também no Windows, embora o app só o use no Linux) roda uma thread de vsync num `std::thread` estático; com `exit(0)` ela ainda estava ativa e o C++ chamava `std::terminate` (`0xc0000409` em `ucrtbase.dll`). Por isso, para fechar o app, use `windowManager.close()`.
  - Para conferir: abrir e fechar o `.exe` com `CloseMainWindow()` no PowerShell e ver o código de saída (`0` está certo) e o log Aplicativo do Windows (evento 1000).
- Scripts `.sh` precisam de fim de linha LF, garantido pelo `.gitattributes`. Com CRLF o bash do WSL falha.
- **Android:** usa Gradle 9.3.1, AGP 9.1.0 e Kotlin 2.4.0, as mesmas versões dos modelos do Flutter 3.47 (`templateDefaultGradleVersion` e afins em `packages/flutter_tools/lib/src/android/gradle_utils.dart` do SDK), com `android.builtInKotlin=true` (o app não aplica `kotlin-android`).
  - O `android/gradle.properties` tem `android.r8.proguardAndroidTxt.disallowed=false`. É **temporário**, só enquanto o `flutter_inappwebview_android` estável usar `proguard-android.txt`.
  - Depois de trocar a versão do AGP ou de um plugin Android, rode `flutter clean`. Restos de compilações anteriores fazem o Gradle "compilar" um plugin sem gerar classe nenhuma (erro `cannot find symbol` no `GeneratedPluginRegistrant`).
- **`file_picker` 13:** `pickFile()` devolve um `PlatformFile?`, e no Android o arquivo pode vir só como URI `content://`, sem caminho. Use `caminhoLocalDoArquivo()` (`lib/utils/file_picker_helper.dart`). O `saveFile()` exige os `bytes` e grava o arquivo ele mesmo.
- `.vscode/` e `dist/` estão no `.gitignore`.
