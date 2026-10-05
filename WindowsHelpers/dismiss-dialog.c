/* dismiss-dialog.exe --program <program> --title <title> --text <message> [--wait-seconds N]
 *
 * Waits for one exact standard dialog of a program and presses its OK button, as a
 * player would. Games such as GTA V show a graphics driver advisory that does not
 * apply under Apple's graphics layer. The title and message must match after runs of
 * white space become one space; any other dialog is left alone. The helper exits after
 * it presses OK, when the program exits, or after N seconds (600 by default).
 * Exit codes: 0 pressed or timed out, 10 usage. */
#include "helpers.h"

/* Copies `text` into `out` with each run of white space as one space, trimmed. */
static void collapse(const wchar_t *text, wchar_t *out, size_t size) {
    size_t n = 0;
    int space = 0;
    for (; *text && n + 1 < size; text++) {
        if (iswspace(*text)) { space = n > 0; continue; }
        if (space && n + 2 < size) out[n++] = L' ';
        space = 0;
        out[n++] = *text;
    }
    out[n] = 0;
}

static int same_text(const wchar_t *a, const wchar_t *b) {
    static wchar_t x[4096], y[4096];
    collapse(a, x, 4096);
    collapse(b, y, 4096);
    return wcscmp(x, y) == 0;
}

struct target { const wchar_t *program, *title, *text; int pressed; };

/* Joins the text of a dialog's static controls, which hold its message. */
static BOOL CALLBACK gather(HWND child, LPARAM data) {
    wchar_t *message = (wchar_t *)data, klass[64], value[2048];
    if (!GetClassNameW(child, klass, 64) || _wcsicmp(klass, L"Static")) return TRUE;
    if (GetWindowTextW(child, value, 2048) > 0 && wcslen(message) + wcslen(value) + 2 < 4096) {
        wcscat(message, L" ");
        wcscat(message, value);
    }
    return TRUE;
}

static BOOL CALLBACK check(HWND window, LPARAM data) {
    struct target *t = (struct target *)data;
    wchar_t klass[64], title[512];
    if (!IsWindowVisible(window) || !GetClassNameW(window, klass, 64) || wcscmp(klass, L"#32770")) return TRUE;
    GetWindowTextW(window, title, 512);
    if (!same_text(title, t->title)) return TRUE;
    static wchar_t path[PATH_CHARS], message[4096];
    if (!window_program(window, path, PATH_CHARS) || !program_matches(path, t->program)) return TRUE;
    message[0] = 0;
    EnumChildWindows(window, gather, (LPARAM)message);
    HWND ok = GetDlgItem(window, IDOK);
    if (!same_text(message, t->text) || !ok || !IsWindowEnabled(ok)) return TRUE;
    t->pressed = PostMessageW(window, WM_COMMAND, MAKEWPARAM(IDOK, BN_CLICKED), (LPARAM)ok);
    say("Pressed OK on \"%ls\".", t->title);
    return !t->pressed;
}

int wmain(int argc, wchar_t **argv) {
    struct target t = { option(argc, argv, L"--program"), option(argc, argv, L"--title"), option(argc, argv, L"--text"), 0 };
    if (!t.program || !t.title || !t.text) return 10;
    DWORD deadline = GetTickCount() + wait_seconds(argc, argv, 600) * 1000;
    say("Watching %ls for \"%ls\".", t.program, t.title);
    int seen = 0;
    while (!t.pressed && (LONG)(deadline - GetTickCount()) > 0) {
        EnumWindows(check, (LPARAM)&t);
        if (program_running(t.program)) seen = 1;
        else if (seen) { say("%ls exited.", t.program); break; }
        Sleep(250);
    }
    return 0;
}
