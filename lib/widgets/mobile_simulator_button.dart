import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_size/window_size.dart' as window_size;

class MobileSimulatorButton extends StatelessWidget {
  const MobileSimulatorButton({super.key});

  void _redimensionarJanela(double largura, double altura) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      window_size.setWindowMinSize(const Size(300, 400));
      window_size.setWindowMaxSize(const Size(4096, 4096));
      window_size.setWindowFrame(Rect.fromLTWH(100, 100, largura, altura));
    }
  }

  void _mostrarMenuSimuladorCelular(BuildContext context) {
    final TextEditingController larguraController = TextEditingController(
      text: '390',
    );
    final TextEditingController alturaController = TextEditingController(
      text: '844',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Simulador de Tela (Windows)',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Escolha um modelo pronto:',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                _botaoOpcaoCelular(
                  dialogContext,
                  'iPhone Pequeno (SE)',
                  375,
                  667,
                ),
                _botaoOpcaoCelular(
                  dialogContext,
                  'iPhone Maior (14/15 Pro Max)',
                  430,
                  932,
                ),
                _botaoOpcaoCelular(
                  dialogContext,
                  'Android Pequeno (Compacto)',
                  360,
                  800,
                ),
                _botaoOpcaoCelular(
                  dialogContext,
                  'Android Maior (Moderno/Gamer)',
                  412,
                  915,
                ),
                const Divider(height: 24),
                Text(
                  'Ou digite valores personalizados (X e Y):',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: larguraController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecor(context, 'Largura (X em pixels)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: alturaController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecor(context, 'Altura (Y em pixels)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final double? w = double.tryParse(larguraController.text);
                final double? h = double.tryParse(alturaController.text);
                if (w != null && h != null) {
                  _redimensionarJanela(w, h);
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
  }

  Widget _botaoOpcaoCelular(
    BuildContext context,
    String nome,
    double w,
    double h,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
        onPressed: () {
          _redimensionarJanela(w, h);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '$nome\n(${w.toInt()} x ${h.toInt()})',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(BuildContext context, String label) =>
      InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontSize: 12),
      ),
      icon: const Icon(Icons.phone_android, size: 16),
      label: const Text('Simular Celular'),
      onPressed: () => _mostrarMenuSimuladorCelular(context),
    );
  }
}
