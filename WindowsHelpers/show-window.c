/* show-window.exe <program>
 *
 * Restores and raises the main window of a running program, such as Battle.net.exe
 * when it was closed to the notification area. The main window is the largest
 * top-level window with a title that no other window owns.
 * Exit codes: 0 shown, 2 no such window, 10 usage. */
#include "helpers.h"

struct search { const wchar_t *program; HWND best; LONGLONG area; };

static BOOL CALLBACK consider(HWND window, LPARAM data) {
    struct search *s = (struct search *)data;
    if (GetWindow(window, GW_OWNER) || GetWindowTextLengthW(window) == 0) return TRUE;
    static wchar_t path[PATH_CHARS];
    if (!window_program(window, path, PATH_CHARS) || !program_matches(path, s->program)) return TRUE;
    RECT r;
    if (!GetWindowRect(window, &r)) return TRUE;
    LONGLONG area = (LONGLONG)(r.right - r.left) * (r.bottom - r.top);
    if (area > s->area) { s->best = window; s->area = area; }
    return TRUE;
}

int wmain(int argc, wchar_t **argv) {
    if (argc != 2) return 10;
    struct search s = { argv[1], NULL, -1 };
    EnumWindows(consider, (LPARAM)&s);
    if (!s.best) { say("No window of %ls.", argv[1]); return 2; }
    ShowWindow(s.best, IsIconic(s.best) ? SW_RESTORE : SW_SHOW);
    SetWindowPos(s.best, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetForegroundWindow(s.best);
    say("Showed the window of %ls.", argv[1]);
    return 0;
}
