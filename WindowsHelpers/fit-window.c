/* fit-window.exe --program <program> --width W --height H --inset T [--wait-seconds N]
 *
 * Keeps a fullscreen game below the notch of a MacBook screen. W and H are the Mac
 * screen's size in points and T is its safe top inset, also in points. A visible
 * top-level window of the program that covers the whole primary monitor moves down by
 * the inset; windowed sizes are left alone. With the matching Mac driver option the
 * window then counts as fullscreen and the menu bar stays hidden.
 * The helper exits when the program exits, or after N seconds (300 by default) if it
 * never starts. Exit codes: 0 done, 4 the program never started, 10 usage. */
#include "helpers.h"
#include <math.h>

struct fit { const wchar_t *program; double width, height, inset; int moved; };

static int same_rect(RECT a, RECT b) {
    return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom;
}

static BOOL CALLBACK place(HWND window, LPARAM data) {
    struct fit *f = (struct fit *)data;
    if (!IsWindowVisible(window) || IsIconic(window) || GetWindow(window, GW_OWNER)) return TRUE;
    static wchar_t path[PATH_CHARS];
    if (!window_program(window, path, PATH_CHARS) || !program_matches(path, f->program)) return TRUE;
    MONITORINFO info = { .cbSize = sizeof info };
    if (!GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONULL), &info) || !(info.dwFlags & MONITORINFOF_PRIMARY))
        return TRUE;
    RECT monitor = info.rcMonitor, current;
    GetWindowRect(window, &current);
    /* Wine's pixels per Mac point; a monitor of another shape is not the screen we measured. */
    double scale = (monitor.right - monitor.left) / f->width;
    if (fabs((monitor.bottom - monitor.top) - f->height * scale) > 2) return TRUE;
    RECT safe = monitor;
    safe.top += (LONG)ceil(f->inset * scale);
    if (!same_rect(current, monitor)) return TRUE;
    if (SetWindowPos(window, NULL, safe.left, safe.top, safe.right - safe.left, safe.bottom - safe.top,
                     SWP_NOACTIVATE | SWP_NOZORDER)) {
        f->moved++;
        say("Moved the window below the notch: %ld,%ld %ldx%ld.", safe.left, safe.top, safe.right - safe.left, safe.bottom - safe.top);
    }
    return TRUE;
}

int wmain(int argc, wchar_t **argv) {
    const wchar_t *program = option(argc, argv, L"--program"), *w = option(argc, argv, L"--width"),
                  *h = option(argc, argv, L"--height"), *t = option(argc, argv, L"--inset");
    if (!program || !w || !h || !t) return 10;
    struct fit f = { program, wcstod(w, NULL), wcstod(h, NULL), wcstod(t, NULL), 0 };
    if (!(f.width >= 640 && f.height >= 480 && f.inset > 0 && f.inset < f.height / 10)) return 10;
    DWORD deadline = GetTickCount() + wait_seconds(argc, argv, 300) * 1000;
    int seen = 0;
    say("Watching %ls for fullscreen windows.", program);
    for (;;) {
        EnumWindows(place, (LPARAM)&f);
        if (program_running(program)) seen = 1;
        else if (seen) break;
        else if ((LONG)(deadline - GetTickCount()) <= 0) { say("%ls did not start.", program); return 4; }
        Sleep(500);
    }
    say("%ls exited.", program);
    return 0;
}
