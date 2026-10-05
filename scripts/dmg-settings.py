# dmgbuild settings for the MacGames installer window. dmgbuild writes the layout and
# the background into the volume's .DS_Store directly, with no Finder scripting.
# scripts/release.sh passes: -D app=<path to MacGames.app> -D background=<tiff>
import os

application = defines["app"]
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

# Icon centers match scripts/render-dmg-background.swift: both stand on the card,
# the drag chevrons run between them, and the names fall in the card's label row.
icon_locations = {appname: (190, 236), "Applications": (470, 236)}
background = defines["background"]

# 440 points of art plus Finder's title and tab bars on macOS 27 (68 points).
window_rect = ((200, 120), (660, 508))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
text_size = 13
icon_size = 112
hide_extension = [appname]
