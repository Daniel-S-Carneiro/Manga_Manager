import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/utils/config_rolagem.dart';

void main() {
  group('ConfigRolagem.deTextos', () {
    test('sem nada salvo usa o padrão', () {
      expect(ConfigRolagem.deTextos(), ConfigRolagem.padrao);
    });

    test('lê os valores salvos', () {
      final c = ConfigRolagem.deTextos(
        ativa: 'false',
        intensidade: '60',
        suavidade: '7',
      );
      expect(c.ativa, isFalse);
      expect(c.intensidade, 60);
      expect(c.suavidade, 7);
    });

    test('número inválido fica no padrão e fora da faixa é limitado', () {
      final invalido = ConfigRolagem.deTextos(
        intensidade: 'abc',
        suavidade: '',
      );
      expect(invalido.intensidade, ConfigRolagem.padrao.intensidade);
      expect(invalido.suavidade, ConfigRolagem.padrao.suavidade);

      final fora = ConfigRolagem.deTextos(intensidade: '5000', suavidade: '-3');
      expect(fora.intensidade, ConfigRolagem.intensidadeMaxima);
      expect(fora.suavidade, 0);

      final baixo = ConfigRolagem.deTextos(intensidade: '1');
      expect(baixo.intensidade, ConfigRolagem.intensidadeMinima);
    });
  });

  test('suavidade vira tempo do deslize e nome no painel', () {
    expect(ConfigRolagem.padrao.copyWith(suavidade: 0).tauMs, 0);
    expect(ConfigRolagem.padrao.copyWith(suavidade: 4).tauMs, 100);
    expect(
      ConfigRolagem.padrao.copyWith(suavidade: 0).nomeSuavidade,
      'Desligada',
    );
    expect(ConfigRolagem.padrao.copyWith(suavidade: 2).nomeSuavidade, 'Leve');
    expect(ConfigRolagem.padrao.copyWith(suavidade: 5).nomeSuavidade, 'Média');
    expect(ConfigRolagem.padrao.copyWith(suavidade: 10).nomeSuavidade, 'Alta');
  });

  test('copyWith e igualdade por valor', () {
    final c = ConfigRolagem.padrao.copyWith(intensidade: 150);
    expect(c.intensidade, 150);
    expect(c.ativa, ConfigRolagem.padrao.ativa);
    expect(c, isNot(ConfigRolagem.padrao));
    expect(c.copyWith(intensidade: 100), ConfigRolagem.padrao);
  });
}
