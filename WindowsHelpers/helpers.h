/* Shared code for the MacGames Windows helpers. Each helper is one small console
 * program that runs inside a game's Wine prefix, next to the game. */
#ifndef MACGAMES_HELPERS_H
#define MACGAMES_HELPERS_H

#define WIN32_LEAN_AND_MEAN
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <tlhelp32.h>
#include <wchar.h>
#include <wctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#define PATH_CHARS 32768

/* The file name part of a Windows path. */
static inline const wchar_t *file_name(const wchar_t *path) {
    const wchar_t *slash = wcsrchr(path, L'\\');
    return slash ? slash + 1 : path;
}

/* A program given as a full path matches only that path; a bare file name matches
 * any program with that name. Windows paths ignore case. */
static inline int program_matches(const wchar_t *path, const wchar_t *program) {
    if (wcschr(program, L'\\')) return _wcsicmp(path, program) == 0;
    return _wcsicmp(file_name(path), program) == 0;
}

/* The full path of the program that owns `window`. */
static inline int window_program(HWND window, wchar_t *path, DWORD size) {
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return 0;
    BOOL ok = QueryFullProcessImageNameW(process, 0, path, &size);
    CloseHandle(process);
    return ok;
}

/* Whether a process of `program` runs in this prefix now. */
static inline int program_running(const wchar_t *program) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    PROCESSENTRY32W entry = { .dwSize = sizeof entry };
    int found = 0;
    for (BOOL more = Process32FirstW(snapshot, &entry); more && !found; more = Process32NextW(snapshot, &entry))
        found = _wcsicmp(entry.szExeFile, file_name(program)) == 0;
    CloseHandle(snapshot);
    return found;
}

/* The value after `--name`, or NULL. */
static inline const wchar_t *option(int argc, wchar_t **argv, const wchar_t *name) {
    for (int i = 1; i + 1 < argc; i++)
        if (wcscmp(argv[i], name) == 0) return argv[i + 1];
    return NULL;
}

/* Watchers wait for their program this long when the command line names no limit. */
static inline DWORD wait_seconds(int argc, wchar_t **argv, DWORD fallback) {
    const wchar_t *value = option(argc, argv, L"--wait-seconds");
    return value ? (DWORD)wcstoul(value, NULL, 10) : fallback;
}

static inline void say(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    putchar('\n');
    fflush(stdout);
}

#endif
