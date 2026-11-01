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
