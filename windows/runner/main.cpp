#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"


#include "webview_cef/webview_cef_plugin_c_api.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,_In_ wchar_t *command_line, _In_ int show_command) {
  
  int exit_code = initCEFProcesses(instance);
  if (exit_code >= 0) {
    return exit_code;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"manga_manager", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
    handleWndProcForCEF(msg.hwnd, msg.message, msg.wParam, msg.lParam);
  }

  // Fecha a janela e o engine do Flutter, se ainda não fecharam (o
  // windowManager.destroy() só encerra o loop). Os plugins rodam aqui os
  // próprios destrutores.
  window.Destroy();

  // Daqui em diante o processo só destruiria as variáveis estáticas dos
  // plugins, e duas delas derrubavam o app em todo fechamento:
  //  - o flutter_inappwebview_windows 0.6.0 guarda em estáticas uma
  //    DispatcherQueueController e um Compositor que ele nunca desliga
  //    (ShutdownQueueAsync); liberados no fim do processo, davam 0xc0000005
  //    em coremessaging.dll;
  //  - o webview_cef guarda a thread de vsync num std::thread estático; se
  //    ela ainda estiver rodando, o C++ chama std::terminate (0xc0000409).
  // Nada mais precisa rodar: os dados já foram gravados pelo app e o WebView2
  // roda em outros processos, que fecham sozinhos. Por isso o processo
  // termina aqui, sem esses destrutores.
  ::fflush(stdout);
  ::fflush(stderr);
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
