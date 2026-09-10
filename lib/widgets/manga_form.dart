import 'dart:io';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../database/db_helper.dart';

class AddMangaFormWidget extends StatefulWidget {
  final VoidCallback onMangaSaved;

  const AddMangaFormWidget({super.key, required this.onMangaSaved});

  @override
  State<AddMangaFormWidget> createState() => _AddMangaFormWidgetState();
}

class _AddMangaFormWidgetState extends State<AddMangaFormWidget> {
  final _formKey = GlobalKey<FormState>();

  final _nomePtController = TextEditingController();
  final _nomeEnController = TextEditingController();
  final _linkUrlController = TextEditingController();
  final _capituloController = TextEditingController(text: '1');

  String? _capaSelecionadaPath;

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

  late Map<String, dynamic> _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = _statusOptions.first;
  }

  @override
  void dispose() {
    _nomePtController.dispose();
    _nomeEnController.dispose();
    _linkUrlController.dispose();
    _capituloController.dispose();
    super.dispose();
  }

  Future<void> _escolherEProcessarCapa() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );

      if (result != null && result.files.single.path != null) {
        String pathOriginal = result.files.single.path!;

        io.Directory capasDir = await DbHelper().getCapasDirectory();

        bool isWindows = !kIsWeb && Platform.isWindows;
        String extensao = isWindows ? p.extension(pathOriginal) : '.webp';
        String novoNome =
            'capa_${DateTime.now().millisecondsSinceEpoch}$extensao';
        String caminhoFinal = '${capasDir.path}/$novoNome';

        if (isWindows) {
          await File(pathOriginal).copy(caminhoFinal);
        } else {
          var resultCompress = await FlutterImageCompress.compressAndGetFile(
            pathOriginal,
            caminhoFinal,
            minWidth: 300,
            minHeight: 450,
            quality: 85,
            format: CompressFormat.webp,
          );
          if (resultCompress == null) {
            await File(pathOriginal).copy(caminhoFinal);
          }
        }

        setState(() => _capaSelecionadaPath = caminhoFinal);
      }
    } catch (e) {
      debugPrint('Erro ao processar imagem: $e');
    }
  }

  Future<void> _salvarManga() async {
    if (_formKey.currentState!.validate()) {
      final dadosManga = {
        'nome_pt': _nomePtController.text.trim(),
        'nome_en': _nomeEnController.text.trim().isEmpty
            ? null
            : _nomeEnController.text.trim(),
        'capitulo': int.tryParse(_capituloController.text) ?? 1,
        'link_url': _linkUrlController.text.trim().isEmpty
            ? null
            : _linkUrlController.text.trim(),
        'status_leitura': _selectedStatus['label'],
        'capa_path': _capaSelecionadaPath ?? 'assets/capa_generica.png',
        'ordem_leitura': 1,
      };

      await DbHelper().insertManga(dadosManga);

      _nomePtController.clear();
      _nomeEnController.clear();
      _linkUrlController.clear();
      _capituloController.text = '1';
      setState(() {
        _selectedStatus = _statusOptions.first;
        _capaSelecionadaPath = null;
      });

      widget.onMangaSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Text(
                  'Adicionar Novo Mangá',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nomePtController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: _buildInputDecoration('Nome em Português', theme),
                validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
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
                decoration: _buildInputDecoration('Capítulo', theme).copyWith(
                  prefixIcon: IconButton(
                    icon: Icon(Icons.remove, color: colorScheme.error),
                    onPressed: () {
                      int val = int.tryParse(_capituloController.text) ?? 1;
                      if (val > 1) {
                        _capituloController.text = (val - 1).toString();
                      }
                    },
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.add, color: colorScheme.secondary),
                    onPressed: () {
                      int val = int.tryParse(_capituloController.text) ?? 0;
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
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _capaSelecionadaPath == null
                        ? theme.dividerColor
                        : colorScheme.primary,
                  ),
                ),
                icon: Icon(
                  _capaSelecionadaPath == null
                      ? Icons.image_search_rounded
                      : Icons.check_circle_rounded,
                  color: _capaSelecionadaPath == null
                      ? Colors.amber
                      : colorScheme.primary,
                ),
                label: Text(
                  _capaSelecionadaPath == null
                      ? 'Escolher Capa'
                      : 'Capa Selecionada',
                  style: TextStyle(
                    color: _capaSelecionadaPath == null
                        ? colorScheme.onSurface.withValues(alpha: 0.5)
                        : colorScheme.primary,
                  ),
                ),
                onPressed: _escolherEProcessarCapa,
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: PopupMenuButton<Map<String, dynamic>>(
                  initialValue: _selectedStatus,
                  color: colorScheme.surfaceContainer,
                  constraints: const BoxConstraints(minWidth: 370),
                  onSelected: (Map<String, dynamic> novoStatus) {
                    setState(() => _selectedStatus = novoStatus);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedStatus['icon'],
                          color: _selectedStatus['color'],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _selectedStatus['label'],
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_drop_down,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ),
                  itemBuilder: (BuildContext context) {
                    return _statusOptions.map((status) {
                      return PopupMenuItem<Map<String, dynamic>>(
                        value: status,
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
                              style: TextStyle(color: colorScheme.onSurface),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _salvarManga,
                child: Text(
                  'Salvar Mangá',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
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
