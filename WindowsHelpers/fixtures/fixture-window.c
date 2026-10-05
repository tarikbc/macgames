/* fixture-window.exe <seconds>: covers the primary monitor with a borderless window
 * like a fullscreen game, then prints where the window ended up as
 * "<left> <top> <width> <height>". Used only by scripts/test-windows-helpers.sh. */
#include "../helpers.h"

int wmain(int argc, wchar_t **argv) {
    if (argc != 2) return 10;
    WNDCLASSW klass = { .lpfnWndProc = DefWindowProcW, .hInstance = GetModuleHandleW(NULL),
                        .lpszClassName = L"MacGamesFixture", .hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH) };
    RegisterClassW(&klass);
    MONITORINFO info = { .cbSize = sizeof info };
    GetMonitorInfoW(MonitorFromPoint((POINT){0, 0}, MONITOR_DEFAULTTOPRIMARY), &info);
    RECT m = info.rcMonitor;
    HWND window = CreateWindowW(klass.lpszClassName, L"Fixture", WS_POPUP | WS_VISIBLE, m.left, m.top,
                                m.right - m.left, m.bottom - m.top, NULL, NULL, klass.hInstance, NULL);
    if (!window) return 11;
    DWORD end = GetTickCount() + (DWORD)wcstoul(argv[1], NULL, 10) * 1000;
    while ((LONG)(end - GetTickCount()) > 0) {
        MSG message;
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
        Sleep(20);
    }
    RECT r;
    GetWindowRect(window, &r);
    say("%ld %ld %ld %ld", r.left, r.top, r.right - r.left, r.bottom - r.top);
    return 0;
}
