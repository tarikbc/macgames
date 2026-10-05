/* display-mode.exe
 *
 * Prints the primary display's current mode as Windows programs see it, as
 * "<width> <height>". With Wine's Retina mode off this is the Mac's size in points.
 * Exit codes: 0 printed, 2 no mode, 3 a size no game uses. */
#include "helpers.h"

int wmain(void) {
    DEVMODEW mode = { .dmSize = sizeof mode };
    if (!EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &mode)) return 2;
    if (mode.dmPelsWidth < 640 || mode.dmPelsHeight < 480 || mode.dmPelsWidth > 16384 || mode.dmPelsHeight > 16384) return 3;
    say("%lu %lu", mode.dmPelsWidth, mode.dmPelsHeight);
    return 0;
}
