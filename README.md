<p align="center">
  <img src="assets/images/logo.png" alt="Manga Manager" width="140">
</p>

<h1 align="center">Manga Manager</h1>

<p align="center">
  Biblioteca pessoal de mangás com leitor embutido para Windows, Linux e Android, feita em Flutter.
</p>

<p align="center">
  <a href="https://github.com/Daniel-S-Carneiro/Manga_Manager/releases/latest"><img src="https://img.shields.io/github/v/release/Daniel-S-Carneiro/Manga_Manager?label=vers%C3%A3o" alt="Última versão"></a>
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter" alt="Flutter 3.47">
  <img src="https://img.shields.io/badge/plataformas-Windows%20%7C%20Linux%20%7C%20Android-informational" alt="Plataformas: Windows, Linux e Android">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licen%C3%A7a-MIT-green" alt="Licença MIT"></a>
</p>

---

## Recursos

### Biblioteca

- Cadastre mangás com título em português e em inglês, capítulo atual, link de leitura, capa e status (**Lendo**, **Completo**, **Dropado**, **Planejo Ler**).
- Busque pelo título e reorganize a lista arrastando os cards.
- As capas ficam salvas no próprio dispositivo (no Linux e no Android são convertidas para WebP).

### Leitor embutido

- Abre o link do mangá dentro do app: WebView2 no Windows, Chromium (CEF) no Linux e WebView no Android.
- Bloqueia anúncios, pop-ups e redirecionamentos, e mantém a navegação dentro do site do mangá.
- Barra de controle flutuante (voltar, recarregar e tela cheia), na horizontal ou na vertical, que pode ser arrastada e lembra a posição.
- Tela cheia com **F11**.
- Ao fechar o leitor, o app identifica o capítulo pelo título ou pelo endereço da página e **pergunta** se você quer atualizar o link e o capítulo. Nada é gravado sem confirmação. No Linux, por enquanto, só o link é atualizado.

### Interface e dados

- Tema claro e escuro.
- Zoom da interface pelo controle deslizante ou com **Ctrl + roda do mouse**, lembrado entre aberturas.
- Todos os dados ficam no seu dispositivo, num banco SQLite.
- Backup e restauração em `.tar.gz` (banco + capas), substituindo tudo ou mesclando com o que já existe.
- Aviso de nova versão a partir das releases do GitHub. No Windows a atualização é instalada pelo próprio app.

## Instalação

Baixe o arquivo da sua plataforma na **[última release](https://github.com/Daniel-S-Carneiro/Manga_Manager/releases/latest)**:

| Plataforma | Arquivo | Como instalar |
| --- | --- | --- |
| Windows 10/11 (64 bits) | `MangaManager_Setup.exe` | Execute o instalador (pede permissão de administrador). O leitor usa o Microsoft Edge WebView2 Runtime, que já vem no Windows 11 e no Windows 10 atualizado. |
| Linux x64 | `MangaManager_Linux_x64.tar.gz` | Extraia e execute `bundle/manga_manager`. Instale o `xclip` para poder colar texto no leitor: `sudo apt install xclip`. |
| Android 7.0+ | `MangaManager.apk` | Permita a instalação de apps de fontes desconhecidas e abra o APK. |

**Onde ficam os dados no Windows:** o banco fica em `%APPDATA%\com.example\manga_manager\` e as capas em `Documentos\manga_manager_capas\`. Ao desinstalar, o instalador pergunta se você quer apagá-los.

## Desenvolvimento

### Requisitos

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 (canal stable), com as ferramentas de desktop Windows e o Android SDK.
- [NSIS](https://nsis.sourceforge.io/) para gerar o instalador do Windows.
- Para o pacote Linux: WSL 2 com Ubuntu, o Flutter para Linux em `~/flutter` e `clang`, `cmake`, `ninja-build`, `pkg-config` e `libgtk-3-dev`.

### Executar e testar

```bash
git clone https://github.com/Daniel-S-Carneiro/Manga_Manager.git
cd Manga_Manager
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
├── screens/           # leitor: BrowserScreen (Windows/Android) e LinuxBrowserScreen (CEF)
├── services/          # backup e atualização automática
├── utils/             # adblock e filtro de navegação, tema, tar.gz, seletor de arquivos
└── widgets/           # cards, formulários, diálogos e barra de controle do leitor
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

Este é um projeto pessoal, feito para organizar e acompanhar a leitura de mangás. Sugestões e relatos de problemas são bem-vindos nas [issues](https://github.com/Daniel-S-Carneiro/Manga_Manager/issues).

## Licença

Distribuído sob a licença MIT. Veja o arquivo [LICENSE](LICENSE).
