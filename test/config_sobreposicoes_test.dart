import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/utils/config_sobreposicoes.dart';

void main() {
  group('decodificar', () {
    test('lista gravada, em minúsculas e sem vazios', () {
      expect(
        ConfigSobreposicoes.decodificar('["Site.com", " outro.net ", ""]'),
        ['site.com', 'outro.net'],
      );
    });

    test('nada gravado ou texto inválido vira lista vazia', () {
      expect(ConfigSobreposicoes.decodificar(null), isEmpty);
      expect(ConfigSobreposicoes.decodificar(''), isEmpty);
      expect(ConfigSobreposicoes.decodificar('{"a": 1}'), isEmpty);
      expect(ConfigSobreposicoes.decodificar('não é json'), isEmpty);
    });
  });

  group('atualizar', () {
    test('desligar acrescenta o site uma vez só, em ordem', () {
      var lista = ConfigSobreposicoes.atualizar([], 'site.com', ativa: false);
      lista = ConfigSobreposicoes.atualizar(lista, 'Site.com', ativa: false);
      lista = ConfigSobreposicoes.atualizar(lista, 'abc.net', ativa: false);
      expect(lista, ['abc.net', 'site.com']);
    });

    test('ligar tira o site e não mexe nos outros', () {
      final lista = ConfigSobreposicoes.atualizar(
        ['abc.net', 'site.com'],
        'site.com',
        ativa: true,
      );
      expect(lista, ['abc.net']);
    });

    test('domínio vazio não entra na lista', () {
      expect(ConfigSobreposicoes.atualizar([], '  ', ativa: false), isEmpty);
    });
  });
}
