import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Etapas da atualização no Windows, na ordem em que acontecem.
enum EtapaAtualizacao { baixando, permissao, instalando }

/// Atualização no Windows, do download até o app reabrir.
///
/// Baixa o instalador mostrando o progresso, pede a permissão de
/// administrador e abre o instalador com `/ATUALIZAR`: ele mostra só a barra
/// de progresso, espera o app fechar, mantém os dados e abre o app de novo ao
/// terminar. Depois de abrir o instalador, este diálogo fecha o app.
///
/// Os parâmetros opcionais existem para os testes trocarem a rede, a pasta e
/// o sistema.
class AtualizacaoDialog extends StatefulWidget {
  final String versaoAtual;
  final String novaVersao;
  final String urlDownload;

  /// Abre o executável com elevação (UAC); devolve se o usuário aceitou.
  final Future<bool> Function(String exe, List<String> args) iniciarElevado;
  final http.Client? cliente;
  final Future<Directory> Function() pastaTemporaria;
  final VoidCallback encerrarApp;

  /// Tempo mostrando "Fechando para instalar" antes de fechar o app.
  final Duration esperaAntesDeFechar;

  const AtualizacaoDialog({
    super.key,
    required this.versaoAtual,
    required this.novaVersao,
    required this.urlDownload,
    required this.iniciarElevado,
    required this.pastaTemporaria,
    required this.encerrarApp,
    this.cliente,
    this.esperaAntesDeFechar = const Duration(milliseconds: 900),
  });

  /// Nome do instalador baixado, na pasta temporária.
  static const String nomeInstalador = 'manga_manager_update.exe';

  @override
  State<AtualizacaoDialog> createState() => _AtualizacaoDialogState();
}

class _CanceladoPeloUsuario implements Exception {}

/// Falha com a mensagem que vai para a tela.
class _FalhaAtualizacao implements Exception {
  final String mensagem;
  _FalhaAtualizacao(this.mensagem);
}

class _AtualizacaoDialogState extends State<AtualizacaoDialog> {
  late final http.Client _cliente = widget.cliente ?? http.Client();

  EtapaAtualizacao _etapa = EtapaAtualizacao.baixando;
  String? _erro;
  File? _instalador;

  int _recebidos = 0;
  int? _total;
  double _bytesPorSegundo = 0;

  StreamSubscription<List<int>>? _download;
  Completer<void>? _fimDoDownload;

  @override
  void initState() {
    super.initState();
    unawaited(_baixarEInstalar());
  }

  @override
  void dispose() {
    _download?.cancel();
    if (widget.cliente == null) _cliente.close();
    super.dispose();
  }

  Future<void> _baixarEInstalar() async {
    setState(() {
      _etapa = EtapaAtualizacao.baixando;
      _erro = null;
      _recebidos = 0;
      _total = null;
      _bytesPorSegundo = 0;
    });
    try {
      _instalador = await _baixar();
    } on _CanceladoPeloUsuario {
      return;
    } catch (e) {
      if (mounted) setState(() => _erro = _mensagemDeErro(e));
      return;
    }
    await _instalar();
  }

