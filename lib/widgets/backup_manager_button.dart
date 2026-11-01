import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/backup_service.dart';
import '../controllers/refresh_controller.dart';
import '../utils/file_picker_helper.dart';

class BackupManagerButton extends StatefulWidget {
  final VoidCallback onBackupRestored;

  const BackupManagerButton({super.key, required this.onBackupRestored});

  @override
  State<BackupManagerButton> createState() => _BackupManagerButtonState();
}

class _BackupManagerButtonState extends State<BackupManagerButton> {
  bool _isLoading = false;
  final BackupService _backupService = BackupService();

  void _mostrarFeedback(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _atualizarInterface() {
    imageCache.clear();
    imageCache.clearLiveImages();
    widget.onBackupRestored();
    globalRefreshController.refresh();
  }

  Future<void> _fazerBackup() async {
    Navigator.pop(context);
    setState(() => _isLoading = true);

    String? tempPath;
    try {
      // O diálogo de salvar grava os bytes ele mesmo (file_picker 13+): o
      // backup é gerado antes, numa pasta temporária, e depois entregue a ele
      final tempDir = await getTemporaryDirectory();
      tempPath = p.join(
        tempDir.path,
        'manga_backup_${DateTime.now().millisecondsSinceEpoch}.tar.gz',
      );
      await _backupService.exportBackup(tempPath);
      final bytes = await File(tempPath).readAsBytes();

      final destino = await FilePicker.saveFile(
        dialogTitle: 'Salvar Backup',
        fileName: 'manga_backup.tar.gz',
        bytes: bytes,
        mimeType: 'application/gzip',
      );
      if (destino == null) return;

      // Garante a extensão quando o destino é um arquivo local (no Android a
      // URI é content:// e o nome fica a cargo do sistema)
      if (destino.scheme == 'file') {
        final salvo = destino.toFilePath();
        if (!salvo.toLowerCase().endsWith('.tar.gz')) {
          await File(salvo).rename('$salvo.tar.gz');
        }
      }

      _mostrarFeedback('Backup exportado com sucesso!');
    } catch (e) {
      _mostrarFeedback(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (tempPath != null) {
        try {
          await File(tempPath).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executarRestauracao({required bool merge}) async {
    Navigator.pop(context);

    final arquivo = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['gz', 'tar'],
    );

    if (arquivo == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final caminho = await caminhoLocalDoArquivo(arquivo);
      final msg = await _backupService.restoreBackup(caminho, merge: merge);
      _mostrarFeedback(msg);
      _atualizarInterface();
    } catch (e) {
      _mostrarFeedback(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _abrirMenuOpcoes() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Gerenciador de Backup',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.blue),
                  title: const Text('Criar Backup (Exportar .tar.gz)'),
                  subtitle: const Text(
                    'Salva o BD e a pasta de capas num arquivo comprimido',
                  ),
                  onTap: _fazerBackup,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                  ),
                  title: const Text('Restaurar (Substituir Tudo)'),
                  subtitle: const Text(
                    'Apaga o atual e coloca o do arquivo .tar.gz',
                  ),
                  onTap: () => _executarRestauracao(merge: false),
                ),
                ListTile(
                  leading: const Icon(Icons.merge_type, color: Colors.green),
                  title: const Text('Restaurar (Mesclar / Ignorar Iguais)'),
                  subtitle: const Text(
                    'Mantém o atual e adiciona apenas os nomes diferentes',
                  ),
                  onTap: () => _executarRestauracao(merge: true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontSize: 12),
      ),
      icon: _isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.backup, size: 16),
      label: Text(_isLoading ? 'Processando...' : 'Backup / Restaurar'),
      onPressed: _isLoading ? null : _abrirMenuOpcoes,
    );
  }
}
