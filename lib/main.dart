import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'database/db_helper.dart';
import 'widgets/top_bar.dart';
import 'widgets/manga_form.dart';
import 'widgets/manga_card.dart';
import 'utils/error_handler.dart';
import 'utils/theme_notifier.dart';
import 'services/update_service.dart';
import 'controllers/refresh_controller.dart';
import 'package:screen_retriever/screen_retriever.dart';

// Controle global de Zoom da interface
final ValueNotifier<double> appZoomNotifier = ValueNotifier<double>(1.0);

Future<void> setupDatabaseFactory() async {
  try {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    debugPrint('Database factory inicializada com sucesso.');
  } catch (e, stackTrace) {
    debugPrint('ERRO CRÍTICO DB: Falha ao inicializar a factory: $e');
    debugPrint(stackTrace.toString());
  }
}

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await setupDatabaseFactory();

      if (!kIsWeb) {
        // Força a escala do Windows (1.25x) como padrão ao rodar no Linux
        if (Platform.isLinux) {
          appZoomNotifier.value = 1.25;
        }

        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          await windowManager.ensureInitialized();

          const Size minSize = Size(400, 600);

          WindowOptions windowOptions = const WindowOptions(
            title: 'Manga Manager',
            size: Size(1024, 700),
            minimumSize: minSize,
            center: true,
            skipTaskbar: false,
            titleBarStyle: TitleBarStyle.normal,
          );

          windowManager.waitUntilReadyToShow(windowOptions, () async {
            await windowManager.maximize(); // Mantido conforme solicitado
            await windowManager.show();
            await windowManager.focus();
          });
        }
      }

      runApp(const MangaManagerApp());

      ErrorWidget.builder = (FlutterErrorDetails details) {
        return Material(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 50),
                  const SizedBox(height: 16),
                  Text(
                    'Erro na Interface:\n${details.exception}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        );
      };
    },
    (error, stack) {
      debugPrint('Erro não tratado (Zoned): $error');
    },
  );
}

