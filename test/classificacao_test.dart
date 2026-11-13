import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/utils/classificacao.dart';

void main() {
  group('TipoLeitura', () {
    test('as chaves gravadas no banco não mudam', () {
      // Bancos e backups já têm essas chaves: trocar uma faz os itens
      // perderem o tipo
      expect(TipoLeitura.todos.map((t) => t.chave), [
        'manga',
        'manhwa',
        'manhua',
        'webtoon',
        'novel',
        'outro',
      ]);
    });

    test(
      'daChave acha o tipo e devolve nulo para sem tipo ou desconhecido',
      () {
        for (final tipo in TipoLeitura.todos) {
          expect(TipoLeitura.daChave(tipo.chave), same(tipo));
        }
        expect(TipoLeitura.daChave(null), isNull);
        expect(TipoLeitura.daChave(''), isNull);
        expect(TipoLeitura.daChave('chave_do_futuro'), isNull);
        // A chave é exata (o banco grava em minúsculas)
        expect(TipoLeitura.daChave('Manga'), isNull);
      },
    );
  });

  group('StatusLeitura', () {
    test('os valores gravados no banco não mudam', () {
      expect(StatusLeitura.todos.map((s) => s.valor), [
        'Lendo',
        'Completo',
        'Dropado',
        'Planejo Ler',
      ]);
    });

    test('doValor acha o status e devolve nulo para desconhecido', () {
      for (final status in StatusLeitura.todos) {
        expect(StatusLeitura.doValor(status.valor), same(status));
      }
      expect(StatusLeitura.doValor(null), isNull);
      expect(StatusLeitura.doValor('lendo'), isNull);
    });
  });

  group('FiltroTipo', () {
    test('todos, sem tipo e um tipo são diferentes entre si', () {
      const manhwa = FiltroTipo.de(TipoLeitura.manhwa);
      expect(FiltroTipo.todos.ehTodos, isTrue);
      expect(FiltroTipo.semTipo.ehTodos, isFalse);
      expect(FiltroTipo.semTipo.ehSemTipo, isTrue);
      expect(manhwa.ehTodos, isFalse);
      expect(manhwa.ehSemTipo, isFalse);
      expect(FiltroTipo.todos, isNot(FiltroTipo.semTipo));
      expect(manhwa, const FiltroTipo.de(TipoLeitura.manhwa));
      expect(manhwa, isNot(const FiltroTipo.de(TipoLeitura.manhua)));
      expect(
        [FiltroTipo.todos.nome, FiltroTipo.semTipo.nome, manhwa.nome],
        ['Todos', 'Sem tipo', 'Manhwa'],
      );
    });
  });

  group('FiltroLista', () {
    test('sem busca nem filtro não restringe nada', () {
      const filtro = FiltroLista(busca: '   ');
      expect(filtro.temFiltro, isFalse);
      expect(filtro.restringe, isFalse);
      expect(filtro.clausula().where, isNull);
      expect(filtro.clausula().args, isEmpty);
    });

    test('busca entre parênteses e com o texto aparado', () {
      final c = const FiltroLista(busca: ' one ').clausula();
      expect(c.where, '(nome_pt LIKE ? OR nome_en LIKE ?)');
      expect(c.args, ['%one%', '%one%']);
    });

    test('busca, tipo e status juntos', () {
      const filtro = FiltroLista(
        busca: 'a',
        tipo: FiltroTipo.de(TipoLeitura.webtoon),
        status: StatusLeitura.dropado,
      );
      expect(filtro.temFiltro, isTrue);
      final c = filtro.clausula();
      expect(
        c.where,
        '(nome_pt LIKE ? OR nome_en LIKE ?) AND tipo = ? AND '
        'status_leitura = ?',
      );
      expect(c.args, ['%a%', '%a%', 'webtoon', 'Dropado']);
    });

    test('sem tipo também pega chave desconhecida', () {
      final c = const FiltroLista(tipo: FiltroTipo.semTipo).clausula();
      expect(c.where, startsWith('(tipo IS NULL OR tipo NOT IN (?'));
      expect(c.args, TipoLeitura.todos.map((t) => t.chave));
      // Um "?" para cada chave
      expect('?'.allMatches(c.where!).length, c.args.length);
    });

    test('copiarCom e semFiltros', () {
      const base = FiltroLista(
        busca: 'x',
        tipo: FiltroTipo.semTipo,
        status: StatusLeitura.lendo,
      );
      expect(base.copiarCom(busca: 'y').busca, 'y');
      expect(base.copiarCom(busca: 'y').status, StatusLeitura.lendo);
      expect(base.copiarCom(limparStatus: true).status, isNull);
      expect(base.copiarCom(limparStatus: true).tipo, FiltroTipo.semTipo);
      expect(base.semFiltros(), const FiltroLista(busca: 'x'));
      expect(base.semFiltros().restringe, isTrue);
      expect(const FiltroLista().semFiltros().restringe, isFalse);
    });
  });
}
