<p align="center">
  <img src="assets/images/logo.png" alt="Onde Parei" width="140">
</p>

<h1 align="center">Onde Parei – Where I Left Off</h1>

<p align="center">
  Biblioteca pessoal de leitura (mangá, manhwa, manhua, webtoon e novel) que guarda em que capítulo você parou, com leitor embutido para Windows, Linux e Android. Feita em Flutter.
</p>

<p align="center">
  <a href="https://github.com/Daniel-S-Carneiro/Onde-Parei/releases/latest"><img src="https://img.shields.io/github/v/release/Daniel-S-Carneiro/Onde-Parei?label=vers%C3%A3o" alt="Última versão"></a>
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter" alt="Flutter 3.47">
  <img src="https://img.shields.io/badge/plataformas-Windows%20%7C%20Linux%20%7C%20Android-informational" alt="Plataformas: Windows, Linux e Android">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licen%C3%A7a-MIT-green" alt="Licença MIT"></a>
</p>

<p align="center">
  <em>A personal reading tracker for manga, manhwa, manhua, webtoons and novels. It remembers the chapter where you left off and opens your own links in a built-in reader with ad blocking. The app is in Portuguese (Brazil).</em>
</p>

---

> **Vindo do Manga Manager?** O app mudou de nome e agora é um app novo, que fica instalado ao lado do antigo. Para levar a biblioteca:
> - **No mesmo computador (Windows ou Linux):** feche o Manga Manager e, no Onde Parei, use **Importar do Manga Manager** (aparece na lista vazia e em Backup / Restaurar).
> - **No celular ou em outro aparelho:** no Manga Manager, faça um backup; no Onde Parei, restaure esse backup.
>
> O Manga Manager não é alterado. Depois de conferir a lista, você pode desinstalá-lo. Os logins dos sites no leitor não vêm junto.

## O que é (e o que não é)

O Onde Parei é um **gerenciador de leitura**. Funciona como um navegador com favoritos: você cadastra o que lê (mangá, manhwa, manhua, webtoon, novel) com **os seus próprios links**, e o app guarda em que capítulo você parou e abre a página no navegador embutido.

- O app não hospeda, não distribui e não indica conteúdo, nem vem com sites prontos.
- O bloqueio de anúncios e de pop-ups funciona como o de navegadores como Brave e Firefox: muda só o que aparece na tela, sem liberar nada que o site não entregou.

As regras completas estão em [docs/diretrizes-projeto.md](docs/diretrizes-projeto.md).

## Recursos

### Biblioteca

- Cadastre cada leitura com título em português e em inglês, capítulo atual, link de leitura, capa e status (**Lendo**, **Completo**, **Dropado**, **Planejo Ler**).
- Marque o tipo de cada leitura: **Mangá**, **Manhwa**, **Manhua**, **Webtoon**, **Novel** ou **Outro**. O tipo aparece num selo na capa.
- Busque pelo título, filtre por tipo e por status e reorganize a lista arrastando os cards.
- As capas ficam salvas no próprio dispositivo (no Linux e no Android são convertidas para WebP).

### Leitor embutido

- Abre o link da leitura dentro do app: WebView2 no Windows, Chromium (CEF) no Linux e WebView no Android.
- Bloqueia anúncios, pop-ups e redirecionamentos, e mantém a navegação dentro do site aberto.
- Esconde avisos que cobrem a página sozinhos; um botão na barra do leitor desliga isso no site aberto.
- Barra de controle flutuante (voltar, recarregar e tela cheia), na horizontal ou na vertical, que pode ser arrastada e lembra a posição.
- Rolagem do mouse suave no computador, com distância por giro e suavidade ajustáveis pelo botão de mouse da barra.
- Tela cheia com **F11**.
- Ao fechar o leitor, o app identifica o capítulo pelo título ou pelo endereço da página e **pergunta** se você quer atualizar o link e o capítulo. Nada é gravado sem confirmação.

### Interface e dados

- Tema claro e escuro.
- Zoom da interface pelo controle deslizante ou com **Ctrl + roda do mouse**, lembrado entre aberturas.
- Todos os dados ficam no seu dispositivo, num banco SQLite.
- Backup e restauração em `.tar.gz` (banco + capas), substituindo tudo ou mesclando com o que já existe.
- Aviso de nova versão a partir das releases do GitHub. No Windows a atualização é instalada pelo próprio app.