class MangaManagerApp extends StatelessWidget {
  const MangaManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeNotifier,
      builder: (_, currentMode, _) {
        return ValueListenableBuilder<double>(
          valueListenable: appZoomNotifier,
          builder: (context, zoom, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              theme: ThemeController.lightTheme,
              darkTheme: ThemeController.darkTheme,
              // O builder aplica o zoom global redimensionando a área lógica do app
              builder: (context, child) {
                final mediaQuery = MediaQuery.of(context);
                final size = mediaQuery.size;
                final scaledSize = Size(size.width / zoom, size.height / zoom);

                return MediaQuery(
                  data: mediaQuery.copyWith(
                    size: scaledSize,
                    devicePixelRatio: mediaQuery.devicePixelRatio * zoom,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: scaledSize.width,
                      height: scaledSize.height,
                      child: Transform.scale(
                        scale: zoom,
                        alignment: Alignment.center,
                        child: child!,
                      ),
                    ),
                  ),
                );
              },
              home: const MainScreen(),
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.trackpad,
                },
              ),
            );
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  bool _showForm = false;
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _mangas = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 30;

  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    globalRefreshController.addListener(_onRefreshRequested);
    _scrollController.addListener(_onScroll);
    _carregarLote(refresh: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logDisplayMetrics();
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        UpdateService.checkUpdate(context);
      }
    });
  }

  Future<void> _logDisplayMetrics() async {
    if (kIsWeb) return;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final logicalSize = MediaQuery.sizeOf(context);

    try {
      final windowSize = await windowManager.getSize();
      final display = await screenRetriever.getPrimaryDisplay();

      debugPrint('\n========================================');
      debugPrint(
        '🖥️  MÉTRICAS DE DISPLAY E JANELA (${Platform.operatingSystem})',
      );
      debugPrint('========================================');
      debugPrint('Resolução real do Monitor (Display): ${display.size}');
      debugPrint('Tamanho físico da Janela (WindowManager): $windowSize');
      debugPrint('Tamanho lógico da Tela (MediaQuery): $logicalSize');
      debugPrint('Proporção de Escala (Device Pixel Ratio): $pixelRatio');
      debugPrint('========================================\n');
    } catch (e) {
      debugPrint('Erro ao capturar métricas: $e');
    }
  }

  @override
  void dispose() {
    globalRefreshController.removeListener(_onRefreshRequested);
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onRefreshRequested() {
    _carregarLote(refresh: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      if (!_isLoading && _hasMore) {
        _carregarLote();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query;
      });
      _carregarLote(refresh: true);
    });
  }

  Future<void> _carregarLote({bool refresh = false}) async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      if (refresh) {
        _offset = 0;
        _mangas.clear();
        _hasMore = true;
      }

      final dadosNovos = await DbHelper().getMangas(
        limit: _limit,
        offset: _offset,
        query: _searchQuery,
      );

      if (mounted) {
        setState(() {
          _offset += dadosNovos.length;
          if (dadosNovos.length < _limit) _hasMore = false;
          _mangas.addAll(dadosNovos);
          _isLoading = false;
        });
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.showFatalError(context, error, stackTrace);
      }
    }
  }

  Future<void> _atualizarMangaEspecifico(int id) async {
    try {
      final db = await DbHelper().database;
      final resultado = await db.query(
        'mangas',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (resultado.isNotEmpty) {
        final index = _mangas.indexWhere((m) => m['id'] == id);
        if (index != -1) {
          setState(() {
            _mangas[index] = resultado.first;
          });
        }
      }
    } catch (error, stackTrace) {
      if (mounted) {
        ErrorHandler.showFatalError(context, error, stackTrace);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;
    final theme = Theme.of(context);

    return Scaffold(
      body: GeometricBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Meu Gerenciador de Mangás',
                        style: TextStyle(
                          fontSize: 22,
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // --- CONTROLE DE ZOOM ADICIONADO AQUI ---
                      if (isDesktop) ...[
                        Tooltip(
                          message: 'Zoom da Interface',
                          child: Icon(
                            Icons.zoom_in,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: appZoomNotifier,
                          builder: (context, zoom, _) {
                            return SizedBox(
                              width: 120,
                              child: Slider(
                                value: zoom,
                                min: 0.5,
                                max: 2.0,
                                divisions: 15,
                                activeColor: theme.colorScheme.primary,
                                label: '${(zoom * 100).toInt()}%',
                                onChanged: (val) => appZoomNotifier.value = val,
                              ),
                            );
                          },
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: appZoomNotifier,
                          builder: (context, zoom, _) {
                            return IconButton(
                              icon: const Icon(Icons.restore, size: 20),
                              tooltip: 'Restaurar Zoom',
                              onPressed: () {
                                appZoomNotifier.value =
                                    (!kIsWeb && Platform.isLinux) ? 1.25 : 1.0;
                              },
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                  TopBar(
                    showForm: _showForm,
                    isDesktop: isDesktop,
                    onToggleForm: () {
                      setState(() => _showForm = !_showForm);
                      if (!isDesktop && _showForm) _showMobileForm(context);
                    },
                    onToggleTheme: ThemeController.toggleTheme,
                    onSearchChanged: _onSearchChanged,
                  ),
                  Expanded(
                    child: _mangas.isEmpty && _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ReorderableGridView.builder(
                            controller: _scrollController,
                            addAutomaticKeepAlives: true,
                            addRepaintBoundaries: true,
                            padding: const EdgeInsets.all(8.0),
                            dragWidgetBuilder: (int index, Widget child) {
                              return TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                builder: (context, animValue, animChild) {
                                  final double scale = lerpDouble(
                                    1,
                                    1.05,
                                    animValue,
                                  )!;
                                  final double rotation = lerpDouble(
                                    0,
                                    0.05,
                                    animValue,
                                  )!;
                                  return Transform.scale(
                                    scale: scale,
                                    child: Transform.rotate(
                                      angle: rotation,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: animValue),
                                            width: 3 * animValue,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.3 * animValue,
                                              ),
                                              blurRadius: 15 * animValue,
                                              spreadRadius: 2 * animValue,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: animChild,
                                      ),
                                    ),
                                  );
                                },
                                child: child,
                              );
                            },
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  mainAxisExtent: 515,
                                ),
                            itemCount: _mangas.length,
                            itemBuilder: (context, index) {
                              final manga = _mangas[index];
                              return MangaCardWidget(
                                key: ValueKey(manga['id']),
                                manga: manga,
                                onDelete: () async {
                                  final mangaRemovido = _mangas[index];
                                  setState(() {
                                    _mangas.removeAt(index);
                                  });

                                  try {
                                    await DbHelper().deleteManga(manga['id']);
                                  } catch (error, stackTrace) {
                                    setState(() {
                                      _mangas.insert(index, mangaRemovido);
                                    });

                                    if (context.mounted) {
                                      ErrorHandler.showFatalError(
                                        context,
                                        error,
                                        stackTrace,
                                      );
                                    }
                                  }
                                },
                                onUpdate: () =>
                                    _atualizarMangaEspecifico(manga['id']),
                              );
                            },
                            onReorder: (oldIndex, newIndex) {
                              if (_searchQuery.isNotEmpty || _hasMore) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Não é possível alterar a ordem durante uma busca ou antes de carregar todos os mangás.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              setState(() {
                                final item = _mangas.removeAt(oldIndex);
                                _mangas.insert(newIndex, item);
                              });
                              DbHelper().reordenarMangas(_mangas);
                            },
                          ),
                  ),
                ],
              ),
              if (isDesktop && _showForm)
                GestureDetector(
                  onTap: () => setState(() => _showForm = false),
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: 400,
                          constraints: const BoxConstraints(maxHeight: 600),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.08,
                              ),
                            ),
                          ),
                          child: AddMangaFormWidget(
                            onMangaSaved: () {
                              _carregarLote(refresh: true);
                              setState(() => _showForm = false);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMobileForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: AddMangaFormWidget(
            onMangaSaved: () {
              _carregarLote(refresh: true);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    ).whenComplete(() => setState(() => _showForm = false));
  }
}
