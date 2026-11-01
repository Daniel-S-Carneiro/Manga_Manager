import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/config_rolagem.dart';

/// Painel da rolagem do mouse, aberto pela barra flutuante do leitor. Não é
/// modal: dá para rolar a página com ele aberto e sentir a diferença.
///
/// [onAlterando] recebe cada passo de um controle deslizante (só o painel
/// muda); [onConfirmar] recebe o valor final, que o leitor aplica na página e
/// salva.
class PainelRolagem extends StatelessWidget {
  final ValueListenable<ConfigRolagem> config;
  final ValueChanged<ConfigRolagem> onAlterando;
  final ValueChanged<ConfigRolagem> onConfirmar;
  final VoidCallback onFechar;

  const PainelRolagem({
    super.key,
    required this.config,
    required this.onAlterando,
    required this.onConfirmar,
    required this.onFechar,
  });

  static const TextStyle _texto = TextStyle(color: Colors.white, fontSize: 14);
  static const TextStyle _dica = TextStyle(color: Colors.white54, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConfigRolagem>(
      valueListenable: config,
      builder: (context, c, _) {
        return Material(
          color: Colors.transparent,
          child: Container(
            width: 320,
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mouse, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Rolagem do mouse',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                      tooltip: 'Fechar',
                      onPressed: onFechar,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Rolagem personalizada', style: _texto),
                      ),
                      Switch(
                        value: c.ativa,
                        onChanged: (v) => onConfirmar(c.copyWith(ativa: v)),
                      ),
                    ],
                  ),
                ),
                if (!c.ativa)
                  const Padding(
                    padding: EdgeInsets.only(right: 12, bottom: 4),
                    child: Text(
                      'Desligada: o app não mexe na rolagem do navegador.',
                      style: _dica,
                    ),
                  ),
                const SizedBox(height: 4),
                Text('Distância por giro: ${c.intensidade}%', style: _texto),
                Slider(
                  key: const Key('rolagem_intensidade'),
                  value: c.intensidade.toDouble(),
                  min: ConfigRolagem.intensidadeMinima.toDouble(),
                  max: ConfigRolagem.intensidadeMaxima.toDouble(),
                  divisions:
                      (ConfigRolagem.intensidadeMaxima -
                          ConfigRolagem.intensidadeMinima) ~/
                      10,
                  label: '${c.intensidade}%',
                  onChanged: c.ativa
                      ? (v) => onAlterando(c.copyWith(intensidade: v.round()))
                      : null,
                  onChangeEnd: c.ativa
                      ? (v) => onConfirmar(c.copyWith(intensidade: v.round()))
                      : null,
                ),
                Text(
                  'Suavidade: ${c.nomeSuavidade} (${c.suavidade})',
                  style: _texto,
                ),
                Slider(
                  key: const Key('rolagem_suavidade'),
                  value: c.suavidade.toDouble(),
                  min: 0,
                  max: ConfigRolagem.suavidadeMaxima.toDouble(),
                  divisions: ConfigRolagem.suavidadeMaxima,
                  label: c.nomeSuavidade,
                  onChanged: c.ativa
                      ? (v) => onAlterando(c.copyWith(suavidade: v.round()))
                      : null,
                  onChangeEnd: c.ativa
                      ? (v) => onConfirmar(c.copyWith(suavidade: v.round()))
                      : null,
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Text(
                    '100% ≈ um navegador comum. Role a página com o painel '
                    'aberto para testar.',
                    style: _dica,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: c == ConfigRolagem.padrao
                        ? null
                        : () => onConfirmar(ConfigRolagem.padrao),
                    child: const Text('Restaurar padrão'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
