import 'package:flutter/material.dart';

class ErrorHandler {
  static void showFatalError(
    BuildContext context,
    dynamic error,
    StackTrace stack,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Erro Crítico'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Um erro inesperado ocorreu:\n\n$error\n\nStack:\n$stack',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
