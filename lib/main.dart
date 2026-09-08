import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'database/db_helper.dart';
import 'widgets/top_bar.dart';
import 'widgets/manga_form.dart';
import 'widgets/manga_card.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'dart:async';
import 'utils/error_handler.dart';
import 'utils/theme_notifier.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (!kIsWeb) {
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
            await windowManager.setMinimumSize(minSize);

            await windowManager.maximize();
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
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeController.lightTheme,
          darkTheme: ThemeController.darkTheme,
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
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
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
    _scrollController.addListener(_onScroll);
    _carregarLote(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

    // Aguarda 300ms de pausa na digitação antes de disparar a busca
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
                  const SizedBox(height: 12),
                  Text(
                    'Meu Gerenciador de Mangás',
                    style: TextStyle(
                      fontSize: 22,
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
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
                                onDelete: () {
                                  setState(() {
                                    _mangas.removeAt(index);
                                  });
                                  DbHelper().deleteManga(manga['id']);
                                },
                                onUpdate: () =>
                                    _atualizarMangaEspecifico(manga['id']),
                              );
                            },
                            onReorder: (oldIndex, newIndex) {
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
                              color: theme.colorScheme.onSurface.withAlpha(20),
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
