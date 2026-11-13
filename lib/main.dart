import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'; // PointerSignalEvent / PointerScrollEvent
import 'package:flutter/services.dart'; // HardwareKeyboard / KeyEvent
import 'package:window_manager/window_manager.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'database/db_helper.dart';
import 'widgets/barra_filtros.dart';
import 'widgets/top_bar.dart';
import 'widgets/manga_form.dart';
import 'widgets/manga_card.dart';
import 'utils/classificacao.dart';
import 'utils/error_handler.dart';
import 'utils/licencas.dart';
import 'utils/lista_paginada.dart';
import 'utils/theme_notifier.dart';
import 'services/importacao_manga_manager.dart';
import 'services/update_service.dart';
import 'controllers/refresh_controller.dart';
import 'widgets/biblioteca_vazia.dart';

// import 'package:webview_cef/webview_cef.dart';
// import 'package:screen_retriever/screen_retriever.dart';

// Controle global de Zoom da interface
final ValueNotifier<double> appZoomNotifier = ValueNotifier<double>(1.0);

// Estado do modificador de zoom (Ctrl; Cmd no macOS): usado para travar o
// scroll da grade enquanto o usuário dá zoom com a roda do mouse
final ValueNotifier<bool> ctrlPressedNotifier = ValueNotifier<bool>(false);

// Retorna true se o modificador de zoom está pressionado
bool _modificadorZoomPressionado() {
  final kb = HardwareKeyboard.instance;
  return defaultTargetPlatform == TargetPlatform.macOS
      ? kb.isMetaPressed
      : kb.isControlPressed;
}

// Handler de teclado: apenas atualiza o estado do Ctrl
bool _atualizarEstadoCtrl(KeyEvent event) {
  final pressed = _modificadorZoomPressionado();
  if (ctrlPressedNotifier.value != pressed) {
    ctrlPressedNotifier.value = pressed;
  }
  return false; // não consome o evento
}

// Ctrl + roda do mouse => altera o zoom
void _zoomComScroll(PointerSignalEvent event) {
  if (event is! PointerScrollEvent) return;
  if (!_modificadorZoomPressionado()) return;

  final dy = event.scrollDelta.dy;
  if (dy == 0) return;

  const passo = 0.1; // mesmo passo do Slider (0.5–2.0 com 15 divisões)
  final novo = appZoomNotifier.value + (dy < 0 ? passo : -passo);
  appZoomNotifier.value = (novo.clamp(0.5, 2.0) * 100).round() / 100;
}

// Chave usada na tabela 'configuracoes' para guardar o zoom
const String _zoomConfigKey = 'zoom';
Timer? _zoomSaveTimer;

// Lê o zoom salvo no banco (se existir) e aplica antes de abrir a tela
Future<void> _carregarZoomSalvo() async {
  try {
    final salvo = await DbHelper().getConfig(_zoomConfigKey);
    final valor = double.tryParse(salvo ?? '');
    if (valor != null) {
      appZoomNotifier.value = valor.clamp(0.5, 2.0).toDouble();
    }
  } catch (e) {
    debugPrint('Erro ao carregar zoom salvo: $e');
  }

  // Só começa a salvar depois de carregar, para não regravar o valor lido
  appZoomNotifier.addListener(_agendarSalvarZoom);
}

