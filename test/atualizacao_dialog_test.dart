// Falha rápido se algum passo ficar esperando para sempre
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manga_manager/widgets/atualizacao_dialog.dart';

/// Um "instalador" de mentira: começa com MZ, como todo .exe.
List<int> instaladorFalso(int tamanho) => [
  0x4D,
  0x5A,
  ...List<int>.filled(tamanho - 2, 0),
];

void main() {
  late Directory pasta;
  late int downloads;
  late List<List<String>> elevacoes;
  late int encerramentos;

  setUp(() {
    pasta = Directory.systemTemp.createTempSync('atualizacao_teste');
    downloads = 0;
    elevacoes = [];
    encerramentos = 0;
  });

  tearDown(() {
    if (pasta.existsSync()) pasta.deleteSync(recursive: true);
  });

  File arquivoBaixado() =>
      File('${pasta.path}${Platform.pathSeparator}manga_manager_update.exe');

  /// Desenha a tela, avançando o relógio do teste, até a condição valer. O
  /// arquivo é gravado de forma síncrona, então nada depende de tempo real.
  Future<void> ate(WidgetTester tester, bool Function() condicao) async {
    for (var i = 0; i < 100 && !condicao(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(condicao(), isTrue, reason: 'a condição não aconteceu a tempo');
  }

  Future<void> abrir(
    WidgetTester tester, {
    required http.Client cliente,
    Future<bool> Function()? aceitaPermissao,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => AtualizacaoDialog(
                versaoAtual: '2.1.0',
                novaVersao: '2.1.1',
                urlDownload: 'https://exemplo.com/MangaManager_Setup.exe',
                cliente: cliente,
                pastaTemporaria: () async => pasta,
                iniciarElevado: (exe, args) async {
                  elevacoes.add([exe, ...args]);
                  return aceitaPermissao == null ? true : aceitaPermissao();
                },
                encerrarApp: () => encerramentos++,
                esperaAntesDeFechar: Duration.zero,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
  }

  http.Client servidor(
    List<int> corpo, {
    int status = 200,
    int? contentLength,
  }) => MockClient.streaming((request, _) async {
    downloads++;
    return http.StreamedResponse(
      Stream.value(corpo),
      status,
      contentLength: contentLength ?? corpo.length,
    );
  });

  testWidgets('baixa, pede a permissão, abre o instalador e fecha o app', (
    tester,
  ) async {
    final pedacos = StreamController<List<int>>();
    final corpo = instaladorFalso(4000);
    final cliente = MockClient.streaming((request, _) async {
      downloads++;
      return http.StreamedResponse(
        pedacos.stream,
        200,
        contentLength: corpo.length,
      );
    });
    await abrir(tester, cliente: cliente);

    expect(find.text('Atualizando para a v2.1.1'), findsOneWidget);
    expect(find.text('Baixar a atualização'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    pedacos.add(corpo.sublist(0, 2000));
    pedacos.add(corpo.sublist(2000));
    await pedacos.close();
    await ate(tester, () => encerramentos == 1);

    expect(downloads, 1);
    expect(elevacoes, [
      [arquivoBaixado().path, '/ATUALIZAR'],
    ]);
    expect(arquivoBaixado().lengthSync(), 4000);
    expect(find.textContaining('Fechando para instalar'), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
  });

  testWidgets('permissão recusada: tenta de novo sem baixar outra vez', (
    tester,
  ) async {
    var aceita = false;
    await abrir(
      tester,
      cliente: servidor(instaladorFalso(1000)),
      aceitaPermissao: () async => aceita,
    );

    await ate(tester, () => elevacoes.length == 1);
    await tester.pump();
    expect(
      find.textContaining('permissão de administrador foi recusada'),
      findsOneWidget,
    );
    expect(encerramentos, 0);

    aceita = true;
    await tester.tap(find.text('Tentar de novo'));
    await ate(tester, () => encerramentos == 1);
    expect(elevacoes.length, 2);
    expect(downloads, 1);
  });

  testWidgets('erro do servidor: mostra e baixa de novo ao tentar', (
    tester,
  ) async {
    await abrir(tester, cliente: servidor([], status: 404));

    await ate(
      tester,
      () => find.textContaining('respondeu 404').evaluate().isNotEmpty,
    );
    expect(elevacoes, isEmpty);

    await tester.tap(find.text('Tentar de novo'));
    await ate(tester, () => downloads == 2);
  });

  testWidgets('arquivo que não é programa não é executado', (tester) async {
    await abrir(tester, cliente: servidor('<html>erro</html>'.codeUnits));

    await ate(
      tester,
      () => find
          .textContaining('não é um instalador válido')
          .evaluate()
          .isNotEmpty,
    );
    expect(elevacoes, isEmpty);
    expect(arquivoBaixado().existsSync(), isFalse);
  });

  testWidgets('download incompleto não é executado', (tester) async {
    await abrir(
      tester,
      cliente: servidor(instaladorFalso(500), contentLength: 1000),
    );

    await ate(
      tester,
      () => find.textContaining('incompleto').evaluate().isNotEmpty,
    );
    expect(elevacoes, isEmpty);
  });

  testWidgets('cancelar durante o download fecha a tela', (tester) async {
    final pedacos = StreamController<List<int>>();
    final cliente = MockClient.streaming((request, _) async {
      downloads++;
      return http.StreamedResponse(pedacos.stream, 200, contentLength: 5000);
    });
    await abrir(tester, cliente: cliente);

    pedacos.add(instaladorFalso(1000));
    await ate(tester, () => downloads == 1);
    await tester.tap(find.text('Cancelar'));
    await ate(tester, () => find.byType(AtualizacaoDialog).evaluate().isEmpty);

    expect(elevacoes, isEmpty);
    expect(encerramentos, 0);
    await ate(tester, () => !arquivoBaixado().existsSync());
    // Sem await: com a assinatura cancelada, o close() devolve um futuro da
    // zona raiz, que o relógio falso do teste não conclui
    unawaited(pedacos.close());
  });
}