  Future<File> _baixar() async {
    final pasta = await widget.pastaTemporaria();
    final arquivo = File(p.join(pasta.path, AtualizacaoDialog.nomeInstalador));

    final resposta = await _cliente.send(
      http.Request('GET', Uri.parse(widget.urlDownload)),
    );
    if (resposta.statusCode != 200) {
      throw _FalhaAtualizacao(
        'O servidor respondeu ${resposta.statusCode} ao baixar a atualização.',
      );
    }
    if (mounted) setState(() => _total = resposta.contentLength);

    // Gravação síncrona, pedaço a pedaço (dezenas de KB, frações de
    // milissegundo cada): nenhuma operação de arquivo fica pendente quando o
    // download termina, é cancelado ou falha
    final destino = arquivo.openSync(mode: FileMode.write);
    final relogio = Stopwatch()..start();
    var ultimaTela = 0;
    final fim = _fimDoDownload = Completer<void>();
    var completo = false;
    try {
      final download = _download = resposta.stream.listen(
        null,
        onDone: () {
          if (!fim.isCompleted) fim.complete();
        },
        onError: (Object e) {
          if (!fim.isCompleted) fim.completeError(e);
        },
        cancelOnError: true,
      );
      download.onData((pedaco) {
        try {
          destino.writeFromSync(pedaco);
        } catch (e) {
          download.cancel();
          if (!fim.isCompleted) fim.completeError(e);
          return;
        }
        _recebidos += pedaco.length;
        // A tela acompanha a cada 100 ms, não a cada pedaço
        final agora = relogio.elapsedMilliseconds;
        if (agora - ultimaTela >= 100 && mounted) {
          ultimaTela = agora;
          setState(() {
            if (agora > 0) _bytesPorSegundo = _recebidos * 1000 / agora;
          });
        }
      });
      await fim.future;
      completo = true;
    } finally {
      _download = null;
      destino.closeSync();
      if (!completo) _apagar(arquivo);
    }
    if (mounted) setState(() {});

    // Download incompleto ou algo que não é um programa (ex.: página de erro)
    final total = _total;
    if (total != null && _recebidos != total) {
      _apagar(arquivo);
      throw _FalhaAtualizacao(
        'O download veio incompleto ($_recebidos de $total bytes).',
      );
    }
    if (!_ehExecutavel(arquivo)) {
      _apagar(arquivo);
      throw _FalhaAtualizacao('O arquivo baixado não é um instalador válido.');
    }
    return arquivo;
  }

  /// Todo .exe começa com "MZ".
  bool _ehExecutavel(File arquivo) {
    final leitura = arquivo.openSync();
    try {
      final inicio = leitura.readSync(2);
      return inicio.length == 2 && inicio[0] == 0x4D && inicio[1] == 0x5A;
    } finally {
      leitura.closeSync();
    }
  }

  void _apagar(File arquivo) {
    try {
      if (arquivo.existsSync()) arquivo.deleteSync();
    } catch (_) {}
  }

  Future<void> _instalar() async {
    final instalador = _instalador;
    if (instalador == null || !mounted) return;
    setState(() {
      _etapa = EtapaAtualizacao.permissao;
      _erro = null;
    });

    bool aceitou;
    try {
      aceitou = await widget.iniciarElevado(instalador.path, ['/ATUALIZAR']);
    } catch (e) {
      aceitou = false;
    }
    if (!mounted) return;
    if (!aceitou) {
      setState(
        () => _erro =
            'A permissão de administrador foi recusada. Sem ela o Windows '
            'não deixa instalar a nova versão.',
      );
      return;
    }

    // O instalador espera o app fechar para trocar os arquivos
    setState(() => _etapa = EtapaAtualizacao.instalando);
    await Future<void>.delayed(widget.esperaAntesDeFechar);
    widget.encerrarApp();
  }

