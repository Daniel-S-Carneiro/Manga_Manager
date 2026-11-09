# Diretrizes do projeto: posicionamento e limites

> Vale para o código, o README, as releases e as demonstrações.
> Para o Claude Code: antes de implementar uma funcionalidade nova, confira se ela respeita estas regras. Se uma tarefa entrar em conflito com elas, **pare e pergunte** ao usuário antes de seguir.
> Isto é uma orientação geral de boas práticas, não uma consultoria jurídica.

## Posicionamento

O Manga Manager é um **gerenciador de leitura e um tradutor**, não um repositório de mangás.

- Funciona como um navegador com favoritos: **o usuário traz as próprias URLs**, de sites oficiais ou não.
- O app não hospeda, não distribui, não indica e não vem com fontes de conteúdo prontas.
- A tradução é uma **camada temporária na tela**, para uso pessoal, como o tradutor do Chrome ou extensões como o Torii.

Deixe esse posicionamento explícito no README.

## O app faz (permitido)

- Guardar as URLs, o capítulo atual e as capas que o usuário escolheu.
- Abrir as páginas no navegador embutido, como qualquer navegador.
- **Adblock e bloqueio de rastreamento**, como Brave, Opera e Firefox. Descreva como "bloqueio de anúncios", nunca como "desvio de proteção".
- **Bloqueio de redirecionamentos e pop-unders:** é proteção contra golpes e malware.
- **Anti-adblock:** o app pode esconder avisos e coberturas que estão por cima de um conteúdo **já carregado**, o que é só remover um elemento da tela. Prefira regras genéricas, sem uma regra feita sob medida para cada site.
- **Adblock por site:** o usuário pode desligar o adblock num site específico, por exemplo para apoiar um site oficial. Use a `allowed_domains_list` como base.
- **Stealth do WebView**, para que o WebView se apresente como um navegador comum (o WebView tem marcas, como o "wv" no user agent, que alguns sites confundem com robô). Uma pessoa lê página por página. Descreva como **compatibilidade**.
- Traduzir e desenhar o texto por cima das imagens **só na tela**, enquanto a página está aberta.
- Fazer cache **apenas do texto** (texto original + idiomas → tradução), para economizar cota.

## Regra central

> **O app altera apenas como o conteúdo já entregue é exibido. O que o servidor não entrega sem assinatura, login ou confirmação de que os anúncios carregaram continua bloqueado.**

## O app não faz (linhas a não cruzar)

- **Conteúdo retido pelo servidor:** não tentar obter conteúdo que o site só envia depois de confirmar que os anúncios carregaram, nem conteúdo exclusivo para assinantes ou usuários logados.

- **Fontes embutidas:** nenhuma lista, extensão ou repositório de sites de mangá vem com o app, nem é sugerida por ele.
- **Download em massa:** nada de baixar capítulos sem que o usuário abra as páginas, nem de rastrear sites (scraping) em segundo plano.
- **Captcha:** não resolver captcha automaticamente nem integrar serviços que resolvem.
- **Conteúdo pago:** não contornar paywall, login, assinatura ou DRM.
- **Exportar ou compartilhar** as páginas traduzidas como imagem, PDF ou CBZ. Isso transformaria o app num gerador de cópias.
- **Cache persistente de imagens** das páginas, traduzidas ou não. (Um cache temporário em memória durante a leitura é aceitável.)
  - O cache do próprio motor do navegador (WebView2, CEF, WebView do Android) não conta: todo navegador tem um, ele guarda os logins e acelera o carregamento. A regra vale para o que o app grava por conta própria, e o app não cria nenhum cache de imagens.

## Tradução sem rastro

- Todo o processo (download da imagem, OCR, tradução e desenho) roda em segundo plano, e o resultado só existe na tela enquanto a página está aberta.
- As imagens ficam apenas em memória e são descartadas ao fechar a página ou o capítulo. Nada de imagem vai para o disco.
- O cache guarda só texto (texto original + idiomas → tradução). Ele tem um limite de tamanho e um botão "Limpar cache de traduções" nas configurações.
- O app não oferece botão de salvar, exportar ou compartilhar a página traduzida.
- Se o usuário tirar um print da tela e publicar, isso é um ato dele, como com qualquer outra coisa que ele veja e publique. O app não facilita nem incentiva isso.

## Divulgação (README, prints, vídeos, releases)

- Use nas demonstrações páginas de **domínio público**, de sites oficiais ou feitas por você.
- Não cite, não mostre e não dê links de sites não oficiais.
- Descreva as funcionalidades com os termos neutros acima: "bloqueio de anúncios", "compatibilidade", "tradução na tela".
- **Monetização:** cobrar pelo app aumenta a exposição. Se um dia isso for considerado, reavalie estas diretrizes antes.

## Licenças de terceiros

- Antes de distribuir, confira as licenças dos pacotes e dos modelos de IA.
  - PaddleOCR: Apache-2.0.
  - OPUS-MT: CC-BY, que **exige atribuição**. Mantenha uma tela "Sobre" ou um arquivo de créditos com os modelos usados.
- As chaves de API (DeepL, Azure, Google Cloud) são do usuário e ficam só no aparelho dele, guardadas com `flutter_secure_storage`. Elas são enviadas apenas ao serviço a que pertencem.
- Respeite os termos de cada serviço de tradução, inclusive os limites da cota grátis. O app já para quando chega no limite.

## Checklist para cada funcionalidade nova

1. O usuário continua escolhendo e abrindo as páginas ele mesmo?
1. A funcionalidade só altera a exibição do que o site já entregou, sem obter conteúdo retido?
2. O resultado fica só na tela, sem gerar arquivo ou cópia compartilhável?
3. Funciona sem indicar ou embutir nenhum site?
4. A descrição no README usa termos neutros?
5. Algum pacote ou modelo novo exige atribuição?

Se alguma resposta for "não" ou "não sei", discuta com o usuário antes de implementar.
