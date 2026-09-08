import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../database/db_helper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:io' as io;

class EditMangaFormWidget extends StatefulWidget {
  final Map<String, dynamic> manga;
  final VoidCallback onMangaUpdated;
  final VoidCallback onDelete;

  const EditMangaFormWidget({
    super.key,
    required this.manga,
    required this.onMangaUpdated,
    required this.onDelete,
  });

  @override
  State<EditMangaFormWidget> createState() => _EditMangaFormWidgetState();
}

class _EditMangaFormWidgetState extends State<EditMangaFormWidget> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nomePtController;
  late TextEditingController _nomeEnController;
  late TextEditingController _capituloController;
  late TextEditingController _linkUrlController;
  String? _capaPath;

  final List<Map<String, dynamic>> _statusOptions = [
    {'label': 'Lendo', 'icon': Icons.menu_book_rounded, 'color': Colors.blue},
    {
      'label': 'Completo',
      'icon': Icons.check_circle_rounded,
      'color': Colors.green,
    },
    {
      'label': 'Dropado',
      'icon': Icons.cancel_rounded,
      'color': Colors.redAccent,
    },
    {
      'label': 'Planejo Ler',
      'icon': Icons.watch_later_rounded,
      'color': Colors.orange,
    },
  ];

  late String _statusSelecionado;

  @override
  void initState() {
    super.initState();
    _nomePtController = TextEditingController(
      text: widget.manga['nome_pt'] ?? '',
    );
    _nomeEnController = TextEditingController(
      text: widget.manga['nome_en'] ?? '',
    );
    _capituloController = TextEditingController(
      text: '${widget.manga['capitulo'] ?? 1}',
    );
    _linkUrlController = TextEditingController(
      text: widget.manga['link_url'] ?? '',
    );
    _capaPath = null;

    final statusBanco = widget.manga['status_leitura'];
    _statusSelecionado =
        _statusOptions.any((opt) => opt['label'] == statusBanco)
        ? statusBanco
        : 'Lendo';
  }

  @override
  void dispose() {
    _nomePtController.dispose();
    _nomeEnController.dispose();
    _capituloController.dispose();
    _linkUrlController.dispose();
    super.dispose();
  }

  Future<void> _escolherNovaCapa() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );

      if (result != null && result.files.single.path != null) {
        String originalPath = result.files.single.path!;

        io.Directory capasDir = await DbHelper().getCapasDirectory();

        bool isWindows = !kIsWeb && Platform.isWindows;
        String extensao = isWindows ? p.extension(originalPath) : '.webp';
        String novoNome =
            'capa_${DateTime.now().millisecondsSinceEpoch}$extensao';
        String caminhoFinal = '${capasDir.path}/$novoNome';

        if (isWindows) {
          await File(originalPath).copy(caminhoFinal);
        } else {
          var resultCompress = await FlutterImageCompress.compressAndGetFile(
            originalPath,
            caminhoFinal,
            minWidth: 300,
            minHeight: 450,
            quality: 85,
            format: CompressFormat.webp,
          );
          if (resultCompress == null) {
            await File(originalPath).copy(caminhoFinal);
          }
        }

        setState(() => _capaPath = caminhoFinal);
      }
    } catch (e) {
      debugPrint('Erro ao processar imagem de edição: $e');
    }
  }

  Future<void> _salvarAlteracoes() async {
    if (_formKey.currentState!.validate()) {
      if (!kIsWeb && _capaPath != null && widget.manga['capa_path'] != null) {
        final oldFile = File(widget.manga['capa_path']);
        if (oldFile.existsSync()) {
          try {
            await FileImage(oldFile).evict();
            await oldFile.delete();
          } catch (e) {
            debugPrint('Erro ao excluir capa antiga: $e');
          }
        }
      }

      final dadosAtualizados = {
        'nome_pt': _nomePtController.text.trim(),
        'nome_en': _nomeEnController.text.trim().isEmpty
            ? null
            : _nomeEnController.text.trim(),
        'capitulo': int.tryParse(_capituloController.text) ?? 1,
        'link_url': _linkUrlController.text.trim().isEmpty
            ? null
            : _linkUrlController.text.trim(),
        'capa_path': _capaPath ?? widget.manga['capa_path'],
        'status_leitura': _statusSelecionado,
      };

      await DbHelper().updateManga(widget.manga['id'], dadosAtualizados);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onMangaUpdated();
    }
  }

  Future<void> _excluirManga() async {
    if (!kIsWeb) {
      final String? capaPath = widget.manga['capa_path'];
      if (capaPath != null && capaPath.isNotEmpty) {
        final file = File(capaPath);
        if (await file.exists()) {
          await FileImage(file).evict();
          await file.delete();
        }
      }
    }

    if (!mounted) return;
    Navigator.pop(context);
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.1),
            ),
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Editar Mangá',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nomePtController,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: _buildInputDecoration(
                      'Nome em Português',
                      theme,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'O nome em português é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nomeEnController,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: _buildInputDecoration('Nome em Inglês', theme),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _capituloController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: _buildInputDecoration('Capítulo Atual', theme)
                        .copyWith(
                          prefixIcon: IconButton(
                            icon: Icon(Icons.remove, color: colorScheme.error),
                            onPressed: () {
                              int val =
                                  int.tryParse(_capituloController.text) ?? 1;
                              if (val > 1) {
                                _capituloController.text = (val - 1).toString();
                              }
                            },
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.add, color: colorScheme.secondary),
                            onPressed: () {
                              int val =
                                  int.tryParse(_capituloController.text) ?? 0;
                              _capituloController.text = (val + 1).toString();
                            },
                          ),
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _linkUrlController,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: _buildInputDecoration(
                      'Link do site (https://...)',
                      theme,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: PopupMenuButton<String>(
                      initialValue: _statusSelecionado,
                      color: colorScheme.surfaceContainer,
                      constraints: const BoxConstraints(
                        minWidth: 370,
                        maxWidth: 400,
                      ),
                      onSelected: (String novoStatus) =>
                          setState(() => _statusSelecionado = novoStatus),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _statusOptions.firstWhere(
                                (e) => e['label'] == _statusSelecionado,
                              )['icon'],
                              color: _statusOptions.firstWhere(
                                (e) => e['label'] == _statusSelecionado,
                              )['color'],
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _statusSelecionado,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_drop_down,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (BuildContext context) =>
                          _statusOptions.map((status) {
                            return PopupMenuItem<String>(
                              value: status['label'],
                              child: SizedBox(
                                width: 300,
                                child: Row(
                                  children: [
                                    Icon(
                                      status['icon'],
                                      color: status['color'],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      status['label'],
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _escolherNovaCapa,
                    icon: Icon(
                      _capaPath != null
                          ? Icons.check_circle
                          : Icons.image_search_rounded,
                      color: _capaPath != null
                          ? colorScheme.primary
                          : Colors.amber,
                    ),
                    label: Text(
                      _capaPath != null
                          ? 'Capa Selecionada'
                          : 'Escolher Nova Capa',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _salvarAlteracoes,
                    child: Text(
                      'Salvar Alterações',
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _excluirManga,
                    icon: Icon(Icons.delete_forever, color: colorScheme.error),
                    label: Text(
                      'Excluir Mangá',
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: colorScheme.onSurface.withValues(alpha: 0.7),
        fontSize: 16,
      ),
      filled: true,

      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
  }
}
