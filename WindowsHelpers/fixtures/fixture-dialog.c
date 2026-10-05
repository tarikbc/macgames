/* fixture-dialog.exe <title> <message>: shows a standard OK/Cancel dialog and exits
 * with the button pressed (1 OK, 2 Cancel). Used only by scripts/test-windows-helpers.sh. */
#include "../helpers.h"

int wmain(int argc, wchar_t **argv) {
    if (argc != 3) return 10;
    return MessageBoxW(NULL, argv[2], argv[1], MB_OKCANCEL | MB_ICONWARNING);
}
