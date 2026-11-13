import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/utils/capa_helper.dart';

void main() {
  group('tamanhoDecodificado', () {
    test('card estreito no celular: a altura manda', () {
      // Redmi Note 8 Pro: densidade 2,75; card de ~190×320
      final t = CapaHelper.tamanhoDecodificado(190, 320, 2.75);
      expect(t.largura, isNull);
      // 320 × 2,75 = 880, arredondado para cima de 64 em 64
      expect(t.altura, 896);
    });

    test('card largo no computador: a largura manda', () {
      final t = CapaHelper.tamanhoDecodificado(300, 320, 1.25);
      expect(t.altura, isNull);
      // 300 × 1,25 = 375
      expect(t.largura, 384);
    });

    test('a gravação basta para o card no celular', () {
      final t = CapaHelper.tamanhoDecodificado(190, 320, 3);
      expect(t.altura!, lessThanOrEqualTo(CapaHelper.alturaGravada));
    });

    test('mudar pouco a largura não muda o tamanho decodificado', () {
      // 375 e 381 px caem na mesma faixa (até 384)
      final a = CapaHelper.tamanhoDecodificado(300, 320, 1.25);
      final b = CapaHelper.tamanhoDecodificado(305, 320, 1.25);
      expect(a, b);
    });

    test('largura desconhecida usa a altura', () {
      final t = CapaHelper.tamanhoDecodificado(double.infinity, 320, 2);
      expect(t.largura, isNull);
      expect(t.altura, 640);
    });

    test('nunca decodifica menos que um passo', () {
      final t = CapaHelper.tamanhoDecodificado(10, 20, 1);
      expect(t.altura, CapaHelper.passoDecodificacao);
    });
  });
}
