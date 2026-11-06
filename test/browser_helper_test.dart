import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/utils/browser_helper.dart';
import 'package:manga_manager/utils/config_rolagem.dart';

/// Node no PATH, para conferir a sintaxe do JS gerado.
final bool _temNode = () {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}();

void main() {
  group('hostMatchesAllowed', () {
    const permitidos = ['nexustoons.com', 'leituramanga'];

    test('host igual ou subdomínio de entrada com ponto', () {
      expect(
        BrowserHelper.hostMatchesAllowed(
          'https://nexustoons.com/manga/1',
          permitidos,
        ),
        isTrue,
      );
      expect(
        BrowserHelper.hostMatchesAllowed(
          'https://cdn.nexustoons.com/img.png',
          permitidos,
        ),
        isTrue,
      );
    });

    test('domínio permitido na query string ou no caminho não libera', () {
      expect(
        BrowserHelper.hostMatchesAllowed(
          'https://anuncio.com/?volta=nexustoons.com',
          permitidos,
        ),
        isFalse,
      );
      expect(
        BrowserHelper.hostMatchesAllowed(
          'https://anuncio.com/nexustoons.com/x',
          permitidos,
        ),
        isFalse,
      );
    });

    test('host que só começa com o domínio permitido não libera', () {
      expect(
        BrowserHelper.hostMatchesAllowed(
          'https://nexustoons.com.golpe.io/',
          permitidos,
        ),
        isFalse,
      );
    });

    test('entrada sem ponto casa por trecho do host', () {
      expect(
        BrowserHelper.hostMatchesAllowed(
          'https://www.leituramanga.net/cap-1',
          permitidos,
        ),
        isTrue,
      );
    });

    test('URL sem host não libera', () {
      expect(
        BrowserHelper.hostMatchesAllowed('about:blank', permitidos),
        isFalse,
      );
      expect(BrowserHelper.hostMatchesAllowed('', permitidos), isFalse);
    });
  });

  group('hostCasaComEntrada / urlEhAnuncio', () {
    test('entrada com ponto casa por rótulos inteiros do host', () {
      expect(
        BrowserHelper.hostCasaComEntrada(
          'ad.doubleclick.net',
          'doubleclick.net',
        ),
        isTrue,
      );
      expect(
        BrowserHelper.hostCasaComEntrada('doubleclick.net', 'doubleclick.net'),
        isTrue,
      );
      expect(
        BrowserHelper.hostCasaComEntrada(
          'pagead2.googlesyndication.com',
          'pagead2.googlesyndication',
        ),
        isTrue,
      );
    });

    test('entrada genérica não pega domínio só parecido', () {
      // Antes (trecho do host) 'adjust.com' pegava 'cadjust.com'
      expect(
        BrowserHelper.hostCasaComEntrada('cadjust.com', 'adjust.com'),
        isFalse,
      );
      expect(
        BrowserHelper.hostCasaComEntrada('a-ads.com.meusite.net', 'a-ads.co'),
        isFalse,
      );
    });

    test('entrada sem ponto continua sendo palavra-chave', () {
      expect(
        BrowserHelper.hostCasaComEntrada('x9.tcliktrc.com', 'tcliktrc'),
        isTrue,
      );
    });

    test('urlEhAnuncio: host pela regra acima e "/" na URL inteira', () {
      const lista = ['ravishwalnut.qpon', 'exemplo.com/ads/'];
      expect(
        BrowserHelper.urlEhAnuncio('https://ravishwalnut.qpon/f/x', lista),
        isTrue,
      );
      expect(
        BrowserHelper.urlEhAnuncio('https://exemplo.com/ads/banner.js', lista),
        isTrue,
      );
      expect(
        BrowserHelper.urlEhAnuncio('https://exemplo.com/capitulo/1', lista),
        isFalse,
      );
      expect(
        BrowserHelper.urlEhAnuncio('https://nexustoons.com/api/x', lista),
        isFalse,
      );
    });

    test('lista padrão pega a rede dos pop-ups do Nexus', () {
      const lista = BrowserHelper.defaultAdDomains;
      for (final url in [
        'https://cc.leedbrott.com/sfiSVdtOsMv/156269',
        'https://semicticken.com/1clkn/156312',
        'https://fs.pistilairwash.cfd/sbx/f/156269',
        'https://ep1.adtrafficquality.google/getconfig/sodar',
        'https://fundingchoicesmessages.google.com/i/ca-pub-1',
      ]) {
        expect(BrowserHelper.urlEhAnuncio(url, lista), isTrue, reason: url);
      }
      // O próprio site e o reCAPTCHA do Google continuam passando
      expect(
        BrowserHelper.urlEhAnuncio(
          'https://www.nexusmangas.com/assets/entries/pages.js',
          lista,
        ),
        isFalse,
      );
      expect(
        BrowserHelper.urlEhAnuncio(
          'https://www.google.com/recaptcha/api2/aframe',
          lista,
        ),
        isFalse,
      );
    });
  });

  group('isSameOriginHost', () {
    test('mesmo host ou subdomínio', () {
      expect(
        BrowserHelper.isSameOriginHost('https://site.com/a', 'site.com'),
        isTrue,
      );
      expect(
        BrowserHelper.isSameOriginHost('https://img.site.com/a', 'site.com'),
        isTrue,
      );
    });

    test('outro host com o nome no caminho não conta', () {
      expect(
        BrowserHelper.isSameOriginHost(
          'https://outro.com/site.com',
          'site.com',
        ),
        isFalse,
      );
    });
  });

  group('getAdBlockScript', () {
    test('leva as listas como JSON e cancela navegação para fora', () async {
      final js = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: 'nexustoons.com',
        adDomains: const ['ravishwalnut.qpon'],
        allowedDomains: const ['leituramanga.net'],
      );

      expect(js, contains('const AD_LIST = ["ravishwalnut.qpon"]'));
      expect(js, contains('"nexustoons.com"'));
      expect(js, contains('"leituramanga.net"'));
      // Diagnóstico e bloqueio por script desligados por padrão
      expect(js, contains('const DIAGNOSTICO = false;'));
      expect(js, contains('const BLOQUEAR_NAVEGACAO = false;'));
      // Bloqueio de scripts/quadros de anúncio ligado por padrão
      expect(js, contains('const BLOQUEAR_ELEMENTOS = true;'));
      // Remoção do que fica preso no <html> e blocos do Google escondidos
      expect(js, contains('const REMOVER_FORA_DO_BODY = true;'));
      expect(js, contains("el.tagName === 'HEAD' || el.tagName === 'BODY'"));
      // Lista de seletores escondidos vira uma string JS (via JSON)
      expect(
        js,
        contains(
          'estilo.replaceSync("ins.adsbygoogle, #mjsDonationModal '
          '{ display: none !important; }");',
        ),
      );
    });

    test('regra do <html> pode ser desligada', () async {
      final js = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: 'nexustoons.com',
        adDomains: const [],
        allowedDomains: const [],
        removerForaDoBody: false,
      );

      expect(js, contains('const REMOVER_FORA_DO_BODY = false;'));
    });

    // O script vai como texto para o navegador: um erro de sintaxe (ex.: uma
    // interpolação do Dart no lugar errado) desligaria o adblock inteiro sem
    // aviso. O Node confere a sintaxe; sem Node na máquina, o teste é pulado.
    test('JS gerado tem sintaxe válida', () async {
      final pasta = Directory.systemTemp.createTempSync('adblock_js');
      addTearDown(() => pasta.deleteSync(recursive: true));
      final variantes = {
        'padrao': await BrowserHelper.getAdBlockScript(
          sessionOriginHost: 'www.nexusmangas.com',
          adDomains: BrowserHelper.defaultAdDomains,
          allowedDomains: BrowserHelper.defaultAllowedDomains,
        ),
        'tudo_ligado': await BrowserHelper.getAdBlockScript(
          sessionOriginHost: 'www.nexusmangas.com',
          adDomains: const ['exemplo.com', 'exemplo.com/ads/'],
          allowedDomains: const [],
          diagnostico: true,
          bloquearNavegacaoPorScript: true,
        ),
      };
      for (final MapEntry(key: nome, value: js) in variantes.entries) {
        final arquivo = File('${pasta.path}/$nome.js')..writeAsStringSync(js);
        final r = Process.runSync('node', ['--check', arquivo.path]);
        expect(r.exitCode, 0, reason: '$nome: ${r.stderr}');
      }
    }, skip: _temNode ? false : 'Node não encontrado no PATH');

    test('bloqueio por script (Navigation API) só quando pedido', () async {
      final js = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: 'nexustoons.com',
        adDomains: const [],
        allowedDomains: const [],
        bloquearNavegacaoPorScript: true,
      );

      expect(js, contains('const BLOQUEAR_NAVEGACAO = true;'));
      expect(js, contains("addEventListener('navigate'"));
      expect(js, contains('e.preventDefault()'));
    });

    test('modo diagnóstico liga a anotação de falhas na página', () async {
      final js = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: 'nexustoons.com',
        adDomains: const [],
        allowedDomains: const [],
        diagnostico: true,
      );

      expect(js, contains('const DIAGNOSTICO = true;'));
      expect(js, contains('window.__mangaDiag'));
      // Diz se a recusa veio da Cloudflare ou do servidor do site
      expect(js, contains("cabecalho('cf-mitigated')"));
      expect(js, contains('DESAFIO CLOUDFLARE'));
      // Resposta opaca (no-cors) vem com status 0 mesmo quando deu certo
      expect(js, contains("r.type !== 'opaque'"));
      // A string Dart não é "raw": o JS precisa receber \s, e não só "s"
      expect(js, contains(r'.replace(/\s+/g'));
    });
  });

  group('scriptRolagem', () {
    test('leva a configuração como JSON, com o fator base à parte', () {
      final js = BrowserHelper.scriptRolagem(
        const ConfigRolagem(ativa: true, intensidade: 60, suavidade: 4),
        fatorBase: 0.2,
      );

      expect(
        js,
        contains(
          'var CONFIG = {"ativa":true,"base":0.2,"intensidade":0.6,"tau":100};',
        ),
      );
      expect(js, isNot(contains('__CONFIG__')));
    });

    test('rodar de novo na página só troca a configuração', () {
      final js = BrowserHelper.scriptRolagem(
        ConfigRolagem.padrao,
        fatorBase: 1,
      );

      expect(
        js,
        contains(
          'if (window.__mangaRolagem) { window.__mangaRolagem.configurar(CONFIG); return; }',
        ),
      );
    });

    test('precisa poder cancelar a rolagem e respeita zoom e página', () {
      final js = BrowserHelper.scriptRolagem(
        ConfigRolagem.padrao,
        fatorBase: 1,
      );

      // Sem passive: false o preventDefault da roda é ignorado
      expect(
        js,
        contains("addEventListener('wheel', aoGirar, { passive: false })"),
      );
      expect(js, contains('e.defaultPrevented || e.ctrlKey'));
      expect(js, contains("behavior: 'instant'"));
    });

    test('desligada continua instalável e só fica inativa', () {
      final js = BrowserHelper.scriptRolagem(
        ConfigRolagem.padrao.copyWith(ativa: false, suavidade: 0),
        fatorBase: 100 / 530,
      );

      expect(js, contains('"ativa":false'));
      expect(js, contains('"tau":0'));
    });
  });

  group('parseChapter', () {
    test('título em português e inglês', () {
      expect(BrowserHelper.parseChapter(title: 'Capítulo 16'), 16);
      expect(BrowserHelper.parseChapter(title: 'Cap. 918 - Wano'), 918);
      expect(BrowserHelper.parseChapter(title: 'Chapter 103 - Title'), 103);
    });

    test('sem número no título usa a URL', () {
      expect(
        BrowserHelper.parseChapter(
          title: 'One Piece',
          url: 'https://site.com/manga/one-piece/chapter/45/',
        ),
        45,
      );
      expect(
        BrowserHelper.parseChapter(
          title: null,
          url: 'https://site.com/manga/capitulo-12',
        ),
        12,
      );
    });

    test('número no nome do mangá não é confundido com o capítulo', () {
      expect(
        BrowserHelper.parseChapterFromUrl(
          'https://site.com/manga/6th-degree-capitulo-255/',
        ),
        255,
      );
      expect(
        BrowserHelper.parseChapter(title: '6th Degree - Capítulo 255'),
        255,
      );
      expect(BrowserHelper.parseChapter(title: 'Capítulo 47/255'), 47);
    });

    test('sem capítulo em lugar nenhum devolve null', () {
      expect(
        BrowserHelper.parseChapter(
          title: 'One Piece',
          url: 'https://site.com/manga/one-piece',
        ),
        isNull,
      );
    });
  });
}