// Salva o zoom 500 ms após a última mudança (evita gravar a cada passo do slider/scroll)
void _agendarSalvarZoom() {
  _zoomSaveTimer?.cancel();
  _zoomSaveTimer = Timer(const Duration(milliseconds: 500), () async {
    try {
      await DbHelper().setConfig(
        _zoomConfigKey,
        appZoomNotifier.value.toStringAsFixed(2),
      );
    } catch (e) {
      debugPrint('Erro ao salvar zoom: $e');
    }
  });
}

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

      HardwareKeyboard.instance.addHandler(_atualizarEstadoCtrl);
      // Licença do CEF na tela de licenças (o NOTICES não traz)
      registrarLicencasExtras();

      await setupDatabaseFactory();
      await ThemeController.initTheme();
      await _carregarZoomSalvo();

      if (!kIsWeb) {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          await windowManager.ensureInitialized();

          const Size minSize = Size(400, 600);

          WindowOptions windowOptions = const WindowOptions(
            title: 'Onde Parei',
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

      runApp(const OndePareiApp());

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

class OndePareiApp extends StatelessWidget {
  const OndePareiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeNotifier,
      builder: (_, currentMode, _) {
        return ValueListenableBuilder<double>(
          valueListenable: appZoomNotifier,
          builder: (context, zoom, _) {
            return MaterialApp(
              title: 'Onde Parei',
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
                        // Escuta Ctrl + roda do mouse em todo o app
                        child: Listener(
                          onPointerSignal: _zoomComScroll,
                          child: child!,
                        ),
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
  // Lotes de 30 pela posição no banco; a exclusão passa pela lista para o
  // próximo lote não pular um mangá (ver ListaPaginada)
  final ListaPaginada<Map<String, dynamic>> _lista = ListaPaginada(
    tamanhoDoLote: 30,
  );
  List<Map<String, dynamic>> get _mangas => _lista.itens;
  bool get _hasMore => _lista.temMais;
  bool _isLoading = false;

  /// Busca e filtros de tipo e status da lista
  FiltroLista _filtro = const FiltroLista();
  Timer? _debounceTimer;

  /// Banco do Manga Manager neste computador, para a lista vazia oferecer a
  /// importação (só no Windows e no Linux)
  File? _bancoDoMangaManager;

  @override
  void initState() {
    super.initState();
    ctrlPressedNotifier.addListener(_onCtrlChanged);
    globalRefreshController.addListener(_onRefreshRequested);
    _scrollController.addListener(_onScroll);
    _carregarLote(refresh: true);
    ImportacaoMangaManager.localizarBanco().then((banco) {
      if (mounted) setState(() => _bancoDoMangaManager = banco);
    });

    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _logDisplayMetrics();
    // });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        UpdateService.checkUpdate(context);
      }
    });
  }

  // Future<void> _logDisplayMetrics() async {
  //   if (kIsWeb) return;

  //   final pixelRatio = MediaQuery.devicePixelRatioOf(context);
  //   final logicalSize = MediaQuery.sizeOf(context);

  //   try {
  //     final windowSize = await windowManager.getSize();
  //     final display = await screenRetriever.getPrimaryDisplay();

  //     debugPrint('\n========================================');
  //     debugPrint(
  //       '🖥️  MÉTRICAS DE DISPLAY E JANELA (${Platform.operatingSystem})',
  //     );
  //     debugPrint('========================================');
  //     debugPrint('Resolução real do Monitor (Display): ${display.size}');
  //     debugPrint('Tamanho físico da Janela (WindowManager): $windowSize');
  //     debugPrint('Tamanho lógico da Tela (MediaQuery): $logicalSize');
  //     debugPrint('Proporção de Escala (Device Pixel Ratio): $pixelRatio');
  //     debugPrint('========================================\n');
  //   } catch (e) {
  //     debugPrint('Erro ao capturar métricas: $e');
  //   }
  // }

  @override
  void dispose() {
    ctrlPressedNotifier.removeListener(_onCtrlChanged);
    globalRefreshController.removeListener(_onRefreshRequested);
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Reconstrói a tela quando o Ctrl é pressionado/solto (troca o physics da grade)
  void _onCtrlChanged() {
    if (mounted) setState(() {});
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
      _mudarFiltro(_filtro.copiarCom(busca: query));
    });
  }

  /// Troca a busca ou os filtros e recarrega a lista do começo.
  void _mudarFiltro(FiltroLista novo) {
    if (novo == _filtro) return;
    setState(() => _filtro = novo);
    _carregarLote(refresh: true);
  }

  Future<void> _carregarLote({bool refresh = false}) async {
    // Recarregar não espera o lote que está chegando: ele é da busca ou do
    // filtro de antes e é descartado pela geração da lista. Antes, a troca
    // era ignorada e a lista ficava com o resultado antigo
    if (refresh) {
      _lista.reiniciar();
    } else if (_isLoading) {
      return;
    }
    _isLoading = true;
    final geracao = _lista.geracao;

    try {
      final dadosNovos = await DbHelper().getMangas(
        limit: _lista.tamanhoDoLote,
        offset: _lista.offset,
        filtro: _filtro,
      );

      // Uma recarga mais nova cuida do _isLoading
      if (!mounted || geracao != _lista.geracao) return;
      setState(() {
        _lista.acrescentarLote(dadosNovos, geracao: geracao);
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted || geracao != _lista.geracao) return;
      setState(() => _isLoading = false);
      ErrorHandler.showFatalError(context, error, stackTrace);
    }
  }

  Future<void> _atualizarMangaEspecifico(int id) async {
    final filtro = _filtro;
    final geracao = _lista.geracao;
    try {
      final atualizado = await DbHelper().getMangaNoFiltro(id, filtro);
      // A lista foi recarregada enquanto isso (busca ou filtro novos)
      if (!mounted || geracao != _lista.geracao) return;

      final index = _mangas.indexWhere((m) => m['id'] == id);
      if (index == -1) return;
      if (atualizado != null) {
        setState(() => _mangas[index] = atualizado);
        return;
      }

      // Editado, não combina mais com a busca ou o filtro: sai da lista como
      // numa exclusão, para o próximo lote não pular um item
      final nome = _mangas[index]['nome_pt'];
      setState(() => _lista.remover(index));
      if (filtro.restringe) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"$nome" saiu da lista: não combina mais com a busca ou os '
              'filtros.',
            ),
          ),
        );
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
                        'Minhas Leituras',
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
                          message: 'Zoom da Interface (Ctrl + scroll)',
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
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 204 : 16,
                      isDesktop ? 0 : 10,
                      isDesktop ? 204 : 16,
                      4,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BarraFiltros(
                        filtro: _filtro,
                        aoMudar: _mudarFiltro,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _mangas.isEmpty && _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _mangas.isEmpty && _filtro.restringe
                        ? _semResultados(theme)
                        : _mangas.isEmpty && !_isLoading && !_hasMore
                        ? BibliotecaVazia(
                            bancoDoMangaManager: _bancoDoMangaManager,
                          )
                        : ReorderableGridView.builder(
                            controller: _scrollController,
                            // Trava o scroll da grade enquanto o Ctrl está pressionado
                            physics: ctrlPressedNotifier.value
                                ? const NeverScrollableScrollPhysics()
                                : null,
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
                                  // Posição pelo id, na hora: o index do
                                  // card pode ter ficado velho
                                  final posicao = _mangas.indexWhere(
                                    (m) => m['id'] == manga['id'],
                                  );
                                  if (posicao < 0) return;
                                  final mangaRemovido = _mangas[posicao];
                                  final geracao = _lista.geracao;
                                  setState(() => _lista.remover(posicao));

                                  try {
                                    await DbHelper().deleteManga(manga['id']);
                                  } catch (error, stackTrace) {
                                    if (!mounted) return;
                                    // Lista recarregada no meio: ela já veio
                                    // do banco, com o item
                                    if (geracao == _lista.geracao) {
                                      setState(() {
                                        _lista.desfazerRemocao(
                                          posicao,
                                          mangaRemovido,
                                        );
                                      });
                                    }

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
                              // A ordem é regravada a partir da lista em
                              // memória, que precisa ser a biblioteca inteira
                              if (_filtro.restringe || _hasMore) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Não é possível alterar a ordem durante uma busca, com filtros ou antes de carregar a lista inteira.',
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

  /// Lista vazia por causa da busca ou dos filtros.
  Widget _semResultados(ThemeData theme) {
    final cor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: cor),
            const SizedBox(height: 12),
            Text(
              _filtro.temFiltro
                  ? 'Nada encontrado com esses filtros.'
                  : 'Nada encontrado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cor, fontSize: 16),
            ),
            if (_filtro.temFiltro) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _mudarFiltro(_filtro.semFiltros()),
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Limpar filtros'),
              ),
            ],
          ],
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
