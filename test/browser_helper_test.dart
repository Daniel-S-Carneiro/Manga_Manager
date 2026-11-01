import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/utils/browser_helper.dart';

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
    });

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
