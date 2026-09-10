# Manga Manager 📖

Um aplicativo moderno e robusto desenvolvido em **Flutter** para gerenciamento, acompanhamento e leitura fluida de mangás, com foco especial em experiência de desktop (Windows, Linux e macOS).

---

## 🚀 Recursos Principais

- **Gerenciamento de Biblioteca:** Adicione, edite, remova e reordene seus mangás com facilidade. Controle títulos em português e inglês, capítulos atuais, capas locais e status de leitura.
- **Leitor Integrado Inteligente (`InAppWebView`):** Navegue e leia diretamente pelo aplicativo utilizando um WebView avançado.
- **Bloqueio de Anúncios e Popups:** Scripts embutidos para bloquear popups indesejados, janelas de anúncios e iframes maliciosos comuns em sites de leitura.
- **Barra Flutuante Interativa e Persistente:**
  - Menu flutuante arrastável (Draggable) e rotativo (modo horizontal ou vertical).
  - **Persistência no SQLite:** A posição exata na tela e o estado de rotação são salvos automaticamente no banco de dados local.
- **Controle de Rolagem Aprimorado:** Ajuste de velocidade de scroll customizado via JavaScript sem perder o comportamento padrão do navegador, eliminando efeitos incômodos de _bouncing_.
- **Suporte a Tela Cheia (F11):** Alternância rápida para modo imersivo de tela cheia integrada ao gerenciador de janelas.
- **Armazenamento Local Robusto:** Utilização de **SQLite** (`sqflite`) para gerenciar metadados dos mangás e preferências de configuração do usuário (como temas e estados da UI).

---

## 🛠️ Tecnologias Utilizadas

O projeto foi construído utilizando tecnologias e pacotes modernos do ecossistema Flutter:

- **Framework:** [Flutter](https://flutter.dev/) (Dart)
- **Banco de Dados:** `sqflite` / `sqflite_common_ffi` (para suporte multiplataforma desktop/mobile)
- **WebView:** `flutter_inappwebview`
- **Gerenciamento de Janelas:** `window_manager` (para controles nativos de tela cheia, redimensionamento e barra de títulos no desktop)
- **Caminhos e Diretórios:** `path_provider`

---

## 📦 Como Executar o Projeto

Siga os passos abaixo para rodar o projeto em sua máquina de desenvolvimento:

1. **Pré-requisitos:**
   - Tenha o [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado.
   - Certifique-se de ter dependências de plataforma configuradas (como `libwebkit2gtk` caso esteja no Linux).

2. **Clone o repositório:**

   ```bash
   git clone [https://github.com/seu-usuario/manga_manager.git](https://github.com/seu-usuario/manga_manager.git)
   cd manga_manager
   ```

3. **Instale as dependências:**

   ```bash
   flutter pub get
   ```

4. **Instale as dependências:**
   ```bash
   flutter run
   ```

---

## 📂 Estrutura do Projeto

```bash
lib/
├── database/     # Configuração e manipulação do SQLite (DbHelper)
├── screens/      # Telas principais (Lista de Mangás, Leitor/BrowserScreen)
└── main.dart     # Ponto de entrada e inicialização global do app
```

---

## 💡 Contribuição

Este é um projeto de desenvolvimento pessoal focado em produtividade na leitura e organização de mangás. Sugestões e melhorias são sempre bem-vindas!
