import 'dart:io' as io;

import 'package:flutter/material.dart';

import '../controllers/refresh_controller.dart';
import '../database/db_helper.dart';
import '../services/backup_service.dart';

/// Importa a biblioteca do Manga Manager a partir do [banco] dele, depois de
/// confirmar. Com a biblioteca daqui vazia, traz tudo (leituras, capas e
/// configurações); com leituras, acrescenta só as que faltam, pelo nome.
/// Devolve se importou.
Future<bool> importarDoMangaManager(BuildContext context, io.File banco) async {
  final mensageiro = ScaffoldMessenger.of(context);
  final navegador = Navigator.of(context, rootNavigator: true);

  final bool vazia;
  try {
    vazia = (await DbHelper().getMangas(limit: 1)).isEmpty;
  } catch (e) {
    _avisar(mensageiro, e, erro: true);
    return false;
  }
  if (!context.mounted) return false;

  final oQueFaz = vazia
      ? 'Traz as leituras, as capas e as configurações do Manga Manager '
            'para cá.'
      : 'Acrescenta as leituras do Manga Manager que ainda não estão aqui '
            '(pelo nome), com as capas. As que já estão aqui ficam como '
            'estão.';
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Importar do Manga Manager'),
      content: Text(
        '$oQueFaz\n\n'
        'Feche o Manga Manager antes de continuar. Ele não é alterado, e '
        'você pode desinstalá-lo depois de conferir a lista. Os logins dos '
        'sites não vêm junto.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Importar'),
        ),
      ],
    ),
  );
  if (confirmou != true || !context.mounted) return false;

  // Aguarde: o banco fica travado enquanto isso
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Importando a biblioteca...')),
          ],
        ),
      ),
    ),
  );

  try {
    final mensagem = await BackupService().importarDoMangaManager(
      banco,
      merge: !vazia,
    );
    navegador.pop();
    _avisar(mensageiro, mensagem);
    imageCache.clear();
    imageCache.clearLiveImages();
    globalRefreshController.refresh();
    return true;
  } catch (e) {
    navegador.pop();
    _avisar(mensageiro, e, erro: true);
    return false;
  }
}

void _avisar(
  ScaffoldMessengerState mensageiro,
  Object mensagem, {
  bool erro = false,
}) {
  mensageiro.showSnackBar(
    SnackBar(
      content: Text(mensagem.toString().replaceAll('Exception: ', '')),
      backgroundColor: erro ? Colors.red : Colors.green,
      duration: const Duration(seconds: 5),
    ),
  );
}