## Instalação

Baixe o arquivo da sua plataforma na **[última release](https://github.com/Daniel-S-Carneiro/Onde-Parei/releases/latest)**:

| Plataforma | Arquivo | Como instalar |
| --- | --- | --- |
| Windows 10/11 (64 bits) | `OndeParei_Setup.exe` | Execute o instalador (pede permissão de administrador). O leitor usa o Microsoft Edge WebView2 Runtime, que já vem no Windows 11 e no Windows 10 atualizado. |
| Linux x64 | `OndeParei_Linux_x64.tar.gz` | Extraia e execute `bundle/onde_parei`. Instale o `xclip` para poder colar texto no leitor: `sudo apt install xclip`. |
| Android 7.0+ | `OndeParei.apk` | Permita a instalação de apps de fontes desconhecidas e abra o APK. |

**Onde ficam os dados no Windows:** o banco fica em `%APPDATA%\io.github.danielscarneiro\OndeParei\` e as capas em `Documentos\onde_parei_capas\`. Ao desinstalar, o instalador pergunta se você quer apagá-los.

## Desenvolvimento

### Requisitos

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 (canal stable), com as ferramentas de desktop Windows e o Android SDK.
- [NSIS](https://nsis.sourceforge.io/) para gerar o instalador do Windows.
- Para o pacote Linux: WSL 2 com Ubuntu, o Flutter para Linux em `~/flutter` e `clang`, `cmake`, `ninja-build`, `pkg-config` e `libgtk-3-dev`.

### Executar e testar

```bash
git clone https://github.com/Daniel-S-Carneiro/Onde-Parei.git
cd Onde-Parei
flutter pub get
flutter run -d windows
```

```bash
flutter analyze
flutter test
```

### Gerar uma versão

1. Atualize a linha `version:` do `pubspec.yaml` e faça o commit. O script recusa rodar com alterações pendentes, para que os três pacotes saiam do mesmo código.
2. Rode `build_installer.cmd`. Ele compila Windows, Android e Linux (este no WSL, pelo `build_linux.sh`), gera o instalador NSIS e deixa tudo em `dist\`.
3. Publique uma release com a tag `vX.Y.Z` e anexe os três arquivos de `dist\` **sem mudar os nomes**: a atualização automática do app procura por eles.

## Estrutura do projeto

```text
lib/
├── main.dart          # inicialização, zoom, tema e tela principal
├── controllers/       # aviso para a tela principal recarregar a lista
├── database/          # DbHelper (SQLite)
├── screens/           # leitor: base comum (LeitorBase), BrowserScreen (Windows/Android) e LinuxBrowserScreen (CEF)
├── services/          # backup e atualização automática
├── utils/             # adblock e filtro de navegação, tipos e status, tema, tar.gz, seletor de arquivos
└── widgets/           # cards, formulários, filtros, diálogos e barra de controle do leitor
test/                  # testes de lógica e de diálogos
build_installer.cmd    # gera os pacotes de Windows, Android e Linux
build_linux.sh         # compila o Linux no WSL a partir do commit atual
installer.nsi          # instalador do Windows (NSIS)
```

## Tecnologias

- [Flutter](https://flutter.dev/) / Dart
- [sqflite](https://pub.dev/packages/sqflite) e [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) (SQLite no celular e no desktop)
- [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview) (leitor no Windows e no Android) e [webview_cef](https://pub.dev/packages/webview_cef) (leitor no Linux)
- [window_manager](https://pub.dev/packages/window_manager) (janela e tela cheia no desktop)
- [file_picker](https://pub.dev/packages/file_picker) e [tar](https://pub.dev/packages/tar) (capas e backup)

## Contribuição

Este é um projeto pessoal, feito para organizar e acompanhar leituras em capítulos. Sugestões e relatos de problemas são bem-vindos nas [issues](https://github.com/Daniel-S-Carneiro/Onde-Parei/issues).

## Licença

Distribuído sob a licença MIT. Veja o arquivo [LICENSE](LICENSE).

As licenças dos componentes de terceiros ficam no próprio app (janela de versão → **Licenças**). Os pacotes de Windows e Linux trazem também a pasta `licencas/`, com a licença do Chromium Embedded Framework e os créditos do Chromium, que vão dentro do leitor.