  void _cancelar() {
    final fim = _fimDoDownload;
    // Sem esperar o cancel(): o download para de receber na hora, e o
    // _baixar fecha e apaga o arquivo assim que o fim é marcado
    unawaited(_download?.cancel());
    _download = null;
    if (fim != null && !fim.isCompleted) {
      fim.completeError(_CanceladoPeloUsuario());
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _tentarDeNovo() {
    // Com o instalador já baixado, só falta a permissão
    if (_etapa == EtapaAtualizacao.permissao && _instalador != null) {
      unawaited(_instalar());
    } else {
      unawaited(_baixarEInstalar());
    }
  }

  String _mensagemDeErro(Object e) {
    if (e is _FalhaAtualizacao) return e.mensagem;
    if (e is SocketException || e is http.ClientException) {
      return 'Sem conexão com o GitHub. Verifique a internet e tente de novo.';
    }
    if (e is FileSystemException) {
      return 'Não foi possível gravar o instalador: ${e.message}';
    }
    return 'Falha ao baixar a atualização: $e';
  }

  static String _mb(num bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final baixando = _etapa == EtapaAtualizacao.baixando && _erro == null;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.system_update, color: tema.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text('Atualizando para a v${widget.novaVersao}')),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Versão atual: v${widget.versaoAtual}',
                style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _Passo(
                numero: 1,
                titulo: 'Baixar a atualização',
                estado: _estadoDe(EtapaAtualizacao.baixando),
                detalhe: _etapa == EtapaAtualizacao.baixando
                    ? _progressoDoDownload(tema)
                    : null,
              ),
              _Passo(
                numero: 2,
                titulo: 'Permissão do Windows',
                estado: _estadoDe(EtapaAtualizacao.permissao),
                detalhe: _etapa == EtapaAtualizacao.permissao && _erro == null
                    ? const Text(
                        'Aceite o aviso de administrador do Windows para '
                        'instalar.',
                      )
                    : null,
              ),
              _Passo(
                numero: 3,
                titulo: 'Instalar e reabrir',
                estado: _estadoDe(EtapaAtualizacao.instalando),
                ultimo: true,
                detalhe: _etapa == EtapaAtualizacao.instalando
                    ? const Text(
                        'Fechando para instalar. O Manga Manager abre de novo '
                        'sozinho ao terminar.',
                      )
                    : const Text(
                        'O app fecha, instala a nova versão e abre de novo '
                        'sozinho. Seus mangás e capas são mantidos.',
                      ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tema.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _erro!,
                    style: TextStyle(color: tema.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (baixando)
            TextButton(onPressed: _cancelar, child: const Text('Cancelar')),
          if (_erro != null) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
            ElevatedButton(
              onPressed: _tentarDeNovo,
              child: const Text('Tentar de novo'),
            ),
          ],
        ],
      ),
    );
  }

  _EstadoPasso _estadoDe(EtapaAtualizacao etapa) {
    if (etapa.index < _etapa.index) return _EstadoPasso.feito;
    if (etapa.index > _etapa.index) return _EstadoPasso.pendente;
    return _erro != null ? _EstadoPasso.erro : _EstadoPasso.atual;
  }

  Widget _progressoDoDownload(ThemeData tema) {
    final total = _total;
    final fracao = (total != null && total > 0) ? _recebidos / total : null;
    final partes = <String>[
      if (fracao != null) '${(fracao * 100).floor()}%',
      total != null
          ? '${_mb(_recebidos)} de ${_mb(total)} MB'
          : '${_mb(_recebidos)} MB',
      if (_bytesPorSegundo > 0 && _erro == null)
        '${_mb(_bytesPorSegundo)} MB/s',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: _erro != null ? 0 : fracao),
        const SizedBox(height: 6),
        Text(
          partes.join(' · '),
          style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

enum _EstadoPasso { pendente, atual, feito, erro }

class _Passo extends StatelessWidget {
  final int numero;
  final String titulo;
  final _EstadoPasso estado;
  final Widget? detalhe;
  final bool ultimo;

  const _Passo({
    required this.numero,
    required this.titulo,
    required this.estado,
    this.detalhe,
    this.ultimo = false,
  });

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final Widget marcador = switch (estado) {
      _EstadoPasso.feito => const Icon(
        Icons.check_circle,
        color: Colors.green,
        size: 24,
      ),
      _EstadoPasso.erro => Icon(Icons.error, color: cores.error, size: 24),
      _EstadoPasso.atual => const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(3),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
      _EstadoPasso.pendente => CircleAvatar(
        radius: 12,
        backgroundColor: cores.surfaceContainerHighest,
        child: Text(
          '$numero',
          style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
        ),
      ),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          marcador,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: estado == _EstadoPasso.pendente
                          ? FontWeight.normal
                          : FontWeight.bold,
                      color: estado == _EstadoPasso.pendente
                          ? cores.onSurfaceVariant
                          : null,
                    ),
                  ),
                ),
                if (detalhe != null) ...[
                  const SizedBox(height: 6),
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 13),
                    child: detalhe!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
