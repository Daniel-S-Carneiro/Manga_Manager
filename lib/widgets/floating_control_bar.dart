import 'package:flutter/material.dart';

class FloatingControlBar extends StatelessWidget {
  final ValueNotifier<double> posTop;
  final ValueNotifier<double> posLeft;
  final ValueNotifier<bool> isVertical;
  final Size screenSize;
  final VoidCallback onPanEnd;
  final VoidCallback onBack;
  final VoidCallback onReload;
  final VoidCallback onFullScreen;
  final VoidCallback onToggleOrientation;

  const FloatingControlBar({
    super.key,
    required this.posTop,
    required this.posLeft,
    required this.isVertical,
    required this.screenSize,
    required this.onPanEnd,
    required this.onBack,
    required this.onReload,
    required this.onFullScreen,
    required this.onToggleOrientation,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([posTop, posLeft, isVertical]),
      builder: (context, child) {
        return Positioned(
          top: posTop.value.clamp(0.0, screenSize.height - 60.0),
          left: posLeft.value.clamp(0.0, screenSize.width - 60.0),
          child: GestureDetector(
            onPanUpdate: (details) {
              posLeft.value = (posLeft.value + details.delta.dx).clamp(
                0.0,
                screenSize.width - 60.0,
              );
              posTop.value = (posTop.value + details.delta.dy).clamp(
                0.0,
                screenSize.height - 60.0,
              );
            },
            onPanEnd: (details) => onPanEnd(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Flex(
                  direction: isVertical.value ? Axis.vertical : Axis.horizontal,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        isVertical.value
                            ? Icons.drag_handle
                            : Icons.drag_indicator,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Voltar',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                      onPressed: onBack,
                    ),
                    SizedBox(
                      width: isVertical.value ? 0 : 4,
                      height: isVertical.value ? 4 : 0,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Recarregar',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                      onPressed: onReload,
                    ),
                    SizedBox(
                      width: isVertical.value ? 0 : 4,
                      height: isVertical.value ? 4 : 0,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Tela Cheia (F11)',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                      onPressed: onFullScreen,
                    ),
                    SizedBox(
                      width: isVertical.value ? 0 : 4,
                      height: isVertical.value ? 4 : 0,
                    ),
                    IconButton(
                      icon: Icon(
                        isVertical.value
                            ? Icons.view_column_outlined
                            : Icons.view_stream_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: isVertical.value
                          ? 'Girar para Horizontal'
                          : 'Girar para Vertical',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                      onPressed: onToggleOrientation,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
